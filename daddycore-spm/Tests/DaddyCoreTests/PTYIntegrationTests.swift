import XCTest
@testable import DaddyCore
import Foundation

final class PTYIntegrationTests: XCTestCase {

    func testClaudeCodeLaunchAndDetectReady() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sessionManager = SessionManager()
        let session = try sessionManager.createSession(
            projectID: "test-project",
            workUnitID: "test-work",
            agent: .claude,
            cwd: tempDir
        )

        XCTAssertEqual(session.agent, .claude)
        XCTAssertEqual(session.state, .launching)

        try sessionManager.launchSession(session)

        let launchedSession = try XCTUnwrap(sessionManager.session(session.id))
        XCTAssertEqual(launchedSession.state, .ready)

        try sessionManager.terminateSession(session.id)
    }

    func testSessionOutputCapture() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let ptyProcess = PTYProcess(
            executablePath: "/bin/echo",
            arguments: ["hello world"],
            cwd: tempDir
        )

        var capturedOutput = ""
        ptyProcess.registerOutputCallback { output in
            capturedOutput = output
        }

        try ptyProcess.launch()

        Thread.sleep(forTimeInterval: 0.5)

        XCTAssert(capturedOutput.contains("hello world"), "Expected output to contain 'hello world', got: '\(capturedOutput)'")
    }

    func testAdapterLaunchArgs() {
        let claudeAdapter = ClaudeAdapter()
        let args = claudeAdapter.launchArgs(
            cwd: FileManager.default.temporaryDirectory,
            model: ModelRef(agent: .claude, rawValue: "opus"),
            approvalPolicy: .safeAuto
        )

        XCTAssert(args.contains("--permission-mode"))
        XCTAssert(args.contains("acceptEdits"))
        XCTAssert(args.contains("--model"))
        XCTAssert(args.contains("opus"))
    }

    func testClaudeModelFlagValues() {
        let adapter = ClaudeAdapter()

        XCTAssertEqual(adapter.modelFlagValue(for: "opus"), "opus")
        XCTAssertEqual(adapter.modelFlagValue(for: "Opus"), "opus")
        XCTAssertEqual(adapter.modelFlagValue(for: "SONNET"), "sonnet")
        XCTAssertNil(adapter.modelFlagValue(for: "unknown-model"))
    }

    func testStateDetection() {
        let claudeAdapter = ClaudeAdapter()

        let readyState = claudeAdapter.detectState(fromRecentOutput: "claude > ")
        XCTAssertEqual(readyState, .ready)

        let workingState = claudeAdapter.detectState(fromRecentOutput: "thinking... processing...")
        XCTAssertEqual(workingState, .working)

        let rateLimitedState = claudeAdapter.detectState(fromRecentOutput: "rate-limited")
        XCTAssertEqual(rateLimitedState, .rateLimited)
    }
}
