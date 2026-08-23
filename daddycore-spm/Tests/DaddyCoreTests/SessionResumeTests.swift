import XCTest
@testable import DaddyCore

/// Covers reopening a conversation: the arguments each CLI needs, the record
/// that survives a quit, and reading transcripts back off disk.
///
/// The bug this batch exists for was not that chats were lost — they were on
/// disk the whole time — but that Daddy never learned which conversation a card
/// owned, so the only thing it could ask for was "the newest one here". These
/// tests pin down the difference.
final class SessionResumeTests: XCTestCase {

    private let cwd = URL(fileURLWithPath: "/tmp")

    // MARK: - Launch arguments

    func testClaudeNamesTheConversationAtLaunch() {
        let adapter = ClaudeAdapter()
        let id = UUID().uuidString

        let args = adapter.launchArgs(
            cwd: cwd, model: nil, approvalPolicy: .safeAuto,
            resumption: .fresh(sessionID: id)
        )

        XCTAssertTrue(
            args.contains("--session-id") && args.contains(id),
            "without --session-id there is no way to know which file on disk this card owns: \(args)"
        )
    }

    func testClaudeRefusesToPassANonUUIDSessionID() {
        // Claude rejects a malformed id outright, which means the agent never
        // starts at all — a far worse outcome than an unnamed conversation.
        let args = ClaudeAdapter().launchArgs(
            cwd: cwd, model: nil, approvalPolicy: .safeAuto,
            resumption: .fresh(sessionID: "not-a-uuid")
        )

        XCTAssertFalse(args.contains("--session-id"), "\(args)")
    }

    func testClaudeReopensAnExactConversation() {
        let args = ClaudeAdapter().launchArgs(
            cwd: cwd, model: nil, approvalPolicy: .safeAuto,
            resumption: .conversation(id: "abc")
        )

        XCTAssertEqual(argument(after: "--resume", in: args), "abc")
        XCTAssertFalse(args.contains("--continue"), "--continue would reopen the newest one instead")
    }

    func testCodexPutsResumeBeforeItsFlags() {
        // `codex resume [OPTIONS] [SESSION_ID]`. This is the case the old
        // "append some arguments" design could not express at all, and why
        // Codex could not be resumed before now.
        let args = CodexAdapter().launchArgs(
            cwd: cwd, model: nil, approvalPolicy: .safeAuto,
            resumption: .conversation(id: "abc")
        )

        XCTAssertEqual(args.first, "resume", "the subcommand has to lead: \(args)")
        XCTAssertEqual(args.last, "abc", "the session id is positional and must follow the flags: \(args)")
        XCTAssertTrue(args.contains("--sandbox"), "resuming should not drop the approval policy: \(args)")
    }

    func testCodexAsksForTheNewestWhenItHasNoID() {
        let args = CodexAdapter().launchArgs(
            cwd: cwd, model: nil, approvalPolicy: .safeAuto,
            resumption: .mostRecent
        )

        XCTAssertEqual(args.first, "resume")
        XCTAssertEqual(args.last, "--last")
    }

    func testAFreshCodexLaunchHasNoResumeSubcommand() {
        let args = CodexAdapter().launchArgs(
            cwd: cwd, model: nil, approvalPolicy: .safeAuto,
            resumption: .fresh(sessionID: nil)
        )

        XCTAssertFalse(args.contains("resume"), "\(args)")
        XCTAssertFalse(args.contains("--last"), "\(args)")
    }

    func testCursorAndOpenCodeReopenByID() {
        let cursor = CursorAdapter().launchArgs(
            cwd: cwd, model: nil, approvalPolicy: .safeAuto,
            resumption: .conversation(id: "abc")
        )
        XCTAssertEqual(argument(after: "--resume", in: cursor), "abc")

        let opencode = OpenCodeAdapter().launchArgs(
            cwd: cwd, model: nil, approvalPolicy: .safeAuto,
            resumption: .conversation(id: "abc")
        )
        XCTAssertEqual(argument(after: "--session", in: opencode), "abc")
    }

