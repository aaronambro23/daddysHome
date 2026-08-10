import XCTest
@testable import DaddyCore

final class MarkdownWriterTests: XCTestCase {

    func testWorkUnitDirectoryCreation() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let writer = MarkdownWriter(workflowRoot: tempDir)
        let workUnitDir = writer.getWorkUnitDirectory(project: "test-project", workUnit: "test-work")

        XCTAssert(FileManager.default.fileExists(atPath: workUnitDir.path))
    }

    func testSnapshotWriting() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let writer = MarkdownWriter(workflowRoot: tempDir)

        var snapshot = WorkUnitSnapshot()
        snapshot.goal = "Fix authentication bug"
        snapshot.currentState = "In progress"
        snapshot.whatWasDone = ["Identified root cause", "Implemented fix"]
        snapshot.changes = ["auth.swift: Updated session handling"]

        try writer.writeSnapshot(project: "test-project", workUnit: "test-work", snapshot: snapshot)

        let workUnitDir = writer.getWorkUnitDirectory(project: "test-project", workUnit: "test-work")
        let contents = try FileManager.default.contentsOfDirectory(at: workUnitDir, includingPropertiesForKeys: nil)

        let mdFiles = contents.filter { $0.pathExtension == "md" }
        XCTAssertEqual(mdFiles.count, 1)

        let content = try String(contentsOf: mdFiles[0], encoding: .utf8)
        XCTAssert(content.contains("Fix authentication bug"))
        XCTAssert(content.contains("Identified root cause"))
    }

    func testDoneFileWriting() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let writer = MarkdownWriter(workflowRoot: tempDir)

        var snapshot = WorkUnitSnapshot()
        snapshot.goal = "Complete feature X"
        snapshot.whatWasDone = ["Implemented UI", "Added tests", "Deployed"]
        snapshot.agentsUsed = ["Claude/Opus"]

        try writer.writeDone(project: "test-project", workUnit: "test-work", snapshot: snapshot)

        let workUnitDir = writer.getWorkUnitDirectory(project: "test-project", workUnit: "test-work")
        let donePath = workUnitDir.appendingPathComponent("DONE.md")

        XCTAssert(FileManager.default.fileExists(atPath: donePath.path))

        let content = try String(contentsOf: donePath, encoding: .utf8)
        XCTAssert(content.contains("✅ DONE"))
        XCTAssert(content.contains("Complete feature X"))
    }

    func testIsDoneDetection() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let writer = MarkdownWriter(workflowRoot: tempDir)

        XCTAssertFalse(writer.isDone(project: "test-project", workUnit: "test-work"))

        var snapshot = WorkUnitSnapshot()
        try writer.writeDone(project: "test-project", workUnit: "test-work", snapshot: snapshot)

        XCTAssert(writer.isDone(project: "test-project", workUnit: "test-work"))
    }

    func testRecentSnapshotsRetrieval() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let writer = MarkdownWriter(workflowRoot: tempDir)

        var snapshot = WorkUnitSnapshot()
        snapshot.goal = "Test goal"

        for _ in 0..<3 {
            try writer.writeSnapshot(project: "test-project", workUnit: "test-work", snapshot: snapshot)
            Thread.sleep(forTimeInterval: 0.1)
        }

        let recent = writer.getRecentSnapshots(project: "test-project", workUnit: "test-work", limit: 5)
        XCTAssertEqual(recent.count, 3)
    }
}
