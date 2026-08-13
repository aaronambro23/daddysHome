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
    case unknown(String)  // unknown intent
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

    private static let agentPatterns: [(pattern: String, agent: AgentKind)] = [
        ("opencode", .opencode),
        ("open code", .opencode),
        ("claude", .claude),
        ("codex", .codex),
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
        var result = text
        for (pattern, _) in Self.agentPatterns {
            result = result.replacingOccurrences(
                of: "\\b" + NSRegularExpression.escapedPattern(for: pattern) + "\\b",
                with: " ",
                options: .regularExpression
            )
        }
        return result
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
        ]
    }
}
