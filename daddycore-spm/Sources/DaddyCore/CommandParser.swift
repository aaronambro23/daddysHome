import Foundation

public enum CommandIntent: Equatable {
    case work          // start/continue work
    case stop          // stop working
    case resume        // resume session
    case interrupt     // interrupt current work
    case review        // review code
    case handoff       // give to another agent
    case status        // query status
    case runTests      // run tests
    case switchModel   // switch model
    case launch        // launch a new agent
    case unknown(String)  // unknown intent

    // Kanban intents. `CommandParser` lives in DaddyCore, which has no
    // knowledge of `OrchestratorWorkItem`/`OrchestratorWorkStatus`/
    // `OrchestratorWorkCategory` (DaddyApp-only types), so these carry raw
    // string hints rather than app types — resolving a hint against live
    // project/column/category names happens in DaddyApp's
    // `VoiceKanbanResolver`, not here.
    case createWorkItem(title: String, projectHint: String?, statusHint: String?, categoryHint: String?)
    case moveWorkItem(targetHint: String, statusHint: String?, categoryHint: String?)
    // `AgentKind` lives in DaddyCore too, so unlike the project/status/
    // category hints above, this one can just be the resolved type.
    case dispatchWorkItem(targetHint: String, agentHint: AgentKind?)
}

public struct ParsedCommand {
    public var intent: CommandIntent
    public var agent: AgentKind?
    public var model: String?
    public var prompt: String?
    public var targetAgent: AgentKind?

    public init(
        intent: CommandIntent,
        agent: AgentKind? = nil,
        model: String? = nil,
        prompt: String? = nil,
        targetAgent: AgentKind? = nil
    ) {
        self.intent = intent
        self.agent = agent
        self.model = model
        self.prompt = prompt
        self.targetAgent = targetAgent
    }
}

public final class CommandParser {

    /// Keywords in the order they are tested: longest first, then alphabetically.
    ///
    /// This used to iterate a `Dictionary` directly, whose order is not stable
    /// between runs. When two keywords both matched — "what's" (status) and "go"
    /// inside "going" (work) — the winner changed from run to run, and the test
    /// suite failed a different number of times each time it was run. Order is
    /// now part of the contract: the most specific phrase wins.
    private let rankedKeywords: [(keyword: String, intent: CommandIntent)]

    public init(customDictionary: [String: CommandIntent]? = nil) {
        let dictionary = customDictionary ?? Self.defaultDictionary()
        self.rankedKeywords = dictionary
            .map { (keyword: $0.key, intent: $0.value) }
            .sorted { lhs, rhs in
                if lhs.keyword.count != rhs.keyword.count {
                    return lhs.keyword.count > rhs.keyword.count
                }
                return lhs.keyword < rhs.keyword
            }
    }

    public func parse(_ transcript: String) -> ParsedCommand {
        let normalized = transcript.lowercased().trimmingCharacters(in: .whitespaces)

        // Kanban commands are recognized before anything else and return
        // early — they don't go through model/agent stripping or the
        // keyword-ranking table, which know nothing about work items.
        if let kanbanIntent = extractKanbanIntent(from: normalized) {
            return ParsedCommand(intent: kanbanIntent)
        }

        // Model first: "claude-opus" is one model name, and stripping the agent
        // out of it would leave "-opus" and report the wrong thing.
        var model: String?
        var withoutModel = normalized
        if let extractedModel = extractModel(from: normalized, for: nil) {
            model = extractedModel
            withoutModel = removeModel(from: normalized, model: extractedModel)
        }

        let mentions = agentMentions(in: withoutModel)
        let agent = mentions.first
        let textWithoutModel = removingAgentNames(from: withoutModel)

        let intent = extractIntent(from: textWithoutModel)

        // "hand this to codex" — the agent named is the one being handed *to*.
        var targetAgent: AgentKind?
        if case .handoff = intent {
            targetAgent = mentions.last
        }

        // The intent keyword is deliberately left in the prompt: "fix the login
        // bug" is both the instruction and the thing to say to the agent.
        let prompt = textWithoutModel
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:!?-—"))
        let promptText = prompt.isEmpty ? nil : prompt

        return ParsedCommand(
            intent: intent,
            agent: agent,
            model: model,
            prompt: promptText,
            targetAgent: targetAgent
        )
    }

    // MARK: - Kanban

    private static let createTriggers = ["add a task", "add task", "create a task", "create task", "new task"]
    private static let moveTriggers = ["move", "recategorize", "refile"]
    private static let dispatchTriggers = ["dispatch", "send this to", "assign this to"]

