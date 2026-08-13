import Foundation

/// Resolves bare executable names (`claude`, `codex`) to absolute paths.
///
/// The adapters declare bare names, but a GUI app launched from Finder or
/// `open` inherits a minimal PATH — typically `/usr/bin:/bin:/usr/sbin:/sbin` —
/// which does not include `~/.local/bin`, `/opt/homebrew/bin`, or wherever the
/// agent CLIs actually live. Resolving against the *login shell's* PATH is what
/// makes launching work identically from Terminal and from the Dock.
public final class ExecutableResolver: @unchecked Sendable {
    public static let shared = ExecutableResolver()

    private let lock = NSLock()
    private var cachedSearchPaths: [String]?

    private init() {}

    /// Absolute path to `name`, or nil if it cannot be found or is not
    /// executable. Absolute and relative paths are returned untouched.
    public static func resolve(_ name: String) -> String? {
        shared.resolve(name)
    }

    /// Clears the cached PATH. Useful if the user installs a CLI while the app
    /// is running.
    public static func invalidateCache() {
        shared.invalidateCache()
    }

    public func resolve(_ name: String) -> String? {
        guard !name.contains("/") else {
            return FileManager.default.isExecutableFile(atPath: name) ? name : nil
        }

        for directory in searchPaths() {
            let candidate = (directory as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    public func invalidateCache() {
        lock.lock()
        cachedSearchPaths = nil
        lock.unlock()
    }

    // MARK: - Search paths

    private func searchPaths() -> [String] {
        lock.lock()
        if let cached = cachedSearchPaths {
            lock.unlock()
            return cached
        }
        lock.unlock()

        var paths: [String] = []

        // Whatever PATH we already have.
        if let env = ProcessInfo.processInfo.environment["PATH"] {
            paths.append(contentsOf: env.split(separator: ":").map(String.init))
        }

        // The login shell's PATH — this is the one that actually reflects the
        // user's setup (nvm, mise, homebrew, per-tool installers).
        paths.append(contentsOf: loginShellPaths())

        // Last-resort defaults for common install locations, in case the login
        // shell could not be queried.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        paths.append(contentsOf: [
            "\(home)/.local/bin",
            "\(home)/.opencode/bin",
            "\(home)/.bun/bin",
            "\(home)/.cargo/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ])

        // De-duplicate, preserving order.
        var seen = Set<String>()
        let deduped = paths.filter { seen.insert($0).inserted && !$0.isEmpty }

        lock.lock()
        cachedSearchPaths = deduped
        lock.unlock()
        return deduped
    }

    /// Asks the user's login shell what its PATH is. Runs once, then cached.
    ///
    /// Two things here are load-bearing:
    ///
    /// - **stdin must be `/dev/null`.** A login shell that inherits a terminal
    ///   can block waiting on it, and this call happens on whatever thread
    ///   first resolves a binary — in the app, that would freeze the UI. It hung
    ///   the test suite before this was set.
    /// - **There is a deadline.** A user's profile can do arbitrary things
    ///   (version managers, network calls, prompts). Missing PATH entries are a
    ///   recoverable annoyance; a permanent hang is not.
    private func loginShellPaths(timeout: TimeInterval = 3.0) -> [String] {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard FileManager.default.isExecutableFile(atPath: shell) else { return [] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        // -l so profile files are sourced; -c to run a single command.
        process.arguments = ["-lc", "printf %s \"$PATH\""]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        // Reaped through a termination handler rather than `waitUntilExit()`.
        //
        // `waitUntilExit()` pumps the run loop. On the main thread that lets
        // AppKit deliver a CoreAnimation commit *while SwiftUI is already inside
        // a view update*, and AttributeGraph aborts the process. It crashed the
        // app every time the launch menu was opened, because the menu asked
        // which agents were installed from inside its own body. A semaphore
        // blocks the thread without pumping anything.
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            return []
        }

        // Read on a background queue so a shell that never writes cannot pin
        // this thread past the deadline.
        let box = OutputBox()
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            box.set(pipe.fileHandleForReading.readDataToEndOfFile())
            finished.signal()
        }

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return []
        }

        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return []
        }

        guard process.terminationStatus == 0,
              let value = String(data: box.get(), encoding: .utf8)
        else { return [] }

        return value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":")
            .map(String.init)
    }

    /// Lock-guarded box so the reader thread and this one can share a `Data`
    /// without tripping strict concurrency checking.
    private final class OutputBox: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func set(_ value: Data) {
            lock.lock(); data = value; lock.unlock()
        }

        func get() -> Data {
            lock.lock(); defer { lock.unlock() }; return data
        }
    }
}
