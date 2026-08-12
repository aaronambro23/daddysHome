import Foundation

/// Installs the workflow contract into a project so every CLI behaves the same.
///
/// Writes `AGENTS.md` (read by Codex, Cursor and opencode) and a one-line
/// `CLAUDE.md` containing `@AGENTS.md` (Claude Code expands the import), so the
/// contract lives in exactly one file.
public struct ContractInstaller: Sendable {

    public enum InstallError: LocalizedError {
        case notADirectory(String)
        case writeFailed(String, underlying: String)

        public var errorDescription: String? {
            switch self {
            case .notADirectory(let path):
                return "Not a directory: \(path)"
            case .writeFailed(let file, let underlying):
                return "Could not write \(file): \(underlying)"
            }
        }
    }

    public struct Result: Sendable {
        public let agentsPath: URL
        public let claudePath: URL
        /// Files that existed and were backed up before being overwritten.
        public let backedUp: [URL]
        public let createdHandoffDirectory: Bool
    }

    public init() {}

    /// - Parameter projectPath: the project the agents work in, **not** Daddy's
    ///   own repository.
    @discardableResult
    public func install(into projectPath: URL, projectName: String? = nil) throws -> Result {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: projectPath.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw InstallError.notADirectory(projectPath.path)
        }

        let name = projectName ?? projectPath.lastPathComponent
        let agentsURL = projectPath.appendingPathComponent("AGENTS.md")
        let claudeURL = projectPath.appendingPathComponent("CLAUDE.md")

        // Overwrite, but never destroy. Some of these files carry real project
        // knowledge rather than the generated boilerplate.
        var backedUp: [URL] = []
        for url in [agentsURL, claudeURL] where FileManager.default.fileExists(atPath: url.path) {
            if let backup = try backUp(url) { backedUp.append(backup) }
        }

        try write(WorkflowContract.agentsMarkdown(projectName: name), to: agentsURL)
        try write(WorkflowContract.claudeImport, to: claudeURL)

        let handoffs = projectPath.appendingPathComponent(WorkflowContract.handoffDirectory)
        var created = false
        if !FileManager.default.fileExists(atPath: handoffs.path) {
            try? FileManager.default.createDirectory(
                at: handoffs, withIntermediateDirectories: true
            )
            created = FileManager.default.fileExists(atPath: handoffs.path)
        }

        return Result(
            agentsPath: agentsURL,
            claudePath: claudeURL,
            backedUp: backedUp,
            createdHandoffDirectory: created
        )
    }

    /// True when the contract is already present and current.
    public func isInstalled(in projectPath: URL) -> Bool {
        let agents = projectPath.appendingPathComponent("AGENTS.md")
        guard let text = try? String(contentsOf: agents, encoding: .utf8) else { return false }
        return text.contains(WorkflowContract.handoffDirectory)
            && text.contains("Working agreement")
    }

    // MARK: - Helpers

    /// Copies to `<name>.bak`, or `<name>.bak.N` when that is taken, so
    /// reinstalling never clobbers an earlier backup.
    private func backUp(_ url: URL) throws -> URL? {
        var backup = url.appendingPathExtension("bak")
        var counter = 1
        while FileManager.default.fileExists(atPath: backup.path) {
            backup = url.appendingPathExtension("bak.\(counter)")
            counter += 1
            if counter > 50 { return nil }
        }

        do {
            try FileManager.default.copyItem(at: url, to: backup)
            return backup
        } catch {
            throw InstallError.writeFailed(
                backup.lastPathComponent, underlying: error.localizedDescription
            )
        }
    }

    private func write(_ contents: String, to url: URL) throws {
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw InstallError.writeFailed(
                url.lastPathComponent, underlying: error.localizedDescription
            )
        }
    }
}