    /// Good-enough phrase matching, not a general NLU system — same spirit
    /// as the keyword table above. Recognizes a leading verb phrase, then
    /// pulls "to `<project>` project" / "category `<category>`" / a status
    /// word out of whatever follows, leaving the remainder as the title (for
    /// create) or the target description (for move/dispatch).
    private func extractKanbanIntent(from text: String) -> CommandIntent? {
        if let trigger = Self.createTriggers.first(where: { text.hasPrefix($0) }) {
            var remainder = String(text.dropFirst(trigger.count)).trimmingCharacters(in: .whitespaces)
            let projectHint = extractClause(&remainder, pattern: "\\b([a-z0-9][a-z0-9 \\-]*?)\\s+project\\b")
            let categoryHint = extractClause(&remainder, pattern: "\\bcategory\\s+([a-z0-9][a-z0-9 /\\-]*?)(?=,|$)")
            let statusHint = extractClause(&remainder, pattern: "\\b(backlog|verify|dispatched|in\\s*progress|rework|done)\\b")
            let title = cleaned(remainder)
            guard !title.isEmpty else { return nil }
            return .createWorkItem(title: title, projectHint: projectHint, statusHint: statusHint, categoryHint: categoryHint)
        }

        if let trigger = Self.moveTriggers.first(where: { text.hasPrefix($0 + " ") }) {
            var remainder = String(text.dropFirst(trigger.count)).trimmingCharacters(in: .whitespaces)
            let categoryHint = extractClause(&remainder, pattern: "\\bcategory\\s+([a-z0-9][a-z0-9 /\\-]*?)(?=,|$)")
            let statusHint = extractClause(&remainder, pattern: "\\b(?:to|into)\\s+(backlog|verify|dispatched|in\\s*progress|rework|done)\\b")
                ?? extractClause(&remainder, pattern: "\\b(backlog|verify|dispatched|in\\s*progress|rework|done)\\b")
            let target = cleaned(remainder)
            guard !target.isEmpty, statusHint != nil || categoryHint != nil else { return nil }
            return .moveWorkItem(targetHint: target, statusHint: statusHint, categoryHint: categoryHint)
        }

        if let trigger = Self.dispatchTriggers.first(where: { text.hasPrefix($0 + " ") || text.hasPrefix($0) }) {
            var remainder = String(text.dropFirst(trigger.count)).trimmingCharacters(in: .whitespaces)
            let agentHint = agentMentions(in: remainder).first
            remainder = removingAgentNames(from: remainder)
            let target = cleaned(remainder)
            guard !target.isEmpty else { return nil }
            return .dispatchWorkItem(targetHint: target, agentHint: agentHint)
        }

        return nil
    }

    /// Finds `pattern`'s first capture group in `text`, removes the whole
    /// match from `text` in place, and returns the captured (trimmed) value.
    private func extractClause(_ text: inout String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2 else { return nil }

        let groupRange = match.range(at: 1)
        guard groupRange.location != NSNotFound else { return nil }
        let value = ns.substring(with: groupRange).trimmingCharacters(in: .whitespaces)

        let mutable = NSMutableString(string: text)
        mutable.replaceCharacters(in: match.range(at: 0), with: " ")
        text = String(mutable)

        return value.isEmpty ? nil : value
    }

