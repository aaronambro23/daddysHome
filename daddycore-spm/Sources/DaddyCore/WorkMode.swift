import Foundation

/// How much process an agent should wrap around the work.
///
/// The workflow contract in `AGENTS.md` is written for a large, planned batch:
/// ask questions first, read the recent handoff documents, open a document,
/// tick its boxes as you go. That is the right shape for a week of work and the
/// wrong shape for "this div is misaligned, fix it" — where the reading alone
/// costs more than the fix, and every tick is another round trip.
///
/// The mode is chosen per session, not per project, because two agents in the
/// same repository are often doing those two different kinds of work at once.
public enum WorkMode: String, Codable, Sendable, CaseIterable {
    /// Do the thing. No clarifying questions unless the request is genuinely
    /// ambiguous, no reading of prior handoffs unless the prompt asks, no batch
    /// document unless asked for.
    case quick

    /// The full contract: questions first, plan agreed, one document per batch,
    /// boxes ticked as they are finished.
    case detailed

    public var displayName: String {
        switch self {
        case .quick: return "Quick"
        case .detailed: return "Detailed"
        }
    }

    public var summary: String {
        switch self {
        case .quick: return "Execute. Minimal reading, no documents."
        case .detailed: return "Questions first, plan agreed, documented."
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
        case .quick:
            return """
                WORK MODE: QUICK. Follow the QUICK mode rules in AGENTS.md — \
                execute the request directly, skip the clarifying-questions and \
                handoff-reading steps, and do not create or update a batch \
                document unless asked. If AGENTS.md has no QUICK mode section, \
                apply that behaviour anyway.
                """
        case .detailed:
            // The contract's own default. Saying so again would only spend
            // tokens repeating what the file already says.
            return nil
        }
    }

    /// Sent into a running session to change its mode without a restart.
    ///
    /// A launched process cannot have its system prompt rewritten, so switching
    /// mid-conversation is a message rather than a flag. It works on every CLI,
    /// which the flag does not.
    public var switchInstruction: String {
        switch self {
        case .quick:
            return "Switch to QUICK mode for the rest of this session: "
                + "execute directly, skip clarifying questions and handoff reading, "
                + "and write no batch document unless I ask. See AGENTS.md."
        case .detailed:
            return "Switch to DETAILED mode for the rest of this session: "
                + "the full AGENTS.md workflow contract — questions first, plan "
                + "agreed, one batch document with its boxes ticked as you go."
        }
    }
}
