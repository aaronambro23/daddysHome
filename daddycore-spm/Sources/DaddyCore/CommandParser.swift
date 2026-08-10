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
    private let dictionary: [String: CommandIntent]

    public init(customDictionary: [String: CommandIntent]? = nil) {
        if let customDictionary = customDictionary {
            self.dictionary = customDictionary
        } else {
            self.dictionary = Self.defaultDictionary()
        }
    }

    public func parse(_ transcript: String) -> ParsedCommand {
        let normalized = transcript.lowercased().trimmingCharacters(in: .whitespaces)

        var agent: AgentKind?
        var model: String?
        var targetAgent: AgentKind?
        var remainingText = normalized

        // Extract agent name
        (agent, remainingText) = extractAgent(from: remainingText)

        // Extract model if present
        if let extractedModel = extractModel(from: remainingText, for: agent) {
            model = extractedModel
            remainingText = removeModel(from: remainingText, model: extractedModel)
        }

        // Extract intent keyword
        let intent = extractIntent(from: remainingText)

        // For handoff, extract target agent
        if case .handoff = intent {
            (targetAgent, _) = extractAgent(from: remainingText)
        }

        // Everything else is the prompt
        let prompt = remainingText.trimmingCharacters(in: .whitespaces)
        let promptText = prompt.isEmpty ? nil : prompt

        return ParsedCommand(
            intent: intent,
            agent: agent,
            model: model,
            prompt: promptText,
            targetAgent: targetAgent
        )
    }

    private func extractAgent(from text: String) -> (AgentKind?, String) {
        let agentPatterns: [(pattern: String, agent: AgentKind)] = [
            ("claude", .claude),
            ("codex", .codex),
            ("cursor", .cursor),
            ("opencode", .opencode),
            ("open code", .opencode),
        ]

        for (pattern, agent) in agentPatterns {
            if text.hasPrefix(pattern) {
                let remaining = String(text.dropFirst(pattern.count)).trimmingCharacters(in: .whitespaces)
                return (agent, remaining)
            }
        }

        return (nil, text)
    }

    private func extractModel(from text: String, for agent: AgentKind?) -> String? {
        let modelPatterns = [
            "opus", "sonnet", "haiku", "fable",  // Claude
            "gpt-5", "gpt-4", "gpt-3.5",          // Generic
            "o1", "o3",                           // Reasoning
            "claude-opus", "claude-sonnet",       // Full names
        ]

        for pattern in modelPatterns {
            if text.contains(pattern) {
                return pattern
            }
        }

        return nil
    }

    private func removeModel(from text: String, model: String) -> String {
        return text.replacingOccurrences(of: model, with: "").trimmingCharacters(in: .whitespaces)
    }

    private func extractIntent(from text: String) -> CommandIntent {
        for (keyword, intent) in dictionary {
            if text.contains(keyword) {
                return intent
            }
        }

        return .unknown(text)
    }

    private static func defaultDictionary() -> [String: CommandIntent] {
        return [
            // Continue/work
            "continue": .work,
            "keep going": .work,
            "go": .work,
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
