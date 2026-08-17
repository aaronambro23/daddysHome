import XCTest
@testable import DaddyCore

final class HEXWatcherTests: XCTestCase {
    func testEmitsOnlyNewDaddyRecordingsAfterAtomicReplacement() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        try fixture.write([
            fixture.entry(id: "existing", text: "old command", app: "DaddyApp", at: 1),
        ])

        let watcher = try XCTUnwrap(HEXWatcher(historyURL: fixture.historyURL))
        defer { watcher.stop() }

        let received = expectation(description: "new Daddy recording")
        received.assertForOverFulfill = true
        watcher.start { text in
            XCTAssertEqual(text, "Launch codecs.")
            received.fulfill()
        }

        try fixture.write([
            fixture.entry(id: "new", text: "Launch codecs.", app: "DaddyApp", at: 3),
            fixture.entry(id: "other-app", text: "ignore me", app: "Terminal", at: 2),
            fixture.entry(id: "existing", text: "old command", app: "DaddyApp", at: 1),
        ])

        wait(for: [received], timeout: 2)
    }

    func testDifferentRecordingsWithIdenticalTextAreBothEmitted() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.write([])

        let watcher = try XCTUnwrap(HEXWatcher(historyURL: fixture.historyURL))
        defer { watcher.stop() }

        let received = expectation(description: "both recordings")
        received.expectedFulfillmentCount = 2
        received.assertForOverFulfill = true
        watcher.start { text in
            XCTAssertEqual(text, "Launch codecs.")
            received.fulfill()
        }

        try fixture.write([
            fixture.entry(id: "second", text: "Launch codecs.", app: "Daddy", at: 2),
            fixture.entry(id: "first", text: "Launch codecs.", app: "Daddy", at: 1),
        ])

        wait(for: [received], timeout: 2)
    }
}

private struct Fixture {
    let directory: URL
    let historyURL: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DaddyCore-HEXWatcher-\(UUID().uuidString)")
        historyURL = directory.appendingPathComponent("transcription_history.json")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    func entry(
        id: String,
        text: String,
        app: String,
        at timestamp: TimeInterval
    ) -> [String: Any] {
        [
            "id": id,
            "text": text,
            "sourceAppName": app,
            "timestamp": timestamp,
        ]
    }

    func write(_ entries: [[String: Any]]) throws {
        let data = try JSONSerialization.data(withJSONObject: ["history": entries])
        try data.write(to: historyURL, options: .atomic)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
