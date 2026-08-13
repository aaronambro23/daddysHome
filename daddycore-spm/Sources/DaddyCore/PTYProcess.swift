import Foundation
import SwiftTerm

/// A child process running inside a real pseudo-terminal.
///
/// This used to be `Process` + `Pipe`, which is not a TTY. Interactive CLIs
/// call `isatty()` and, on a pipe, disable colour, spinners and — critically —
/// interactive approval prompts, switching to non-interactive mode. Claude
/// Code, Codex and Cursor all behave differently under a pipe, so agent
/// supervision could never have worked properly.
///
/// It is now backed by SwiftTerm's `LocalProcess`, which uses `forkpty`, so the
/// child sees a genuine terminal.
/// All mutable state is guarded by `lock`, so this is safe to hand across
/// queues — the delayed SIGKILL and the read callbacks run off-main.
public final class PTYProcess: LocalProcessDelegate, @unchecked Sendable {
    public enum PTYError: LocalizedError {
        case processFailed(String)
        case alreadyTerminated
        case writeFailed(String)

        public var errorDescription: String? {
            switch self {
            case .processFailed(let msg):
                return "Process failed: \(msg)"
            case .alreadyTerminated:
                return "Process already terminated"
            case .writeFailed(let msg):
                return "Write failed: \(msg)"
            }
        }
    }

    // MARK: Configuration

    private let executablePath: String
    private let arguments: [String]
    private let cwd: URL

    /// Geometry reported to the child via TIOCGWINSZ. Agents wrap their output
    /// to this width, so it is worth setting it to something realistic.
    private var columns: UInt16
    private var rows: UInt16

    // MARK: State

    private var localProcess: LocalProcess!
    private let lock = NSLock()
    private var outputBuffer: String = ""
    private var pendingBytes: [UInt8] = []
    private var outputCallbacks: [(String) -> Void] = []
    private var chunkCallbacks: [(String) -> Void] = []
    private var terminationCallbacks: [(Int32) -> Void] = []
    private var lastExitCode: Int32 = 0
    private var hasExited = false
    private let exitSignal = DispatchSemaphore(value: 0)

    /// Lines of scrollback retained in `recentOutput` for state detection.
    private let retainedLines = 200

    /// Off-main queue for the delayed SIGKILL in `terminate(graceSeconds:)`.
    private let terminationQueue = DispatchQueue(label: "com.daddy.pty.termination")

    public init(
        executablePath: String,
        arguments: [String],
        cwd: URL,
        columns: UInt16 = 120,
        rows: UInt16 = 30
    ) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.cwd = cwd
        self.columns = columns
        self.rows = rows

