import Foundation

// MARK: - Claude Code
//
// The easiest of the four, because Daddy already tells Claude which id to use
// (`ClaudeAdapter.mintsSessionID`), so the transcript's filename is known
// rather than guessed at.

struct ClaudeTranscript: AgentTranscriptSource {

    func transcriptURL(cwd: URL, providerSessionID: String?) -> URL? {
        guard let id = providerSessionID, !id.isEmpty else { return nil }

        // Which project directory Claude filed it under depends on its own
        // slug rule, which `ChatHistory` deliberately refuses to reimplement
        // and so does this. The filename is the session id, so look for it.
        let fileManager = FileManager.default
        guard let projects = try? fileManager.contentsOfDirectory(
            at: ChatHistory.claudeProjectsRoot,
            includingPropertiesForKeys: nil
        ) else { return nil }

        for project in projects {
            let candidate = project.appendingPathComponent("\(id).jsonl")
            if fileManager.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    func read(cwd: URL, providerSessionID: String?) -> TranscriptReading? {
        guard let url = transcriptURL(cwd: cwd, providerSessionID: providerSessionID) else {
            return nil
        }

        var model: String?
        var activity: TranscriptReading.Activity?
        var observedAt: Date?
        var contextPercent: Double?
        var title: String?

        // Newest first. A transcript carries a lot of bookkeeping records
        // (`attachment`, `mode`, `ai-title`, `queue-operation`…); only `user`
        // and `assistant` say anything about whose turn it is.
        for line in TranscriptFile.tailLines(of: url).reversed() {
            guard let record = TranscriptFile.json(line),
                  let type = record["type"] as? String else { continue }

            switch type {
            case "assistant":
                let message = record["message"] as? [String: Any]
                if model == nil { model = message?["model"] as? String }
                // A sidechain record is a subagent's turn, written into the
                // same file. Its usage is the subagent's own small context, so
                // reading it would report a nearly-full session as empty.
                if contextPercent == nil, (record["isSidechain"] as? Bool) != true {
                    // Every assistant record carries the usage of the request
                    // that produced it, and that request *is* the conversation:
                    // whatever was replayed from cache plus whatever was sent
                    // fresh. Summing the four is the size of the context at
                    // that moment, which is the number the CLI's own footer
                    // shows you.
                    contextPercent = Self.contextPercent(
                        usage: message?["usage"] as? [String: Any],
                        model: message?["model"] as? String
                    )
                }
                if activity == nil {
                    // A finished turn stops with `end_turn`. `tool_use` means
                    // a tool call follows, so the turn is still running. Nil
                    // means the record was written mid-stream — treat that as
                    // busy, because a wrong "idle" invites you to interrupt
                    // something mid-thought.
                    let stop = message?["stop_reason"] as? String
                    activity = (stop == "end_turn" || stop == "stop_sequence")
                        ? .idle
                        : .responding
                    observedAt = TranscriptFile.date(record["timestamp"])
                }

            case "user":
                if activity == nil {
                    // A `user` record carrying a tool_result is the harness
                    // feeding a tool's output back in, not you typing.
                    activity = Self.isToolResult(record) ? .responding : .prompted
                    observedAt = TranscriptFile.date(record["timestamp"])
                }

            case "ai-title":
                // Claude names its own conversations and rewrites the name as
                // they develop, so the newest of these is the current answer.
                if title == nil { title = TranscriptFile.humanTitle(record["aiTitle"] as? String) }

            default:
                continue
            }

            if model != nil, activity != nil, title != nil { break }
        }

        guard model != nil || activity != nil else { return nil }
        return TranscriptReading(
            model: model,
            activity: activity,
            observedAt: observedAt ?? TranscriptFile.modifiedAt(url),
            // The file was found, so a missing percentage here means this
            // conversation has not taken a turn yet — not that the link is
            // broken. `transcriptReading` owns that second case.
            context: contextPercent.map { .reported($0) } ?? .noTurnYet,
            title: title
        )
    }

    var reportsContextUsage: Bool { true }
    var titlesConversations: Bool { true }

    /// Claude keeps a status file per running process — `sessions/<pid>.json`
    /// — whose `sessionId` is the conversation it is on *now* and whose
    /// `status` is what it is doing. That file is the one thing on disk that
    /// survives `/clear`: the transcript forks to a new file with a new id, and
    /// this one is rewritten to name it.
    ///
    /// Checked against `cwd` before it is believed. A pid is reused by the
    /// operating system eventually, and adopting a stale file's id would point
    /// the card at some unrelated conversation.
    func liveConversation(pid: Int32, cwd: URL) -> LiveConversation? {
        let status = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/sessions/\(pid).json")

        guard let record = TranscriptFile.json(contentsOf: status),
              let id = record["sessionId"] as? String, !id.isEmpty else { return nil }

        if let recorded = record["cwd"] as? String,
           !TranscriptFile.samePath(recorded, cwd.path) { return nil }

        return LiveConversation(
            id: id,
            activity: Self.activity(record["status"]),
            // A slug — `kanban-board-per-project`. Second-best to the
            // transcript's own `ai-title`, and available a good deal earlier
            // in a conversation's life.
            name: TranscriptFile.humanTitle(record["name"] as? String)
        )
    }

    /// `busy` and `idle` are the two words this file has been observed to use.
    ///
    /// Anything else returns nil rather than a guess — an unknown word from a
    /// newer Claude must not be flattened into "idle", because a wrong idle is
    /// what invites you to interrupt an agent mid-thought, and it is also what
    /// would fire a context handoff in the middle of a turn.
    private static func activity(_ status: Any?) -> TranscriptReading.Activity? {
        switch status as? String {
        case "idle": return .idle
        case "busy": return .responding
        default: return nil
        }
    }

    func defaultModel() -> String? {
        let settings = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        return TranscriptFile.json(contentsOf: settings)?["model"] as? String
    }

    /// Model ids whose context window is 1M rather than 200K.
    ///
    /// A hardcoded table, which this file otherwise refuses to keep — but the
    /// transcript genuinely does not record the window. Every record was read
    /// looking for it; the only thing that knows is the CLI's own `/context`,
    /// and that is rendered, never written down.
    ///
    /// Matched on a fragment of the id, so dated snapshots
    /// (`claude-sonnet-5-20260101`) resolve the same as the bare id.
    private static let longContextModels = [
        "opus-5", "sonnet-5", "fable-5", "mythos-5",
        "opus-4-8", "opus-4-7", "opus-4-6", "sonnet-4-6",
    ]

    /// Share of the window one request's usage represents.
    ///
    /// The unknown-model fallback is 200K on purpose. Guessing small means a
    /// wide session reads as fuller than it is and Daddy offers the handoff
    /// early; guessing large means a narrow one is reported as half empty right
    /// up to the moment it compacts. Early is the survivable mistake.
    private static func contextPercent(
        usage: [String: Any]?,
        model: String?
    ) -> Double? {
        guard let usage else { return nil }

        let fields = [
            "input_tokens",
            "cache_read_input_tokens",
            "cache_creation_input_tokens",
            "output_tokens",
        ]
        let used = fields.reduce(0.0) { total, key in
            total + ((usage[key] as? NSNumber)?.doubleValue ?? 0)
        }
        guard used > 0 else { return nil }

        return used / contextWindow(for: model) * 100
    }

    static func contextWindow(for model: String?) -> Double {
        guard let model = model?.lowercased() else { return 200_000 }
        // An explicit marker beats the table — it is the model saying so.
        if model.contains("[1m]") { return 1_000_000 }
        // Haiku is 200K in every generation, including the ones whose Opus and
        // Sonnet siblings are 1M, so it is checked before the family match.
        if model.contains("haiku") { return 200_000 }
        return longContextModels.contains(where: model.contains) ? 1_000_000 : 200_000
    }

    private static func isToolResult(_ record: [String: Any]) -> Bool {
        guard let message = record["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else { return false }
        return content.contains { $0["type"] as? String == "tool_result" }
    }
}

// MARK: - Codex
//
// Codex cannot be told its session id at launch, so its rollout file is found
// by matching the `cwd` its own header records.

struct CodexTranscript: AgentTranscriptSource {

    /// How many recent rollout files to consider. Codex accumulates thousands
    /// over time and only the newest few could belong to a live session.
    private static let candidateLimit = 40

    /// How much of a rollout's head to read when identifying it.
    ///
    /// Generous because `session_meta` is one line that embeds the entire base
    /// instructions — 22KB in a real file here. A smaller budget cuts that
    /// single line in half, `headLines` correctly discards the fragment, and
    /// every rollout then looks like it belongs to nobody.
    private static let headerBytes = 96 * 1024

    private static var sessionsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
    }

    func transcriptURL(cwd: URL, providerSessionID: String?) -> URL? {
        let fileManager = FileManager.default
        guard let walker = fileManager.enumerator(
            at: Self.sessionsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var candidates: [(url: URL, at: Date)] = []
        for case let url as URL in walker
        where url.lastPathComponent.hasPrefix("rollout-")
            && url.pathExtension == "jsonl" {
            candidates.append((url, TranscriptFile.modifiedAt(url)))
        }

        let wanted = cwd.path
        for candidate in candidates.sorted(by: { $0.at > $1.at })
            .prefix(Self.candidateLimit) {
            for line in TranscriptFile.headLines(of: candidate.url, bytes: Self.headerBytes) {
                guard let record = TranscriptFile.json(line),
                      record["type"] as? String == "session_meta",
                      let payload = record["payload"] as? [String: Any],
                      let path = payload["cwd"] as? String else { continue }
                if TranscriptFile.samePath(path, wanted) { return candidate.url }
                break   // the header is the first record; no need to read on
            }
        }
        return nil
    }

    func read(cwd: URL, providerSessionID: String?) -> TranscriptReading? {
        guard let url = transcriptURL(cwd: cwd, providerSessionID: providerSessionID) else {
            return nil
        }

        var model: String?
        var activity: TranscriptReading.Activity?
        var observedAt: Date?
        var contextPercent: Double?

        // Codex does not title its conversations, so the opening request is
        // the best available. It is at the head of the file, which is read
        // anyway to work out that this rollout belongs to this directory.
        let title = Self.openingRequest(in: url)

        for line in TranscriptFile.tailLines(of: url).reversed() {
            guard let record = TranscriptFile.json(line),
                  let type = record["type"] as? String,
                  let payload = record["payload"] as? [String: Any] else { continue }

            switch type {
            case "turn_context":
                if model == nil { model = payload["model"] as? String }

            case "event_msg":
                if contextPercent == nil, payload["type"] as? String == "token_count" {
                    // `total_token_usage` is cumulative over the session and
                    // routinely exceeds the window — it is a bill, not a
                    // measurement. `last_token_usage` is the size of the most
                    // recent request, which is what the context actually holds.
                    let info = payload["info"] as? [String: Any]
                    let last = info?["last_token_usage"] as? [String: Any]
                    let used = (last?["total_tokens"] as? NSNumber)?.doubleValue
                    let window = (info?["model_context_window"] as? NSNumber)?.doubleValue
                    if let used, let window, used > 0, window > 0 {
                        contextPercent = used / window * 100
                    }
                }

                if activity == nil {
                    switch payload["type"] as? String {
                    case "task_started":
                        activity = .responding
                        observedAt = TranscriptFile.date(record["timestamp"])
                    case "task_complete":
                        activity = .idle
                        observedAt = TranscriptFile.date(record["timestamp"])
                    default:
                        break
                    }
                }

            default:
                continue
            }

            if model != nil, activity != nil, contextPercent != nil { break }
        }

        guard model != nil || activity != nil else { return nil }
        return TranscriptReading(
            model: model,
            activity: activity,
            observedAt: observedAt ?? TranscriptFile.modifiedAt(url),
            context: contextPercent.map { .reported($0) } ?? .noTurnYet,
            title: title
        )
    }

    /// The first message you typed, as opposed to the several the harness
    /// types on your behalf — skills instructions, `AGENTS.md`, the world
    /// state. Codex marks the real one: an `item_completed` event carrying a
    /// `UserMessage`.
    private static func openingRequest(in url: URL) -> String? {
        guard let first = messages(in: url, limit: 1).first else { return nil }
        return TranscriptFile.title(fromPrompt: first.text)
    }

    func openingExcerpt(cwd: URL, providerSessionID: String?) -> String? {
        guard let url = transcriptURL(cwd: cwd, providerSessionID: providerSessionID) else {
            return nil
        }

        let opening = Self.messages(in: url, limit: 5)
        guard !opening.isEmpty else { return nil }

        return opening
            .map { "\($0.role): \($0.text.prefix(600))" }
            .joined(separator: "\n\n")
    }

    /// The first `limit` things actually said, in order.
    ///
    /// Codex types several messages on your behalf before you get a word in —
    /// the skills instructions, `AGENTS.md`, the world state — and those are
    /// plain `response_item` records. The `item_completed` events are the real
    /// conversation, which is why they are what this reads.
    private static func messages(
        in url: URL,
        limit: Int
    ) -> [(role: String, text: String)] {
        var found: [(role: String, text: String)] = []

        for line in TranscriptFile.headLines(of: url, bytes: headerBytes) {
            guard let record = TranscriptFile.json(line),
                  record["type"] as? String == "event_msg",
                  let payload = record["payload"] as? [String: Any],
                  payload["type"] as? String == "item_completed",
                  let item = payload["item"] as? [String: Any],
                  let kind = item["type"] as? String,
                  kind == "UserMessage" || kind == "AgentMessage" else { continue }

            guard let text = Self.text(of: item["content"]), !text.isEmpty else { continue }

            found.append((kind == "UserMessage" ? "user" : "assistant", text))
            if found.count >= limit { break }
        }
        return found
    }

    /// `content` is usually a list of typed blocks and occasionally a bare
    /// string. Taking only the text blocks keeps images and the like from
    /// contributing nothing but a separator.
    private static func text(of content: Any?) -> String? {
        if let string = content as? String { return string }
        if let blocks = content as? [[String: Any]] {
            return blocks
                .compactMap { $0["text"] as? String }
                .joined(separator: " ")
        }
        return nil
    }

    var reportsContextUsage: Bool { true }

    func defaultModel() -> String? {
        let config = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/config.toml")
        guard let text = try? String(contentsOf: config, encoding: .utf8) else { return nil }

        // Only the top-level `model = "…"`, before the first [section]. A
        // per-project table further down is not this session's default.
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { break }
            guard trimmed.hasPrefix("model") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "model" else {
                continue
            }
            return parts[1]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return nil
    }
}

// MARK: - OpenCode
//
// OpenCode keeps everything in SQLite rather than in files, so there is nothing
// to tail; the session row carries both the model and its last-touched time.

struct OpenCodeTranscript: AgentTranscriptSource {

    private static var database: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencode/opencode.db")
    }

    /// Nothing to watch: the change lands inside a database, and a watcher on
    /// the file would fire on every WAL checkpoint regardless of session.
    func transcriptURL(cwd: URL, providerSessionID: String?) -> URL? { nil }

    func read(cwd: URL, providerSessionID: String?) -> TranscriptReading? {
        guard FileManager.default.fileExists(atPath: Self.database.path) else { return nil }

        let escaped = cwd.path.replacingOccurrences(of: "'", with: "''")
        let query = """
        SELECT model, time_updated FROM session \
        WHERE directory = '\(escaped)' ORDER BY time_updated DESC LIMIT 1;
        """

        // Read-only so a running OpenCode is never blocked or migrated.
        guard let output = shell(
            "/usr/bin/sqlite3",
            ["file:\(Self.database.path)?mode=ro", query]
        ) else { return nil }

        let row = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !row.isEmpty else { return nil }

        let columns = row.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard let modelJSON = columns.first else { return nil }

        // `model` is a JSON blob: {"id":"gpt-5.6-luna","providerID":…,"variant":"high"}
        var model: String?
        if let data = modelJSON.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let id = object["id"] as? String {
            if let variant = object["variant"] as? String, !variant.isEmpty {
                model = "\(id) (\(variant))"
            } else {
                model = id
            }
        }

        var observedAt = Date()
        if columns.count == 2, let millis = Double(columns[1]) {
            observedAt = Date(timeIntervalSince1970: millis / 1000)
        }

        guard model != nil else { return nil }
        return TranscriptReading(model: model, activity: nil, observedAt: observedAt)
    }

    /// The session row carries the model and a timestamp, and no token column.
    var reportsContextUsage: Bool { false }

    func defaultModel() -> String? { nil }

    private func shell(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors

        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Cursor
//
// Cursor stores conversations as an opaque `blobs(id, data BLOB)` table, so
// there is no per-session answer to be had. Its CLI config records the model
// the next session will use, which is the best available and is right whenever
// you have not switched models inside one agent.

struct CursorTranscript: AgentTranscriptSource {

    private static var config: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/cli-config.json")
    }

    func transcriptURL(cwd: URL, providerSessionID: String?) -> URL? { nil }

    /// Global rather than per-session — see the note above. Two Cursor agents
    /// running different models will both show whichever was picked last.
    func read(cwd: URL, providerSessionID: String?) -> TranscriptReading? {
        guard let model = defaultModel() else { return nil }
        return TranscriptReading(
            model: model,
            activity: nil,
            observedAt: TranscriptFile.modifiedAt(Self.config)
        )
    }

    /// Conversations live in an opaque `blobs(id, data BLOB)` table — there is
    /// no per-session anything, let alone token counts.
    var reportsContextUsage: Bool { false }

    func defaultModel() -> String? {
        guard let root = TranscriptFile.json(contentsOf: Self.config) else { return nil }
        if let selected = root["selectedModel"] as? [String: Any],
           let id = selected["modelId"] as? String, !id.isEmpty {
            return id
        }
        if let model = root["model"] as? [String: Any],
           let id = model["modelId"] as? String, !id.isEmpty {
            return id
        }
        return nil
    }
}
