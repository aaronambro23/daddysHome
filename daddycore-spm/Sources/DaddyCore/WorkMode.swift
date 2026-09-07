import Foundation

/// How much process an agent should wrap around the work.
///
/// The workflow contract in `AGENTS.md` defines four modes, and this enum is
/// the app's handle on them. The contract is written so a large planned batch
/// and "this div is misaligned, fix it" do not get the same ceremony: reading
/// three handoff documents costs more than the fix, and every tick is another
/// round trip.
///
/// The mode is chosen per session, not per project, because two agents in the
/// same repository are often doing different kinds of work at once.
public enum WorkMode: String, Codable, Sendable, CaseIterable {
    /// Small, obvious, low-risk change scoped to a handful of known files.
    /// Execute directly. No plan, no subagents, no handoff document.
    case targeted

    /// The full contract: questions first, plan agreed, verified properly,
    /// one document per batch when the work warrants one.
    case planAndBuild

    /// Answer a question or investigate. No code changes.
    case exploreAndResearch

    /// Something is broken. Root-cause first, fix, then reproduce to confirm.
    case debug

    /// The mode a session starts in when nothing else says otherwise.
    ///
    /// Plan & Build is the contract's own default — it is the mode whose rules
    /// the body of `AGENTS.md` is written in.
    public static let `default`: WorkMode = .planAndBuild

    /// Parses a stored value, accepting the two names this enum used before it
    /// grew to four.
    ///
    /// Without this a saved default of `quick` or `detailed` reads back as nil
    /// and silently resets, which for a preference that persists across every
    /// launch is worse than a two-line map.
    public static func fromStored(_ raw: String) -> WorkMode? {
        if let mode = WorkMode(rawValue: raw) { return mode }
        switch raw {
        case "quick": return .targeted
        case "detailed": return .planAndBuild
        default: return nil
        }
    }

    public var displayName: String {
        switch self {
        case .targeted: return "Targeted"
        case .planAndBuild: return "Plan & Build"
        case .exploreAndResearch: return "Explore"
        case .debug: return "Debug"
        }
    }

    /// Uppercase and short, for controls that put four of these side by side.
    public var shortName: String {
        switch self {
        case .targeted: return "TARGETED"
        case .planAndBuild: return "PLAN"
        case .exploreAndResearch: return "EXPLORE"
        case .debug: return "DEBUG"
        }
    }

    public var iconName: String {
        switch self {
        case .targeted: return "bolt.fill"
        case .planAndBuild: return "sparkles"
        case .exploreAndResearch: return "magnifyingglass"
        case .debug: return "ladybug.fill"
        }
    }

    public var summary: String {
        switch self {
        case .targeted:
            return "Execute. Minimal reading, no documents."
        case .planAndBuild:
            return "Questions first, plan agreed, documented."
        case .exploreAndResearch:
            return "Investigate and report. No code changes."
        case .debug:
            return "Root-cause first, then verify the fix."
        }
    }

    /// The slash command that selects this mode from a session's own input.
    ///
    /// Claude Code parses `/name` itself, so these need no interception on our
    /// side — the files in `.claude/commands/` carry the same instruction the
    /// button sends.
    public var slashCommand: String {
        switch self {
        case .targeted: return "/targeted"
        case .planAndBuild: return "/plan"
        case .exploreAndResearch: return "/explore"
        case .debug: return "/debug"
        }
    }

    /// What gets injected into the agent's system prompt at launch.
    ///
    /// Deliberately tiny. The definitions live in `AGENTS.md`, which every one
    /// of these CLIs already reads, so this only has to *name* the mode — a
    /// dozen tokens per session rather than a restatement of the contract. It
    /// also means editing the rules is editing one file in the project, not
    /// rebuilding the app.
    public var systemPrompt: String? {
        switch self {
        case .planAndBuild:
            // The contract's own default. Saying so again would only spend
            // tokens repeating what the file already says.
            return nil
        case .targeted:
            return """
                WORK MODE: TARGETED. Follow the Targeted mode rules in \
                AGENTS.md — execute the request directly, skip the \
                clarifying-questions and handoff-reading steps, use no \
                subagents, and do not create or update a batch document \
                unless asked. If AGENTS.md has no Targeted mode section, \
                apply that behaviour anyway.
                """
        case .exploreAndResearch:
            return """
                WORK MODE: EXPLORE & RESEARCH. Follow the Explore & Research \
                mode rules in AGENTS.md — investigate and report, make no \
                code changes, and cite what you actually found rather than \
                what you inferred. If AGENTS.md has no Explore & Research \
                section, apply that behaviour anyway.
                """
        case .debug:
            return """
                WORK MODE: DEBUG. Follow the Debug mode rules in AGENTS.md — \
                state your root-cause hypothesis before changing anything, \
                fix the cause rather than the symptom, and reproduce the \
                failure after the fix to confirm it is resolved. If \
                AGENTS.md has no Debug section, apply that behaviour anyway.
                """
        }
    }

    /// Sent into a running session to change its mode without a restart.
    ///
    /// A launched process cannot have its system prompt rewritten, so switching
    /// mid-conversation is a message rather than a flag. It works on every CLI,
    /// which the flag does not.
    public var switchInstruction: String {
        switch self {
        case .targeted:
            return "Switch to TARGETED mode for the rest of this session: "
                + "execute directly, skip clarifying questions and handoff reading, "
                + "no subagents, and write no batch document unless I ask. See AGENTS.md."
        case .planAndBuild:
            return "Switch to PLAN & BUILD mode for the rest of this session: "
                + "the full AGENTS.md workflow contract — questions first, plan "
                + "agreed before any code, verified properly, and a batch document "
                + "if the work warrants one."
        case .exploreAndResearch:
            return "Switch to EXPLORE & RESEARCH mode for the rest of this session: "
                + "investigate and answer, make no code changes, and cite what you "
                + "actually found rather than what you inferred. See AGENTS.md."
        case .debug:
            return "Switch to DEBUG mode for the rest of this session: "
                + "state your root-cause hypothesis before changing anything, fix "
                + "the cause and not the symptom, and reproduce the failure after "
                + "the fix to confirm it is resolved. See AGENTS.md."
        }
    }
}
