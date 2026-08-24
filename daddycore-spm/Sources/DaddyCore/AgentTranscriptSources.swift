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

            default:
                continue
            }

            if model != nil, activity != nil { break }
        }

        guard model != nil || activity != nil else { return nil }
        return TranscriptReading(
            model: model,
            activity: activity,
            observedAt: observedAt ?? TranscriptFile.modifiedAt(url)
        )
    }

    func defaultModel() -> String? {
        let settings = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        return TranscriptFile.json(contentsOf: settings)?["model"] as? String
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

        for line in TranscriptFile.tailLines(of: url).reversed() {
            guard let record = TranscriptFile.json(line),
                  let type = record["type"] as? String,
                  let payload = record["payload"] as? [String: Any] else { continue }

            switch type {
            case "turn_context":
                if model == nil { model = payload["model"] as? String }

            case "event_msg":
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

            if model != nil, activity != nil { break }
        }

        guard model != nil || activity != nil else { return nil }
        return TranscriptReading(
            model: model,
            activity: activity,
            observedAt: observedAt ?? TranscriptFile.modifiedAt(url)
        )
    }

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
