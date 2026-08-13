import Foundation

/// Opens an agent in Terminal.app, already briefed.
///
/// Daddy spawns; the work happens in the user's own terminal. Nothing is
/// rendered inside the app and no pty is owned here — Terminal.app owns the
/// process tree, which is the whole point of this branch.
///
/// Terminal.app is the target because its AppleScript `do script` support is
/// solid; Ghostty and Warp have far weaker automation.
public struct TerminalLauncher: Sendable {

    public enum LaunchError: LocalizedError {
        case executableMissing(String)
        case projectMissing(String)
        case appleScriptFailed(String)

        public var errorDescription: String? {
            switch self {
            case .executableMissing(let name):
                return "\(name) is not on your PATH"
            case .projectMissing(let path):
                return "Project directory not found: \(path)"
            case .appleScriptFailed(let message):
                return "Terminal.app refused the command: \(message)"
            }
        }
    }

    public init() {}

    // MARK: - Prompts

    /// The brief handed to a *continuing* agent. This is the feature: a new
    /// session opens already knowing which document to read and what is left,
    /// instead of being re-explained the project by hand.
    public static func continuePrompt(documentPath: String) -> String {
        """
        Read AGENTS.md, then read \(documentPath). \
        Continue from the tasks that are not yet ticked. \
        Do not redo work that is already checked off. \
        Tick each task as you complete it, and close the document with a \
        summary and your recommended next steps.
        """
    }

    /// The brief handed to an agent starting fresh work.
    public static func newBatchPrompt(nextNumber: Int) -> String {
        let filename = String(format: "%03d", nextNumber)
        return """
        Read AGENTS.md first. Review \(WorkflowContract.handoffDirectory)/ to \
        see what has already been done. Ask me what this batch should cover \
        before writing any code, then create \
        \(WorkflowContract.handoffDirectory)/\(filename)-<slug>.md with the \
        plan as unticked checkboxes.
        """
    }

    // MARK: - Launching

    /// - Parameters:
    ///   - agent: which CLI to run.
    ///   - projectPath: working directory; the agent is launched here.
    ///   - prompt: initial prompt. All four CLIs accept one as an argument, so
    ///     the session opens already holding its context.
    ///   - extraArguments: e.g. model flags.
    @discardableResult
    public func launch(
        agent: AgentKind,
        executableName: String,
        projectPath: URL,
        prompt: String?,
        extraArguments: [String] = []
    ) throws -> String {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: projectPath.path, isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw LaunchError.projectMissing(projectPath.path)
        }

        guard let resolved = ExecutableResolver.resolve(executableName) else {
            throw LaunchError.executableMissing(executableName)
        }

        let command = shellCommand(
            executable: resolved,
            projectPath: projectPath,
            prompt: prompt,
            extraArguments: extraArguments
        )

        try runAppleScript(doScript: command)
        return command
    }

    /// The shell line Terminal.app runs. Exposed for testing and so the UI can
    /// show the user exactly what it is about to do.
    public func shellCommand(
        executable: String,
        projectPath: URL,
        prompt: String?,
        extraArguments: [String] = []
    ) -> String {
        var parts = ["cd \(Self.shellQuote(projectPath.path))"]

        var invocation = [Self.shellQuote(executable)]
        invocation.append(contentsOf: extraArguments.map(Self.shellQuote))
        if let prompt, !prompt.isEmpty {
            invocation.append(Self.shellQuote(Self.collapseWhitespace(prompt)))
        }

        parts.append(invocation.joined(separator: " "))
        return parts.joined(separator: " && ")
    }

    // MARK: - AppleScript

    private func runAppleScript(doScript command: String) throws {
        let script = """
        tell application "Terminal"
            activate
            do script "\(Self.appleScriptQuote(command))"
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw LaunchError.appleScriptFailed(error.localizedDescription)
        }

        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "exit \(process.terminationStatus)"
            throw LaunchError.appleScriptFailed(message)
        }
    }

    // MARK: - Quoting
    //
    // Two layers of escaping, and both matter: the command is embedded in an
    // AppleScript string literal, which is itself handed to a shell. Project
    // paths contain spaces ("Obsidian Vault") and prompts contain apostrophes.

    /// Single-quote for the shell, escaping any embedded single quotes.
    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Escape for inclusion in an AppleScript double-quoted string.
    static func appleScriptQuote(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Prompts are written as multi-line Swift literals; Terminal wants one line.
    static func collapseWhitespace(_ value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