    private func cleaned(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s*,\\s*", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:!?-—"))
    }

    private static let agentPatterns: [(pattern: String, agent: AgentKind)] = [
        ("opencode", .opencode),
        ("open code", .opencode),
        ("claude", .claude),
        ("cloud", .claude),       // Transcription: "Claude" → "cloud"
        ("claud", .claude),       // Transcription: dropped final sound
        ("clawed", .claude),      // Transcription: phonetic spelling
        ("collade", .claude),     // Transcription observed in HEX history
        ("codex", .codex),
        ("codecs", .codex),      // Transcription: "codex" → "codecs"
        ("codes", .codex),        // Transcription: "codex" → "codes"
        ("cursor", .cursor),
    ]

    /// Every agent named in the sentence, in the order they appear.
    ///
    /// This used to be `hasPrefix`, so an agent was only recognised at the very
    /// start — "continue codex" found nothing.
    private func agentMentions(in text: String) -> [AgentKind] {
        var found: [(index: String.Index, agent: AgentKind)] = []

        for (pattern, agent) in Self.agentPatterns {
            var searchStart = text.startIndex
            while let range = text.range(
                of: "\\b" + NSRegularExpression.escapedPattern(for: pattern) + "\\b",
                options: .regularExpression,
                range: searchStart..<text.endIndex
            ) {
                found.append((range.lowerBound, agent))
                searchStart = range.upperBound
                if searchStart >= text.endIndex { break }
            }
        }

        // "opencode" and "open code" can both hit; keep first mention per kind.
        var seen = Set<AgentKind>()
        return found
            .sorted { $0.index < $1.index }
            .compactMap { seen.insert($0.agent).inserted ? $0.agent : nil }
    }

    private func removingAgentNames(from text: String) -> String {
        // Remove only the first mention of each agent. A transcription alias can
        // also be meaningful prompt text: "Claude, fix cloud deployment" must
        // retain "cloud" instead of stripping both same-agent matches.
        var firstRangeByAgent: [AgentKind: NSRange] = [:]
        for (pattern, agent) in Self.agentPatterns {
            guard let range = text.range(
                of: "\\b" + NSRegularExpression.escapedPattern(for: pattern) + "\\b",
                options: .regularExpression
            ) else { continue }

            let nsRange = NSRange(range, in: text)
            if let existing = firstRangeByAgent[agent], existing.location <= nsRange.location {
                continue
            }
            firstRangeByAgent[agent] = nsRange
        }

        let result = NSMutableString(string: text)
        for range in firstRangeByAgent.values.sorted(by: { $0.location > $1.location }) {
            result.replaceCharacters(in: range, with: " ")
        }

        return String(result)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private func extractModel(from text: String, for agent: AgentKind?) -> String? {
        let modelPatterns = [
            "claude-opus", "claude-sonnet",       // Full names, before the bare ones
            "gpt-3.5", "gpt-5", "gpt-4",          // Generic
            "opus", "sonnet", "haiku", "fable",   // Claude
            "o1", "o3",                           // Reasoning
        ]

        // Longest first, so "claude-opus" is not reported as "opus".
        for pattern in modelPatterns where contains(text, word: pattern) {
            return pattern
        }

        return nil
    }

    private func removeModel(from text: String, model: String) -> String {
        text
            .replacingOccurrences(
                of: "\\b" + NSRegularExpression.escapedPattern(for: model) + "\\b",
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private func extractIntent(from text: String) -> CommandIntent {
        for (keyword, intent) in rankedKeywords where contains(text, word: keyword) {
            return intent
        }

        return .unknown(text)
    }

    /// Whole-word match. Substring matching is what made "go" fire inside
    /// "going" and "para" inside "parameter".
    private func contains(_ text: String, word: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        return text.range(of: "\\b" + escaped + "\\b", options: .regularExpression) != nil
    }

    private static func defaultDictionary() -> [String: CommandIntent] {
        return [
            // Continue/work
            "continue": .work,
            "keep going": .work,
            "go": .work,
            "fix": .work,
            "work on": .work,
            "build": .work,
            "write": .work,
            "dal": .work,           // Spanish: "dale"
            "dale": .work,          // Spanish
            "segui": .work,         // Spanish: "seguí"
            "prosigue": .work,      // Spanish

            // Stop
            "stop": .stop,
            "halt": .stop,
            "pause": .stop,
            "frena": .stop,         // Spanish: "frena"
            "para": .stop,          // Spanish: "para"
            "pará": .stop,          // Spanish: "pará"

            // Resume
            "resume": .resume,
            "restart": .resume,

            // Interrupt
            "interrupt": .interrupt,
            "break": .interrupt,
            "esc": .interrupt,

            // Review
            "review": .review,
            "check": .review,
            "revisa": .review,      // Spanish: "revisa"
            "revisá": .review,      // Spanish: "revisá"

            // Handoff
            "handoff": .handoff,
            "hand off": .handoff,
            "hand": .handoff,
            "give": .handoff,
            "take over": .handoff,
            "pasalo": .handoff,     // Spanish: "pasalo"
            "pasáselo": .handoff,   // Spanish: "pasáselo"

            // Status
            "status": .status,
            "what's": .status,
            "whats": .status,
            "what is": .status,
            "onda": .status,        // Spanish: "qué onda" (colloquial)
            "estado": .status,      // Spanish

            // Tests
            "test": .runTests,
            "tests": .runTests,
            "run tests": .runTests,
            "corre los tests": .runTests,  // Spanish: "corré los tests"
            "corré": .runTests,     // Spanish: "corré"

            // Model switch
            "switch": .switchModel,
            "change model": .switchModel,
            "model": .switchModel,

            // Launch
            "start": .launch,
            "launch": .launch,
            "begin": .launch,
            "open": .launch,
        ]
    }
}
