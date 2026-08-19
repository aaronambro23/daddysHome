import XCTest
@testable import DaddyCore
import Foundation

final class PTYIntegrationTests: XCTestCase {

    /// Polls `predicate` until it is true or the deadline passes.
    /// Replaces `Thread.sleep`, which is both slower and flakier.
    /// Modelled on terminal-control's `wait_for_text` / `wait_for_idle`.
    @discardableResult
    func waitFor(
        _ description: String,
        timeout: TimeInterval = 10,
        pollInterval: TimeInterval = 0.05,
        _ predicate: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return true }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        return predicate()
    }

    /// Opt-in: `DADDY_LIVE_AGENT_TESTS=1 swift test`.
    ///
    /// This launches the real Claude Code CLI, which is an interactive TUI that
    /// by design never exits. Even with process-group teardown, the XCTest
    /// runner can block at exit on the fds the agent inherited — the suite hung
    /// for nine minutes at 0% CPU before this gate. Driving a real agent needs a
    /// harness that owns the terminal and can wait on visible text (the
    /// deferred `termctrl` option), not a plain unit test.
    ///
    /// The pty layer itself is covered without it, by `testSessionOutputCapture`
    /// (real forkpty output) and `testTerminateKillsDescendants` (process-group
    /// shutdown).
    func testClaudeCodeLaunchAndDetectReady() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["DADDY_LIVE_AGENT_TESTS"] == "1",
            "Set DADDY_LIVE_AGENT_TESTS=1 to run live agent tests"
        )

        try XCTSkipIf(
            ExecutableResolver.resolve("claude") == nil,
            "claude is not on PATH — skipping live agent launch test"
        )

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

        // Terminate unconditionally: without this, a failed assertion leaves a
        // live agent (and its Node descendants) running after the test exits.
        defer { try? sessionManager.terminateSession(session.id) }

        try sessionManager.launchSession(session)

        // The agent needs a moment to boot; asserting immediately is a race.
        let becameReady = waitFor("claude reaches .ready") {
            sessionManager.session(session.id)?.state == .ready
        }

        let observed = sessionManager.session(session.id)?.state
        XCTAssertTrue(
            becameReady,
            "Expected .ready within timeout, last observed: \(String(describing: observed))"
        )

        let pty = try XCTUnwrap(sessionManager.getPTYProcess(for: session.id))
        XCTAssertTrue(pty.isProcessRunning, "Agent should still be running before teardown")
        XCTAssertGreaterThan(pty.pid, 0, "Expected a real pid from forkpty")
    }

    /// The process-group fix: killing a session must take its descendants with
    /// it. `sh` spawning a `sleep` mirrors an agent spawning tool processes.
    func testTerminateKillsDescendants() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let marker = "daddy-descendant-\(UUID().uuidString.prefix(8))"
        let pty = PTYProcess(
            executablePath: "/bin/sh",
            arguments: ["-c", "sleep 300 & echo \(marker)-started; wait"],
            cwd: tempDir
        )

        var output = ""
        let outputLock = NSLock()
        pty.registerChunkCallback { chunk in
            outputLock.lock()
            output += chunk
            outputLock.unlock()
        }

        try pty.launch()
        defer { pty.terminateNow() }

        let started = waitFor("child announces it started") {
            outputLock.lock()
            defer { outputLock.unlock() }
            return output.contains("\(marker)-started")
        }
        XCTAssertTrue(started, "Child never started; got: \(output)")

        let group = pty.pid
        XCTAssertGreaterThan(group, 0)

        pty.terminate(graceSeconds: 0.2)

        // The whole process group must be gone, not just the direct child.
        let groupGone = waitFor("process group is reaped", timeout: 5) {
            kill(-group, 0) != 0
        }
        XCTAssertTrue(
            groupGone,
            "Process group \(group) survived terminate() — descendants leaked"
        )
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

    func testExitImmediatelyAfterControlCIsMarkedAsInterruptedExit() throws {
        let pty = PTYProcess(
            executablePath: "/bin/cat",
            arguments: [],
            cwd: FileManager.default.temporaryDirectory
        )
        try pty.launch()
        defer { pty.terminateNow() }

        try pty.writeControl(0x03)

        XCTAssertTrue(
            waitFor("cat exits after Ctrl-C") { pty.exitCode != nil },
            "Ctrl-C did not terminate the test process"
        )
        XCTAssertTrue(pty.exitedAfterInterrupt)
    }

    func testPhysicalControlCMarkerDoesNotDependOnEncodedBytes() throws {
        let pty = PTYProcess(
            executablePath: "/bin/sh",
            arguments: ["-c", "read ignored"],
            cwd: FileManager.default.temporaryDirectory
        )
        try pty.launch()
        defer { pty.terminateNow() }

        // Enhanced-keyboard TUIs receive Kitty/CSI-u bytes rather than 0x03.
        // The terminal view records the physical key independently; newline
        // stands in for whatever encoded input then causes the child to exit.
        pty.noteInterruptInput()
        try pty.write("\n")

        XCTAssertTrue(
            waitFor("marked process exits") { pty.exitCode != nil },
            "The test process did not exit"
        )
        XCTAssertTrue(pty.exitedAfterInterrupt)
    }

    func testUnrelatedExitIsNotMarkedAsInterruptedExit() throws {
        let pty = PTYProcess(
            executablePath: "/usr/bin/true",
            arguments: [],
            cwd: FileManager.default.temporaryDirectory
        )
        try pty.launch()

        XCTAssertTrue(
            waitFor("true exits") { pty.exitCode != nil },
            "The test process did not exit"
        )
        XCTAssertFalse(pty.exitedAfterInterrupt)
    }

    /// The flag that lets a renderer ask a just-launched child to repaint once.
    /// It must be true for exactly one caller, or the shell pane would send a
    /// Ctrl-L over output the user wanted to keep.
    func testFreshLaunchRedrawIsClaimedOnce() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let ptyProcess = PTYProcess(
            executablePath: "/bin/echo",
            arguments: ["ready"],
            cwd: tempDir
        )

        XCTAssertFalse(
            ptyProcess.consumeFreshLaunchRedraw(),
            "Nothing has launched yet, so there is no prompt to redraw"
        )

        try ptyProcess.launch()

        XCTAssertTrue(ptyProcess.consumeFreshLaunchRedraw())
        XCTAssertFalse(ptyProcess.consumeFreshLaunchRedraw(), "The flag is one-shot")
    }

    /// A renderer that goes away must be able to take its registration with it.
    /// The pty outlives the view, so a callback nobody can cancel runs for every
    /// chunk for the rest of the process's life.
    func testChunkCallbacksCanBeRemoved() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let ptyProcess = PTYProcess(
            executablePath: "/bin/echo",
            arguments: ["ready"],
            cwd: tempDir
        )

        let lock = NSLock()
        var removedSaw = 0
        var keptSaw = 0

        let removed = ptyProcess.registerChunkCallback { _ in
            lock.lock(); removedSaw += 1; lock.unlock()
        }
        ptyProcess.registerChunkCallback { _ in
            lock.lock(); keptSaw += 1; lock.unlock()
        }

        ptyProcess.removeChunkCallback(removed)

        try ptyProcess.launch()

        XCTAssertTrue(
            waitFor("the surviving callback sees output") {
                lock.lock(); defer { lock.unlock() }
                return keptSaw > 0
            }
        )

        lock.lock()
        let strays = removedSaw
        lock.unlock()
        XCTAssertEqual(strays, 0, "A removed callback must never be called again")
    }

    /// Two shells in one project: distinct ptys, each reachable by its own id,
    /// and closing one leaves the other running.
    func testShellSessionsAreKeyedByShellID() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let shells = ShellSessions()
        defer { shells.shutdownAll() }

        let first = try shells.shell(id: "tab-1", cwd: tempDir)
        let second = try shells.shell(id: "tab-2", cwd: tempDir)

        XCTAssertFalse(first === second, "Each tab gets its own shell")
        XCTAssertTrue(shells.existing(id: "tab-1") === first)
        XCTAssertTrue(try shells.shell(id: "tab-1", cwd: tempDir) === first, "Asking twice reuses it")
        XCTAssertNil(shells.existing(id: "tab-3"), "Never started, never invented")

        shells.close(id: "tab-1")
        XCTAssertNil(shells.existing(id: "tab-1"))
        XCTAssertTrue(
            waitFor("first shell exits") { !first.isProcessRunning },
            "Closing a tab must kill its shell"
        )
        XCTAssertTrue(second.isProcessRunning, "Closing one tab must not touch the others")
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
