import Foundation

/// Plain login shells, addressed by an opaque id.
///
/// Nothing to do with agents. These are the terminals you use *yourself* while
/// an agent works beside you: run the app locally, `cd` around, check
/// `git status`, commit and push — without leaving Daddy to do it.
///
/// Deliberately not routed through `SessionManager`. A `Session` has a
/// non-optional `AgentKind`, and a shell is not an agent: forcing a fifth case
/// into that enum would leak "shell" into the adapters, the state heuristics,
/// the launch menus and the handoff-document writer, all of which exist to
/// describe agents. What a shell needs is a pty, and `PTYProcess` already is
/// one — process-group shutdown, resize, incremental UTF-8 decoding and all.
///
/// No state detection runs on these. `OutputHeuristics` reads agent chatter for
/// signs of working or waiting; a shell prompt is not a status.
///
/// ## Why the key is a shell id and not a project id
///
/// It used to be one shell per project, keyed by the project. Tabs ended that:
/// a project has several shells now, in an order the user set, one of which is
/// on screen. Ordering, numbering and "which one is showing" are all facts
/// about the *interface*, and none of them survive a look at this file — so
/// they live in `MockStore` and this stays a registry that starts a shell, hands
/// it back, and kills it when asked.
public final class ShellSessions: @unchecked Sendable {
    private var shells: [String: PTYProcess] = [:]
    private let lock = NSLock()

    public init() {}

    /// The user's own shell, not a guess. Falls back to zsh, which is the macOS
    /// default, rather than to `sh` — a login shell with none of someone's
    /// aliases or PATH in it is not the shell they asked for.
    public static var loginShellPath: String {
        ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    /// The shell with this id, started on first ask and kept afterwards.
    ///
    /// Persistence is the point: a dev server started here keeps serving while
    /// you go and work in another project, and comes back still running.
    ///
    /// - Important: this launches a process. Never call it from inside a
    ///   SwiftUI `body` — spawning during layout is what crashed the launch
    ///   menu when it resolved executables while rendering.
    @discardableResult
    public func shell(id: String, cwd: URL) throws -> PTYProcess {
        lock.lock()
        if let existing = shells[id], existing.isProcessRunning {
            lock.unlock()
            return existing
        }
        lock.unlock()

        let pty = PTYProcess(
            executablePath: Self.loginShellPath,
            // Login shell, so ~/.zprofile and ~/.zshrc are read and the prompt,
            // aliases and PATH are the ones the user actually has. The pty
            // makes it interactive; no `-i` needed.
            arguments: ["-l"],
            cwd: cwd
        )
        try pty.launch()

        lock.lock()
        shells[id] = pty
        lock.unlock()

        return pty
    }

    /// The running shell with this id, without starting one. Safe to call from
    /// a view body.
    public func existing(id: String) -> PTYProcess? {
        lock.lock()
        defer { lock.unlock() }
        return shells[id]
    }

    /// Ends one shell — and whatever it was running.
    public func close(id: String) {
        lock.lock()
        let pty = shells.removeValue(forKey: id)
        lock.unlock()

        pty?.terminate()
    }

    /// Called at app teardown. A shell running `npm run dev` owns a whole tree
    /// of node processes; leaving them behind would leak a server holding a
    /// port every time Daddy quits.
    public func shutdownAll() {
        lock.lock()
        let all = Array(shells.values)
        shells.removeAll()
        lock.unlock()

        for pty in all {
            pty.shutdown(graceSeconds: 1.0)
        }
    }
}
