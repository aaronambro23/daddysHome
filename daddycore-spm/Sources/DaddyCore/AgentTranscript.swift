import Foundation

/// How much of its context window a session has spent — or why we cannot say.
///
/// This used to be `Double?`, and the nil meant four different things: this CLI
/// never reports usage, we could not find this session's record, the session
/// has not taken a turn yet, or the tail we read happened to hold no usage.
/// They rendered identically — an empty bar — so a broken link and a CLI doing
/// its best looked the same. Naming them is the whole point of this type.
public enum ContextAvailability: Sendable, Equatable {
    /// A real reading, 0–100.
    case reported(Double)

    /// This CLI does not write its token usage down anywhere. Nothing is
    /// broken; there is genuinely nothing to read.
    case notReported

    /// The CLI does report usage, but we cannot find this session's record.
    /// Daddy's link to the conversation is broken — the actionable one.
    case transcriptMissing

    /// The record is there and holds no usage yet. A session that has not
    /// taken a turn.
    case noTurnYet

    public var percent: Double? {
        if case .reported(let value) = self { return value }
        return nil
    }
}

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

    /// How much of the model's context window this session has spent, and when
    /// there is no number, which of the several reasons applies.
    public let context: ContextAvailability

    /// What this conversation is about, in a few words.
    ///
    /// Not derived here. Claude titles its own conversations and writes the
    /// result into the transcript, which is a better title than anything read
    /// off the first message could be — it is written from the conversation
    /// rather than from its opening line. Where a CLI does not do that, the
    /// first thing you asked for is the fallback, and where there is neither
    /// this is nil and the card keeps its work-unit id.
    public let title: String?

    public var contextUsedPercent: Double? { context.percent }

    /// The same reading with its activity replaced — for when the CLI states
    /// outright what the transcript could only be read for hints of.
    ///
    /// A stated activity is observed *now*, whatever the transcript's own
    /// timestamp says. That distinction matters because callers discard stale
    /// readings: the last record of a session idle for an hour is an hour old
    /// and tells you nothing about this second, while a status file naming a
    /// process that is alive right now describes this second exactly.
    public func stating(_ activity: Activity?) -> TranscriptReading {
        guard let activity else { return self }
        return TranscriptReading(
            model: model,
            activity: activity,
            observedAt: Date(),
            context: context,
            title: title
        )
    }

    /// The same reading with a title supplied from elsewhere — used when the
    /// transcript has not produced one yet but the CLI's status file has.
    public func titled(_ title: String?) -> TranscriptReading {
        guard self.title == nil, let title else { return self }
        return TranscriptReading(
            model: model,
            activity: activity,
            observedAt: observedAt,
            context: context,
            title: title
        )
    }

    public init(
        model: String?,
        activity: Activity?,
        observedAt: Date,
        context: ContextAvailability = .notReported,
        title: String? = nil
    ) {
        self.model = model
        self.activity = activity
        self.observedAt = observedAt
        self.title = title
        if case .reported(let percent) = context {
            self.context = .reported(min(max(percent, 0), 100))
        } else {
            self.context = context
        }
    }
}

/// What a CLI's per-process status file says about the conversation it is on.
///
/// Two answers from one small file: *which* conversation (which survives
/// `/clear`, where the launch-time id does not) and what it is doing (which the
/// CLI states outright, where the transcript has to be inferred from the shape
/// of the last record written).
public struct LiveConversation: Sendable, Equatable {
    public let id: String
    /// Nil when the file used a word this build does not recognise — better to
    /// fall back to the transcript than to invent a meaning for it.
    public let activity: TranscriptReading.Activity?
    /// The CLI's own name for the conversation, if it has one.
    public let name: String?

    public init(id: String, activity: TranscriptReading.Activity?, name: String? = nil) {
        self.id = id
        self.activity = activity
        self.name = name
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

    /// What this *process* is on right now, if the CLI publishes it somewhere
    /// addressable by pid.
    ///
    /// The id Daddy holds is established once, at launch, and a conversation is
    /// not a process: `/clear` starts a new one inside the same running CLI,
    /// and from that moment the id names a file nothing will ever write to
    /// again. That reads as a frozen percentage rather than a broken link,
    /// which is worse than an error — it is a confident wrong number.
    ///
    /// Nil where the CLI publishes nothing, which leaves the transcript as the
    /// only source for both answers.
    func liveConversation(pid: Int32, cwd: URL) -> LiveConversation?

    /// The opening of the conversation — the first few things said, as plain
    /// text — for titling a conversation whose CLI does not title it itself.
    ///
    /// Only the messages: no tool calls, no diffs, no reasoning. A title is
    /// about the subject, and a page of shell output is not the subject.
    func openingExcerpt(cwd: URL, providerSessionID: String?) -> String?

    /// Whether this CLI names its own conversations. When it does, its title
    /// is the one to use: it is written from the whole conversation rather
    /// than from the first thing that happened in it.
    var titlesConversations: Bool { get }

    /// Whether this CLI records its token usage at all.
    ///
    /// The difference between "there is nothing to read" and "we lost the
    /// file", which is what stops a broken link from hiding behind a CLI
    /// limitation.
    var reportsContextUsage: Bool { get }
}

public extension AgentTranscriptSource {
    /// Most CLIs publish nothing of the kind.
    func liveConversation(pid: Int32, cwd: URL) -> LiveConversation? { nil }

    /// Nothing readable, which leaves the conversation untitled.
    func openingExcerpt(cwd: URL, providerSessionID: String?) -> String? { nil }

    /// Claude is currently the only one that does.
    var titlesConversations: Bool { false }
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

    /// A line of prose cut down to something that fits on a card.
    ///
    /// Takes the first non-empty line, drops the markdown that would render as
    /// punctuation soup at 10pt, and cuts on a word boundary. A prompt that
    /// opens with a pasted stack trace makes a poor title whatever we do; this
    /// only has to beat `live-0827-1041-3`.
    static func title(fromPrompt text: String, limit: Int = 52) -> String? {
        let firstLine = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map(String.init) ?? ""

        let cleaned = firstLine
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return nil }
        guard cleaned.count > limit else { return cleaned }

        let clipped = String(cleaned.prefix(limit))
        guard let lastSpace = clipped.lastIndex(of: " ") else { return clipped + "…" }
        return clipped[clipped.startIndex..<lastSpace] + "…"
    }

    /// A CLI's own name for a conversation, made readable.
    ///
    /// Claude's `ai-title` starts as prose and is rewritten to a slug as the
    /// conversation settles — `context-handoff-system` — and the status file's
    /// `name` is always the slug. Both are the same fact in different dress, so
    /// both get the same treatment: hyphens back to spaces, one capital at the
    /// front. A title that already has spaces is left exactly as written.
    static func humanTitle(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }

        guard !trimmed.contains(" ") else { return trimmed }

        let spaced = trimmed.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
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