    func testOnlyClaudeCanBeToldItsSessionIDUpFront() {
        // The honest state of things, and the reason the other three still fall
        // back to "the newest conversation here". If one of them gains the
        // ability, this test is where that change gets noticed.
        XCTAssertTrue(ClaudeAdapter().mintsSessionID)
        XCTAssertFalse(CodexAdapter().mintsSessionID)
        XCTAssertFalse(CursorAdapter().mintsSessionID)
        XCTAssertFalse(OpenCodeAdapter().mintsSessionID)
    }

    func testEveryAdapterCanReopenSomething() {
        for adapter in [ClaudeAdapter(), CodexAdapter(), CursorAdapter(), OpenCodeAdapter()] as [AgentAdapter] {
            XCTAssertTrue(adapter.canReopenConversations, "\(type(of: adapter))")
        }
    }

    // MARK: - Minting through SessionManager

    func testLaunchingClaudeCommitsASessionIDToTheSession() throws {
        // Not launched — `resumption(for:adapter:continuing:)` is what is being
        // checked, and running the real CLI in a test is not the point.
        let manager = SessionManager()
        let session = try manager.createSession(
            projectID: "/tmp", workUnitID: "unit", agent: .claude, cwd: cwd
        )

        XCTAssertNil(session.providerSessionID, "nothing should be claimed before launch")

        let minted = manager.resumptionForTesting(session: session, continuing: false)
        guard case .fresh(let id?) = minted else {
            return XCTFail("a fresh Claude launch should mint an id, got \(minted)")
        }
        XCTAssertNotNil(UUID(uuidString: id))
    }

    func testAFreshStartDoesNotReuseTheOldConversationID() {
        // "Fresh start" on a card that already has a conversation must not hand
        // Claude the same id: it means the opposite of fresh, and Claude
        // refuses an id already on disk, so the agent would not start.
        let manager = SessionManager()
        let session = Session(
            projectID: "/tmp", workUnitID: "unit", agent: .claude,
            cwd: cwd, providerSessionID: "11111111-1111-1111-1111-111111111111"
        )

        let minted = manager.resumptionForTesting(session: session, continuing: false)
        guard case .fresh(let id?) = minted else {
            return XCTFail("expected a minted id, got \(minted)")
        }
        XCTAssertNotEqual(id, session.providerSessionID)
    }

    func testContinuingWithoutAKnownIDFallsBackToTheNewest() {
        let manager = SessionManager()
        let session = Session(projectID: "/tmp", workUnitID: "unit", agent: .codex, cwd: cwd)

        XCTAssertEqual(
            manager.resumptionForTesting(session: session, continuing: true),
            .mostRecent
        )
    }

    func testContinuingWithAKnownIDReopensThatExactConversation() {
        let manager = SessionManager()
        let session = Session(
            projectID: "/tmp", workUnitID: "unit", agent: .claude,
            cwd: cwd, providerSessionID: "abc"
        )

        XCTAssertEqual(
            manager.resumptionForTesting(session: session, continuing: true),
            .conversation(id: "abc")
        )
    }

    // MARK: - Surviving a quit