        // Deliver on a private serial queue rather than main: this type is used
        // headlessly by the CLI, and state detection should never contend with
        // the UI.
        self.localProcess = LocalProcess(
            delegate: self,
            dispatchQueue: DispatchQueue(label: "com.daddy.pty.\(UUID().uuidString)")
        )
    }

    // MARK: Lifecycle

    public func launch() throws {
        guard !localProcess.running else { return }

        // Adapters declare bare names ("claude"), and a GUI app's inherited
        // PATH will not find them. Resolve against the login shell's PATH.
        guard let resolved = ExecutableResolver.resolve(executablePath) else {
            throw PTYError.processFailed("Executable not found on PATH: \(executablePath)")
        }

        localProcess.startProcess(
            executable: resolved,
            args: arguments,
            environment: nil,
            execName: nil,
            currentDirectory: cwd.path
        )

        guard localProcess.running else {
            throw PTYError.processFailed("forkpty failed for \(executablePath)")
        }
    }

    public func write(_ data: String) throws {
        guard localProcess.running else { throw PTYError.alreadyTerminated }
        guard let encoded = data.data(using: .utf8) else {
            throw PTYError.writeFailed("Could not encode string as UTF-8")
        }
        localProcess.send(data: ArraySlice([UInt8](encoded)))
    }

    /// Send typed input — a control byte, a named key, or literal text.
    /// Prefer this over `write` for anything that is not plain text.
    public func send(_ input: TerminalInput) throws {
        guard localProcess.running else { throw PTYError.alreadyTerminated }
        localProcess.send(data: ArraySlice(input.bytes))
    }

    /// Send a raw control byte, e.g. 0x03 for Ctrl-C.
    public func writeControl(_ byte: UInt8) throws {
        try send(.control(byte))
    }

    /// Shut the child down, along with everything it spawned.
    ///
    /// SwiftTerm's `LocalProcess.terminate()` only does `kill(shellPid, SIGTERM)`,
    /// which reaches the immediate child and nothing else. Agents are Node
    /// processes that spawn descendants (tool calls, MCP servers, ripgrep), so
    /// that reliably orphans them — observed directly: a `claude` survived its
    /// parent and had to be killed by hand.
    ///
    /// `forkpty` makes the child a session leader, so its pid doubles as its
    /// process-group id and a negative pid signals the whole group. Sequence
    /// borrowed from terminal-control (`src/session.rs:731-758`): SIGHUP, a
    /// grace period, then SIGKILL to anything still alive.
    ///
    /// - Parameter graceSeconds: how long to wait after SIGHUP before SIGKILL.
    public func terminate(graceSeconds: Double = 2.0) {
        let group = localProcess.shellPid
        guard group > 0 else {
            localProcess.terminate()
            return
        }

        // SIGHUP reads as "your terminal went away", which interactive programs
        // handle more gracefully. SIGTERM too, because Node does not reliably
        // act on SIGHUP alone.
        kill(-group, SIGHUP)
        kill(-group, SIGTERM)

        terminationQueue.asyncAfter(deadline: .now() + graceSeconds) { [weak self] in
            guard let self else { return }

            // errno == ESRCH means the group is already gone; nothing to do.
            if kill(-group, 0) == 0 {
                kill(-group, SIGKILL)
            }

            // Let SwiftTerm tear down its DispatchIO and file descriptors.
            self.localProcess.terminate()
        }
    }

    /// Kill the process group immediately, skipping the grace period. Used on
    /// app teardown, where waiting is not an option.
    public func terminateNow() {
        let group = localProcess.shellPid
        if group > 0 { kill(-group, SIGKILL) }
        localProcess.terminate()
    }

    /// Shut down synchronously and confirm the group is actually gone.
    ///
    /// `terminate(graceSeconds:)` escalates on a background queue, which is
    /// right for the UI but useless at teardown: the caller can return, or the
    /// whole process can exit, before the SIGKILL ever fires — leaving the
    /// agent alive and still holding the inherited stdout, which is exactly how
    /// `swift test` came to hang for nine minutes at 0% CPU.
    ///
    /// Use this wherever the process must be gone before moving on.
    ///
    /// - Returns: true if the group is confirmed dead.
    @discardableResult
    public func shutdown(graceSeconds: Double = 2.0) -> Bool {
        let group = localProcess.shellPid
        guard group > 0 else {
            localProcess.terminate()
            return true
        }

        // SIGHUP reads as "the terminal went away". SIGTERM as well, because
        // Node — which every one of these agents is — does not reliably act on
        // SIGHUP alone.
        kill(-group, SIGHUP)
        kill(-group, SIGTERM)

        if waitForGroupExit(group, timeout: graceSeconds) {
            localProcess.terminate()
            return true
        }

        kill(-group, SIGKILL)
        let reaped = waitForGroupExit(group, timeout: 1.0)
        localProcess.terminate()
        return reaped
    }

    /// Polls until `kill(-group, 0)` fails, meaning nothing in the group is
    /// left to signal.
    private func waitForGroupExit(_ group: pid_t, timeout: Double) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if kill(-group, 0) != 0 { return true }
            usleep(20_000)   // 20ms
        }
        return kill(-group, 0) != 0
    }

    /// Turns a raw `waitpid` status into the exit code a shell would report.
    ///
    /// SwiftTerm hands the delegate the status word, not the code: a child that
    /// runs `exit 3` arrives here as 768, which is `3 << 8`. Every consumer of
    /// this class was reporting that number verbatim.
    ///
    /// A process killed by a signal has no exit code, so it is reported as
    /// `128 + signal` — the same convention shells use, which matters here
    /// because `shutdown()` ends agents with SIGKILL.
    static func decodeWaitStatus(_ status: Int32) -> Int32 {
        let lowBits = status & 0x7f
        if lowBits == 0 || lowBits == 0x7f {
            return (status >> 8) & 0xff
        }
        return 128 + lowBits
    }

    /// The child's exit code, or nil while it is still running.
    ///
    /// Unlike `waitUntilExit()` this never blocks, so it is safe to ask right
    /// after `shutdown()` — where waiting could deadlock if the termination
    /// delegate has not fired yet.
    public var exitCode: Int32? {
        lock.lock()
        defer { lock.unlock() }
        return hasExited ? lastExitCode : nil
    }

    /// Blocks until the child exits. Returns its exit code.
    @discardableResult
    public func waitUntilExit() -> Int32 {
        lock.lock()
        let alreadyExited = hasExited
        let code = lastExitCode
        lock.unlock()

        if alreadyExited { return code }

        exitSignal.wait()

        lock.lock()
        defer { lock.unlock() }
        return lastExitCode
    }

    /// Update the window size reported to the child. Call this when the
    /// rendering surface resizes so the agent re-wraps its output.
    public func resize(columns: UInt16, rows: UInt16) {
        lock.lock()
        self.columns = columns
        self.rows = rows
        lock.unlock()

        guard localProcess.running else { return }
        var size = winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(localProcess.childfd, TIOCSWINSZ, &size)
    }

    // MARK: Observation

    /// Fires with the full retained buffer on every chunk. Kept for
    /// `SessionManager`'s state detection, which pattern-matches recent output.
    public func registerOutputCallback(_ callback: @escaping (String) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        outputCallbacks.append(callback)
    }

    /// Fires with only the newly-arrived text. Use this to feed a terminal
    /// renderer or append to a log — it does not re-send history.
    public func registerChunkCallback(_ callback: @escaping (String) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        chunkCallbacks.append(callback)
    }

    public func registerTerminationCallback(_ callback: @escaping (Int32) -> Void) {
        lock.lock()
        let alreadyExited = hasExited
        let code = lastExitCode
        if !alreadyExited { terminationCallbacks.append(callback) }
        lock.unlock()

        if alreadyExited { callback(code) }
    }

    public var isProcessRunning: Bool {
        localProcess.running
    }

    /// PID of the child, or 0 before launch.
    public var pid: pid_t {
        localProcess.shellPid
    }

    public var recentOutput: String {
        lock.lock()
        defer { lock.unlock() }
        return outputBuffer
    }

    // MARK: - LocalProcessDelegate

    public func dataReceived(slice: ArraySlice<UInt8>) {
        lock.lock()

        // A read can split a multi-byte UTF-8 sequence, so decode only the
        // valid prefix and carry the remainder into the next chunk.
        pendingBytes.append(contentsOf: slice)
        let text = Self.consumeValidUTF8(&pendingBytes)

        guard !text.isEmpty else {
            lock.unlock()
            return
        }

        outputBuffer.append(text)
        trimBufferLocked()

        let snapshot = outputBuffer
        let outputs = outputCallbacks
        let chunks = chunkCallbacks
        lock.unlock()

        for callback in chunks { callback(text) }
        for callback in outputs { callback(snapshot) }
    }

    public func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        // Flush whatever is left in the decoder before reporting the exit.
        // A child's last write often ends mid-code-point, and those trailing
        // bytes would otherwise be dropped — losing the final line of output,
        // which is frequently the one that says why the agent stopped.
        flushPendingBytes()

        lock.lock()
        guard !hasExited else {
            lock.unlock()
            return
        }
        hasExited = true
        lastExitCode = Self.decodeWaitStatus(exitCode ?? 0)
        let code = lastExitCode
        let callbacks = terminationCallbacks
        terminationCallbacks.removeAll()
        lock.unlock()

        exitSignal.signal()
        for callback in callbacks { callback(code) }
    }

    public func getWindowSize() -> winsize {
        lock.lock()
        defer { lock.unlock() }
        return winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
    }

    // MARK: - Helpers

    /// Decodes any bytes still held by the incremental UTF-8 decoder and
    /// delivers them. Called on termination so trailing output is not lost.
    private func flushPendingBytes() {
        lock.lock()
        guard !pendingBytes.isEmpty else {
            lock.unlock()
            return
        }

        // Lossy on purpose: the stream has ended, so an incomplete code point
        // is never going to be completed.
        let text = String(decoding: pendingBytes, as: UTF8.self)
        pendingBytes.removeAll()

        outputBuffer.append(text)
        trimBufferLocked()

        let snapshot = outputBuffer
        let outputs = outputCallbacks
        let chunks = chunkCallbacks
        lock.unlock()

        for callback in chunks { callback(text) }
        for callback in outputs { callback(snapshot) }
    }

    /// Caller must hold `lock`.
    private func trimBufferLocked() {
        // Cheap guard so we are not splitting a huge string on every chunk.
        guard outputBuffer.utf8.count > 64 * 1024 else { return }

        let lines = outputBuffer.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > retainedLines else { return }
        outputBuffer = lines.suffix(retainedLines).joined(separator: "\n")
    }

    /// Decodes and removes the longest valid UTF-8 prefix of `bytes`.
    /// Leaves at most 3 trailing bytes behind (an incomplete code point).
    static func consumeValidUTF8(_ bytes: inout [UInt8]) -> String {
        guard !bytes.isEmpty else { return "" }

        var end = bytes.count
        // A UTF-8 code point is at most 4 bytes, so we never need to back off
        // further than 3 to find a boundary.
        let floor = max(0, bytes.count - 3)

        while end > floor {
            if let decoded = String(bytes: bytes[0..<end], encoding: .utf8) {
                bytes.removeFirst(end)
                return decoded
            }
            end -= 1
        }

        // Nothing decoded within a code point's reach: the stream contains
        // genuinely invalid bytes. Flush lossily rather than stall forever.
        if bytes.count > 3 {
            let decoded = String(decoding: bytes[0..<floor], as: UTF8.self)
            bytes.removeFirst(floor)
            return decoded
        }

        return ""
    }
}
