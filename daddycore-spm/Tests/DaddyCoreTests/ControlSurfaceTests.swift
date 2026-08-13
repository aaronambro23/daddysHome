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

    func testControlOnAnUnknownSessionThrows() {
        let manager = SessionManager()

        XCTAssertThrowsError(try manager.interruptSession("nope"))
        XCTAssertThrowsError(try manager.resumeSession("nope"))
        XCTAssertThrowsError(try manager.terminateSession("nope"))
        XCTAssertThrowsError(try manager.restartSession("nope"))
    }
}
