import XCTest
@testable import DaddyCore

/// Covers the control surface this branch exists for: send, interrupt, resume,
/// restart, terminate. None of it had a test before — `SessionManager` was only
/// exercised through the live-agent test, which is skipped by default.
///
/// Everything here drives a real pty running `/bin/cat`, which echoes what it is
/// sent and stays alive until closed. That makes input verifiable without
/// needing an agent CLI installed.
final class ControlSurfaceTests: XCTestCase {

    private func waitFor(
        timeout: TimeInterval = 2.0,
        _ condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            usleep(20_000)
        }
        return condition()
    }

    // MARK: - Typed input

    func testPromptReachesTheProcess() throws {
        let pty = PTYProcess(executablePath: "/bin/cat", arguments: [], cwd: URL(fileURLWithPath: "/tmp"))
        try pty.launch()
        defer { pty.shutdown() }

        try ClaudeAdapter().sendPrompt("hello", to: pty)

        XCTAssertTrue(
            waitFor { pty.recentOutput.contains("hello") },
            "prompt never reached the pty; saw \(pty.recentOutput.debugDescription)"
        )
    }

    func testSubmitKeyIsCarriageReturnNotLineFeed() {
        // Asserted on the encoding rather than end-to-end, because the tty's
        // line discipline rewrites CR to LF on the way in (ICRNL) — an echo test
        // would be measuring the terminal, not the adapter. The adapters route
        // through `.key(.enter)`; this pins what that means.
        XCTAssertEqual(TerminalInput.key(.enter).bytes, [0x0d])
        XCTAssertNotEqual(TerminalInput.key(.enter).bytes, [0x0a])
    }

    func testInterruptSendsTheKeyEachCLIActuallyWants() {
        // Claude and Cursor listen for ESC; Codex and OpenCode want Ctrl-C.
        XCTAssertEqual(ClaudeAdapter().interruptInput.bytes, [0x1b])
        XCTAssertEqual(CursorAdapter().interruptInput.bytes, [0x1b])
        XCTAssertEqual(CodexAdapter().interruptInput.bytes, [0x03])
        XCTAssertEqual(OpenCodeAdapter().interruptInput.bytes, [0x03])
    }

    func testResumeSendsAContinuation() throws {
        let pty = PTYProcess(executablePath: "/bin/cat", arguments: [], cwd: URL(fileURLWithPath: "/tmp"))
        try pty.launch()
        defer { pty.shutdown() }

        try ClaudeAdapter().resume(pty)

        XCTAssertTrue(waitFor { pty.recentOutput.contains("continue") })
    }

    // MARK: - Approval policy

    func testApprovalPolicyChangesClaudeLaunchArgs() {
        let adapter = ClaudeAdapter()
        let cwd = URL(fileURLWithPath: "/tmp")

        let safe = adapter.launchArgs(cwd: cwd, model: nil, approvalPolicy: .safeAuto)
        let bypass = adapter.launchArgs(cwd: cwd, model: nil, approvalPolicy: .fullBypass)

        XCTAssertNotEqual(safe, bypass, "the setting used to be accepted and ignored")
        XCTAssertTrue(safe.contains("acceptEdits"))
        XCTAssertTrue(bypass.contains("--dangerously-skip-permissions"))
    }

    func testApprovalPolicyReachesEveryAdapter() {
        // All four used to accept the setting and ignore it. Flag names for
        // Cursor and OpenCode come from their real `--help` output.
        let cwd = URL(fileURLWithPath: "/tmp")
        let adapters: [AgentAdapter] = [
            ClaudeAdapter(), CodexAdapter(), CursorAdapter(), OpenCodeAdapter(),
        ]

        for adapter in adapters {
            let safe = adapter.launchArgs(cwd: cwd, model: nil, approvalPolicy: .safeAuto)
            let bypass = adapter.launchArgs(cwd: cwd, model: nil, approvalPolicy: .fullBypass)

            XCTAssertNotEqual(
                safe, bypass,
                "\(type(of: adapter)) still ignores the approval setting"
            )
        }
    }

    func testCursorAndOpenCodeUseTheirRealFlags() {
        let cwd = URL(fileURLWithPath: "/tmp")

        let cursor = CursorAdapter()
        XCTAssertTrue(
            cursor.launchArgs(cwd: cwd, model: nil, approvalPolicy: .safeAuto)
                .contains("--auto-review")
        )
        XCTAssertTrue(
            cursor.launchArgs(cwd: cwd, model: nil, approvalPolicy: .fullBypass)
                .contains("--force")
        )

        let opencode = OpenCodeAdapter()
        XCTAssertFalse(
            opencode.launchArgs(cwd: cwd, model: nil, approvalPolicy: .safeAuto)
                .contains("--auto"),
            "prompting is opencode's default; safe mode should add nothing"
        )
        XCTAssertTrue(
            opencode.launchArgs(cwd: cwd, model: nil, approvalPolicy: .fullBypass)
                .contains("--auto")
        )
    }

    func testApprovalPolicyChangesCodexSandbox() {
        let adapter = CodexAdapter()
        let cwd = URL(fileURLWithPath: "/tmp")

        let safe = adapter.launchArgs(cwd: cwd, model: nil, approvalPolicy: .safeAuto)
        let bypass = adapter.launchArgs(cwd: cwd, model: nil, approvalPolicy: .fullBypass)

        XCTAssertTrue(safe.contains("workspace-write"))
        XCTAssertTrue(bypass.contains("danger-full-access"))
    }

    // MARK: - Session lifecycle

    private func makeCatSession(_ manager: SessionManager) throws -> Session {
        try manager.createSession(
            projectID: "p", workUnitID: "w", agent: .claude,
            cwd: URL(fileURLWithPath: "/tmp")
        )
    }

    func testTearingDownAPTYKillsTheWholeProcessGroup() throws {
        let manager = SessionManager()
        let session = try makeCatSession(manager)

        // Launch a long-lived stand-in directly so no agent CLI is required.
        let first = PTYProcess(
            executablePath: "/bin/sh",
            arguments: ["-c", "sleep 300"],
            cwd: URL(fileURLWithPath: "/tmp")
        )
        try first.launch()
        manager.attach(first, to: session.id)

        let oldPID = first.pid
        XCTAssertTrue(first.isProcessRunning)

        manager.teardownPTY(for: session.id)

        XCTAssertTrue(
            waitFor { kill(-oldPID, 0) != 0 },
            "the old process group survived — this is the leak restart used to have"
        )
        XCTAssertNil(manager.getPTYProcess(for: session.id))
    }

    func testTerminateReportsTheRealExitCode() throws {
        let manager = SessionManager()
        let session = try makeCatSession(manager)

        let pty = PTYProcess(
            executablePath: "/bin/sh",
            arguments: ["-c", "exit 3"],
            cwd: URL(fileURLWithPath: "/tmp")
        )
        try pty.launch()
        manager.attach(pty, to: session.id)

        XCTAssertTrue(waitFor { pty.exitCode != nil }, "process never reported an exit")
        try manager.terminateSession(session.id)

        XCTAssertEqual(
            manager.session(session.id)?.state, .exited(exitCode: 3),
            "exit code used to be hardcoded to 0"
        )
    }

    func testWaitStatusIsDecodedIntoAnExitCode() {
        // SwiftTerm reports the raw waitpid status: `exit 3` arrives as 768.
        XCTAssertEqual(PTYProcess.decodeWaitStatus(768), 3)
        XCTAssertEqual(PTYProcess.decodeWaitStatus(0), 0)
        // Killed by SIGKILL (9) — reported the way a shell would, as 128 + 9.
        XCTAssertEqual(PTYProcess.decodeWaitStatus(9), 137)
    }

    func testActiveSessionsExcludesDeadOnes() throws {
        let manager = SessionManager()
        let live = try makeCatSession(manager)
        let dead = try makeCatSession(manager)

        let livePTY = PTYProcess(
            executablePath: "/bin/sh", arguments: ["-c", "sleep 300"],
            cwd: URL(fileURLWithPath: "/tmp")
        )
        try livePTY.launch()
        manager.attach(livePTY, to: live.id)
        defer { livePTY.shutdown() }

        let deadPTY = PTYProcess(
            executablePath: "/bin/sh", arguments: ["-c", "exit 0"],
            cwd: URL(fileURLWithPath: "/tmp")
        )
        try deadPTY.launch()
        manager.attach(deadPTY, to: dead.id)
        XCTAssertTrue(waitFor { !deadPTY.isProcessRunning })

        let active = manager.getActiveSessions().map(\.id)

        XCTAssertEqual(manager.allSessions().count, 2)
        XCTAssertEqual(active, [live.id], "getActiveSessions used to return everything")
    }

    // MARK: - Child environment

    func testChildEnvironmentDeclaresATerminal() {
        let env = PTYProcess.childEnvironment()

        // Without TERM a TUI cannot read terminfo, decides the terminal can do
        // nothing, and stops redrawing in place — every keystroke reprints the
        // input line on a new row.
        XCTAssertTrue(env.contains("TERM=xterm-256color"), "no TERM: \(env)")
        XCTAssertTrue(env.contains("COLORTERM=truecolor"))
    }

    func testChildEnvironmentCarriesAUsablePath() {
        let env = PTYProcess.childEnvironment()

        guard let path = env.first(where: { $0.hasPrefix("PATH=") }) else {
            return XCTFail("no PATH — agents cannot find node, git, or anything else")
        }
        XCTAssertTrue(path.contains("/usr/bin"), path)
    }

    func testTheChildActuallySeesTERM() throws {
        // End-to-end: what the process really gets, not what we meant to send.
        let pty = PTYProcess(
            executablePath: "/bin/sh",
            arguments: ["-c", "printf 'TERM<%s>' \"$TERM\""],
            cwd: URL(fileURLWithPath: "/tmp")
        )
        try pty.launch()
        defer { pty.shutdown() }

        XCTAssertTrue(
            waitFor { pty.recentOutput.contains("TERM<xterm-256color>") },
            "child saw: \(pty.recentOutput.debugDescription)"
        )
    }

    // MARK: - Launch

    /// An adapter that runs `/bin/cat`, so the real launch path can be
    /// exercised without an agent CLI installed.
    private final class StubAdapter: AgentAdapter {
        static let kind = AgentKind.claude
        static let executablePath = "/bin/cat"
        let interruptInput = TerminalInput.interrupt
        // Nil: /bin/cat has no conversation to continue. Required since the
        // protocol grew resume support, which this stub predates.
        let continueConversationArgs: [String]? = nil

        func launchArgs(cwd: URL, model: ModelRef?, approvalPolicy: ApprovalPolicy) -> [String] { [] }
        func modelFlagValue(for humanName: String) -> String? { humanName }
        func detectState(fromRecentOutput buffer: String) -> AgentState { .ready }
    }

    func testLaunchingASessionDoesNotDeadlock() throws {
        // `launchSession` held the lock and then called a helper that took it
        // again. NSLock is not recursive, so launching an agent hung the calling
        // thread — the main thread in the app — and beachballed the window.
        let manager = SessionManager()
        manager.register(StubAdapter(), for: .claude)

        let session = try makeCatSession(manager)
        let returned = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            try? manager.launchSession(session)
            returned.signal()
        }

        XCTAssertEqual(
            returned.wait(timeout: .now() + 5), .success,
            "launchSession never returned — the lock is re-entered somewhere"
        )
        XCTAssertNotNil(manager.getPTYProcess(for: session.id))

        try? manager.terminateSession(session.id)
    }

    func testOutputAfterLaunchStillUpdatesState() throws {
        // The state callback is registered after the lock is released; make sure
        // moving it did not stop it being registered at all.
        let manager = SessionManager()
        manager.register(StubAdapter(), for: .claude)

        let session = try makeCatSession(manager)
        try manager.launchSession(session)
        defer { try? manager.terminateSession(session.id) }

        try manager.sendPrompt("hello", to: session.id)

        XCTAssertTrue(
            waitFor { manager.getPTYProcess(for: session.id)?.recentOutput.contains("hello") == true },
            "no output came back through the session"
        )
    }

    func testControlOnAnUnknownSessionThrows() {
        let manager = SessionManager()

        XCTAssertThrowsError(try manager.interruptSession("nope"))
        XCTAssertThrowsError(try manager.resumeSession("nope"))
        XCTAssertThrowsError(try manager.terminateSession("nope"))
        XCTAssertThrowsError(try manager.restartSession("nope"))
    }
}