    func testSessionRecordsRoundTrip() throws {
        let file = temporaryFile("sessions.json")
        let store = SessionStore(url: file)

        let record = SessionRecord(
            id: "card-1", projectID: "/tmp/proj", workUnitID: "unit",
            agent: .claude, model: "opus-5", cwd: "/tmp/proj",
            providerSessionID: "session-1",
            startedAt: Date(timeIntervalSince1970: 1000),
            lastOutputAt: Date(timeIntervalSince1970: 2000)
        )
        store.save([record])

        let loaded = SessionStore(url: file).load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.providerSessionID, "session-1")
        XCTAssertEqual(loaded.first?.id, "card-1")
    }

    func testMissingStoreReadsAsNoHistoryRatherThanFailing() {
        let store = SessionStore(url: temporaryFile("does-not-exist.json"))
        XCTAssertEqual(store.load().count, 0)
    }

    func testCorruptStoreReadsAsNoHistory() throws {
        // First run after a crash mid-write should start the app, not stop it.
        let file = temporaryFile("corrupt.json")
        try "{ not json".write(to: file, atomically: true, encoding: .utf8)

        XCTAssertEqual(SessionStore(url: file).load().count, 0)
    }

    func testRestoredSessionsComeBackDeadButResumable() {
        let manager = SessionManager()
        let session = manager.restoreSession(
            id: "card-1", projectID: "/tmp", workUnitID: "unit",
            agent: .claude, cwd: cwd, providerSessionID: "session-1"
        )

        XCTAssertEqual(session.state, .exited(exitCode: 0), "the pty died with the app that owned it")
        XCTAssertEqual(session.providerSessionID, "session-1")
        XCTAssertEqual(manager.session("card-1")?.id, "card-1")
    }

    // MARK: - Reading transcripts

    func testTranscriptYieldsItsOpeningRequest() throws {
        let file = temporaryFile("\(UUID().uuidString).jsonl")
        try transcript(lines: [
            #"{"type":"mode","mode":"normal"}"#,
            #"{"type":"user","cwd":"/tmp/proj","message":{"role":"user","content":"align the middle column"}}"#,
        ]).write(to: file, atomically: true, encoding: .utf8)

        let chat = try XCTUnwrap(ChatHistory.describe(file, agent: .claude))
        XCTAssertEqual(chat.title, "align the middle column")
        XCTAssertEqual(chat.cwd, "/tmp/proj")
        XCTAssertEqual(chat.id, file.deletingPathExtension().lastPathComponent)
    }

    func testSlashCommandsAndMetaTurnsDoNotBecomeTitles() throws {
        // A transcript's first few user-typed lines are usually not requests.
        // Titling a chat "<command-name>/resume" would make the picker useless.
        let file = temporaryFile("\(UUID().uuidString).jsonl")
        try transcript(lines: [
            #"{"type":"user","cwd":"/tmp/proj","isMeta":true,"message":{"role":"user","content":"Caveat: the messages below"}}"#,
            #"{"type":"user","cwd":"/tmp/proj","message":{"role":"user","content":"<command-name>/resume</command-name>"}}"#,
            #"{"type":"user","cwd":"/tmp/proj","isSidechain":true,"message":{"role":"user","content":"subagent chatter"}}"#,
            #"{"type":"user","cwd":"/tmp/proj","message":{"role":"user","content":"the actual request"}}"#,
        ]).write(to: file, atomically: true, encoding: .utf8)

        XCTAssertEqual(ChatHistory.describe(file, agent: .claude)?.title, "the actual request")
    }

    func testATurnCarryingOnlyToolResultsIsNotARequest() throws {
        let file = temporaryFile("\(UUID().uuidString).jsonl")
        try transcript(lines: [
            #"{"type":"user","cwd":"/tmp/proj","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}"#,
            #"{"type":"user","cwd":"/tmp/proj","message":{"role":"user","content":[{"type":"text","text":"spoken aloud"}]}}"#,
        ]).write(to: file, atomically: true, encoding: .utf8)

        XCTAssertEqual(ChatHistory.describe(file, agent: .claude)?.title, "spoken aloud")
    }

    func testAConversationThatNeverHappenedIsNotOffered() throws {
        // Opening a session and closing it without asking anything leaves a
        // file behind. There is nothing there to reopen.
        let file = temporaryFile("\(UUID().uuidString).jsonl")
        try transcript(lines: [
            #"{"type":"mode","mode":"normal"}"#,
            #"{"type":"permission-mode","permissionMode":"acceptEdits"}"#,
        ]).write(to: file, atomically: true, encoding: .utf8)

        XCTAssertNil(ChatHistory.describe(file, agent: .claude))
    }

    func testLongTitlesAreCutToOneLine() throws {
        let file = temporaryFile("\(UUID().uuidString).jsonl")
        let sprawling = String(repeating: "word ", count: 200)
        try transcript(lines: [
            #"{"type":"user","cwd":"/tmp/proj","message":{"role":"user","content":"\#(sprawling)"}}"#,
        ]).write(to: file, atomically: true, encoding: .utf8)

        let title = try XCTUnwrap(ChatHistory.describe(file, agent: .claude)?.title)
        XCTAssertLessThanOrEqual(title.count, 70)
        XCTAssertFalse(title.contains("\n"))
    }

    // MARK: - Helpers

    private func transcript(lines: [String]) -> String {
        lines.joined(separator: "\n") + "\n"
    }

    private func temporaryFile(_ name: String) -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("daddy-resume-tests/\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(name)
    }

    private func argument(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else {
            return nil
        }
        return args[index + 1]
    }
}
