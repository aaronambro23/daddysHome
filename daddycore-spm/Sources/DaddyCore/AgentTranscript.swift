import Foundation

/// What an agent CLI's own on-disk record says about one live session.
///
/// Daddy used to guess at both of these. The model came from a hardcoded table
/// that was wrong for three of the four providers, and the state came from
/// pattern-matching a terminal byte stream. Every one of these CLIs writes the
/// answer down as it goes; this reads it.
public struct TranscriptReading: Sendable, Equatable {

    /// Where the conversation is in its turn.
    ///
    /// Deliberately not `AgentState`: a transcript knows about turns, not about
    /// rate limits, crashes or permission prompts. Those stay the screen's job.
    public enum Activity: Sendable, Equatable {
        /// You sent something and the agent has not started answering.
        case prompted
        /// Mid-turn — generating, or running a tool.
        case responding
        /// The turn finished.
        case idle
    }

    /// The model the agent is actually running, as the CLI names it.
    public let model: String?
    public let activity: Activity?
    /// When the record this was read from was written, where the CLI says so;
    /// otherwise the file's modification date.
    public let observedAt: Date

    public init(model: String?, activity: Activity?, observedAt: Date) {
        self.model = model
        self.activity = activity
        self.observedAt = observedAt
    }
}

/// Reads one CLI's record of a session.
///
/// Implementations are stateless and cheap to make; they do real I/O, so never
/// call them from the main thread.
public protocol AgentTranscriptSource: Sendable {

    /// The file whose changes mean "this session did something", or nil when
    /// this CLI has no such file. Used by the watcher, not by `read`.
    func transcriptURL(cwd: URL, providerSessionID: String?) -> URL?

    /// What the CLI currently says about this session.
    func read(cwd: URL, providerSessionID: String?) -> TranscriptReading?

    /// The model this CLI would use for a new session, from its config. The
    /// answer before a transcript exists to read.
    func defaultModel() -> String?
}

public enum AgentTranscripts {
    public static func source(for kind: AgentKind) -> AgentTranscriptSource {
        switch kind {
        case .claude: return ClaudeTranscript()
        case .codex: return CodexTranscript()
        case .cursor: return CursorTranscript()
        case .opencode: return OpenCodeTranscript()
        }
    }
}

// MARK: - Shared file reading

enum TranscriptFile {

    /// How much of the end of a transcript to read.
    ///
    /// These files reach tens of megabytes. Everything that says what a session
    /// is doing *now* is in the last few records, and reading the whole thing
    /// once a second per agent would be absurd.
    static let tailBytes = 128 * 1024

    /// The last `bytes` of `url` as whole lines.
    ///
    /// The first line is dropped unless the read happened to start at the
    /// beginning of the file: a byte-capped tail almost always begins mid-line,
    /// and half a JSON object is worse than no JSON object.
    static func tailLines(of url: URL, bytes: Int = tailBytes) -> [Substring] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd() else { return [] }
        let offset = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd(), !data.isEmpty else { return [] }

        let text = String(decoding: data, as: UTF8.self)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        if offset > 0, !lines.isEmpty { lines.removeFirst() }
        return lines
    }

    /// The first `bytes` of `url` as whole lines — for identifying which
    /// session a file belongs to without reading all of it.
    static func headLines(of url: URL, bytes: Int = 16 * 1024) -> [Substring] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: bytes), !data.isEmpty else { return [] }

        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        return text.hasSuffix("\n") ? Array(lines) : Array(lines.dropLast())
    }

    static func json(_ line: Substring) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func json(contentsOf url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func modifiedAt(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? Date()
    }

    /// Paths compared the way a user means them: symlinks resolved, no trailing
    /// slash. `/tmp` and `/private/tmp` are the same directory.
    static func samePath(_ lhs: String, _ rhs: String) -> Bool {
        URL(fileURLWithPath: lhs).resolvingSymlinksInPath().standardizedFileURL.path
            == URL(fileURLWithPath: rhs).resolvingSymlinksInPath().standardizedFileURL.path
    }

    static func date(_ value: Any?) -> Date? {
        if let string = value as? String {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string)
        }
        if let number = value as? NSNumber {
            let seconds = number.doubleValue
            return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1000 : seconds)
        }
        return nil
    }
}
