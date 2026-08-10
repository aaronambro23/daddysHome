import XCTest
@testable import DaddyCore

final class WorkflowStateTests: XCTestCase {

    func testProjectDiscovery() {
        let stateManager = WorkflowStateManager()
        let projects = stateManager.discoverProjects()

        XCTAssertGreaterThan(projects.count, 0, "Should discover at least one project in ~/Documents")

        let firstProject = projects.first
        XCTAssertNotNil(firstProject)
        XCTAssertFalse(firstProject?.name.isEmpty ?? true)
    }

    func testAddSession() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stateManager = WorkflowStateManager()

        let session = Session(
            projectID: "test-project",
            workUnitID: "test-work",
            agent: .claude,
            model: ModelRef(agent: .claude, rawValue: "opus"),
            cwd: tempDir
        )

        stateManager.addSession(session)

        let retrievedSession = stateManager.getSession(session.id)
        XCTAssertNotNil(retrievedSession)
        XCTAssertEqual(retrievedSession?.id, session.id)
        XCTAssertEqual(retrievedSession?.agent, .claude)
    }

    func testUpdateSessionState() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stateManager = WorkflowStateManager()

        let session = Session(
            projectID: "test-project",
            workUnitID: "test-work",
            agent: .claude,
            cwd: tempDir
        )

        stateManager.addSession(session)

        stateManager.updateSessionState(session.id, newState: .working)

        let updatedSession = stateManager.getSession(session.id)
        XCTAssertEqual(updatedSession?.agentState, .working)
    }

    func testFocusManagement() {
        let stateManager = WorkflowStateManager()

        stateManager.setFocus(projectID: "project-1", workUnitID: "work-1", sessionID: "session-1")

        let focus = stateManager.getFocus()
        XCTAssertEqual(focus.projectID, "project-1")
        XCTAssertEqual(focus.workUnitID, "work-1")
        XCTAssertEqual(focus.sessionID, "session-1")
    }

    func testRateLimitedAgentDetection() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stateManager = WorkflowStateManager()

        let claudeSession = Session(
            projectID: "test",
            workUnitID: "work",
            agent: .claude,
            cwd: tempDir
        )
        stateManager.addSession(claudeSession)
        stateManager.updateSessionState(claudeSession.id, newState: .rateLimited)

        let rateLimited = stateManager.getRateLimitedAgents()
        XCTAssert(rateLimited.contains(.claude))
    }

    func testWorkflowStatePersistence() {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test-state.json")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stateManager1 = WorkflowStateManager(stateFile: tempFile)
        let session = Session(
            projectID: "test",
            workUnitID: "work",
            agent: .codex,
            cwd: tempDir
        )
        stateManager1.addSession(session)

        let stateManager2 = WorkflowStateManager(stateFile: tempFile)
        let retrievedSession = stateManager2.getSession(session.id)

        XCTAssertNotNil(retrievedSession)
        XCTAssertEqual(retrievedSession?.agent, .codex)
    }

    func testAgentStateEncodingDecoding() {
        let states: [AgentState] = [
            .launching,
            .ready,
            .working,
            .rateLimited,
            .error("Test error"),
            .exited(exitCode: 1),
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for state in states {
            do {
                let encoded = try encoder.encode(state)
                let decoded = try decoder.decode(AgentState.self, from: encoded)
                XCTAssertEqual(state, decoded, "State \(state) should roundtrip through JSON")
            } catch {
                XCTFail("Failed to encode/decode state \(state): \(error)")
            }
        }
    }
}
