import Foundation

/// A conversation that already happened, as the picker needs to show it.
public struct PastChat: Identifiable, Hashable, Sendable {
    /// The id the CLI knows it by — what you hand back to `--resume`.
    public let id: String
    public let agent: AgentKind
    /// The directory the conversation ran in.
    public let cwd: String
    /// The opening request, trimmed to something that fits on a menu row.
    public let title: String
    public let updatedAt: Date

    public init(id: String, agent: AgentKind, cwd: String, title: String, updatedAt: Date) {
        self.id = id
        self.agent = agent
        self.cwd = cwd
        self.title = title
        self.updatedAt = updatedAt
    }
}

/// Reads conversations off disk, so a chat can be reopened long after the app
/// that started it was quit.
///
/// This deliberately does **not** reimplement Claude's directory-slug rule.
/// Slugging `/Users/me/My Project` to `-Users-me-My-Project` is easy to guess
/// at and easy to get subtly wrong — dots, spaces and underscores all collapse,
/// two different paths can produce one slug, and the rule belongs to Claude
/// rather than to us, so it can change without warning. Every session file
/// records its own `cwd`, so that is what gets matched instead: one probe read
/// per project directory identifies it, and only a directory that matches is
/// read properly.
public enum ChatHistory {

    /// Where Claude Code keeps its transcripts.
    public static var claudeProjectsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }

    /// Bytes read from a file when all we want is which directory it belongs
    /// to. The `cwd` field is on the first non-trivial line.
    private static let probeBytes = 16_384

    /// Bytes read when the file is one we actually care about. The opening
    /// request is near the top; a transcript can be tens of megabytes, and
    /// none of the rest of it is wanted here.
    private static let readBytes = 262_144

    /// Conversations that ran in `directory`, newest first.
    ///
    /// Includes chats started in a plain terminal — they are the same files —
    /// which is the point: Daddy should be able to reopen anything you have
    /// worked on in a project, not only what it started itself.
    public static func claudeChats(inDirectory directory: String, limit: Int = 40) -> [PastChat] {
        let wanted = canonical(directory)
        let fm = FileManager.default

        guard let projectDirs = try? fm.contentsOfDirectory(
            at: claudeProjectsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var chats: [PastChat] = []

        for projectDir in projectDirs where projectDir.hasDirectoryPath {
            let transcripts = self.transcripts(in: projectDir)
            guard let probe = transcripts.first else { continue }

            // One read decides the whole directory: every transcript in it
            // shares a cwd, because the directory is named after that cwd.
            guard let probedCWD = cwd(ofTranscript: probe, bytes: probeBytes),
                  canonical(probedCWD) == wanted else { continue }

            for transcript in transcripts {
                if let chat = describe(transcript, agent: .claude) {
                    chats.append(chat)
                }
            }
        }

        return Array(
            chats
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(limit)
        )
    }

    // MARK: - Reading one transcript

    /// Nil when the file holds no actual conversation — a session that was
    /// opened and closed without asking anything leaves a file behind, and it
    /// is not worth offering to reopen.
    static func describe(_ url: URL, agent: AgentKind) -> PastChat? {
        guard let text = prefix(of: url, bytes: readBytes) else { return nil }

        var foundCWD: String?
        var title: String?

        for line in completeLines(of: text) {
            guard let object = jsonObject(line) else { continue }

            if foundCWD == nil, let value = object["cwd"] as? String {
                foundCWD = value
            }
            if title == nil, let opening = userText(object) {
                title = opening
            }
            if foundCWD != nil && title != nil { break }
        }

        guard let cwd = foundCWD, let title else { return nil }

        return PastChat(
            id: url.deletingPathExtension().lastPathComponent,
            agent: agent,
            cwd: cwd,
            title: summarize(title),
            updatedAt: modifiedAt(url) ?? .distantPast
        )
    }

    private static func cwd(ofTranscript url: URL, bytes: Int) -> String? {
        guard let text = prefix(of: url, bytes: bytes) else { return nil }
        for line in completeLines(of: text) {
            if let value = jsonObject(line)?["cwd"] as? String { return value }
        }
        return nil
    }

    /// The text of a genuine user turn, or nil for anything that is not one.
    ///
    /// A transcript's early lines are mostly not conversation: mode records,
    /// slash-command echoes, the pasted-context caveat, tool results. Titling a
    /// chat "<command-name>/resume" would make the picker useless.
    private static func userText(_ object: [String: Any]) -> String? {
        guard object["type"] as? String == "user" else { return nil }
        guard object["isMeta"] as? Bool != true else { return nil }
        guard object["isSidechain"] as? Bool != true else { return nil }
        guard let message = object["message"] as? [String: Any] else { return nil }

        let text: String
        if let string = message["content"] as? String {
            text = string
        } else if let blocks = message["content"] as? [[String: Any]] {
            // A turn carrying only tool results is the transcript talking to
            // itself, not a request.
            let spoken = blocks
                .filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }
            guard !spoken.isEmpty else { return nil }
            text = spoken.joined(separator: " ")
        } else {
            return nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let ignoredPrefixes = [
            "<command-name>", "<local-command-stdout>", "<command-message>",
            "<system-reminder>", "Caveat:", "<user-prompt-submit-hook>",
        ]
        guard !ignoredPrefixes.contains(where: { trimmed.hasPrefix($0) }) else { return nil }

        return trimmed
    }

    // MARK: - Helpers

    private static func transcripts(in projectDir: URL) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: projectDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries
            .filter { $0.pathExtension == "jsonl" }
            .sorted { (modifiedAt($0) ?? .distantPast) > (modifiedAt($1) ?? .distantPast) }
    }

    /// Reads at most `bytes` from the front of a file.
    ///
    /// `String(contentsOf:)` on an 11MB transcript to read its first line is
    /// the kind of thing that only shows up as a stutter once a project has
    /// some history in it.
    private static func prefix(of url: URL, bytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: bytes), !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
            ?? String(decoding: data, as: UTF8.self)
    }

    /// Drops the trailing fragment, which a byte-capped read will usually have
    /// cut in the middle of a line.
    private static func completeLines(of text: String) -> [Substring] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard text.hasSuffix("\n") else { return lines.dropLast() }
        return Array(lines)
    }

    private static func jsonObject(_ line: Substring) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// One line. The cap is generous because the menu row truncates visually to
    /// its own width — cutting hard at a small number here would put a second
    /// ellipsis in the middle of an already-shortened title.
    private static func summarize(_ text: String, limit: Int = 96) -> String {
        let flattened = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let collapsed = flattened.split(separator: " ").joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        return collapsed.prefix(limit).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Trailing slashes and symlinks would otherwise make the same directory
    /// fail to match itself.
    private static func canonical(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let resolved = URL(fileURLWithPath: expanded).resolvingSymlinksInPath().path
        guard resolved.count > 1, resolved.hasSuffix("/") else { return resolved }
        return String(resolved.dropLast())
    }

    private static func modifiedAt(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
    }
}
