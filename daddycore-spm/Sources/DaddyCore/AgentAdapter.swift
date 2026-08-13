import Foundation

public enum ApprovalPolicy: String {
    case safeAuto = "safe-auto"
    case fullBypass = "full-bypass"
}

public protocol AgentAdapter: AnyObject {
    static var kind: AgentKind { get }
    static var executablePath: String { get }

    /// What this CLI treats as "stop what you are doing, but stay alive".
    /// Claude and Cursor listen for ESC; Codex and OpenCode want Ctrl-C.
    var interruptInput: TerminalInput { get }

    func launchArgs(
        cwd: URL,
        model: ModelRef?,
        approvalPolicy: ApprovalPolicy
    ) -> [String]

    /// Extra arguments that make this CLI pick up its previous conversation
    /// instead of starting a blank one, or nil if it cannot.
    ///
    /// Relaunching otherwise gets you the same agent in the same directory with
    /// no memory of what you were doing, which is rarely what "relaunch" means
    /// to the person clicking it.
    var continueConversationArgs: [String]? { get }

    func modelFlagValue(for humanName: String) -> String?

    func sendPrompt(_ text: String, to pty: PTYProcess) throws

    func selectModel(_ model: ModelRef, on pty: PTYProcess) throws

    func interrupt(_ pty: PTYProcess) throws

    /// Tell an agent that has stopped — interrupted, or paused waiting on you —
    /// to keep going.
    func resume(_ pty: PTYProcess) throws

    func detectState(fromRecentOutput buffer: String) -> AgentState
}

// Every adapter used to carry its own copy of these four, identical except for
// the interrupt byte. That duplication is why one bug had to be fixed four
// times. They live here now; an adapter overrides only what it genuinely does
// differently.
extension AgentAdapter {

    public func sendPrompt(_ text: String, to pty: PTYProcess) throws {
        try pty.send(.text(text))
        // A TTY submits on carriage return. `\n` is a line feed, which some of
        // these composers insert as a newline instead of sending.
        try pty.send(.key(.enter))
    }

    public func selectModel(_ model: ModelRef, on pty: PTYProcess) throws {
        try sendPrompt("/model " + model.rawValue, to: pty)
    }

    public func interrupt(_ pty: PTYProcess) throws {
        try pty.send(interruptInput)
    }

    public func resume(_ pty: PTYProcess) throws {
        try sendPrompt("continue", to: pty)
    }
}

public final class ClaudeAdapter: AgentAdapter {
    public static let kind = AgentKind.claude
    public static let executablePath = "claude"

    public let interruptInput = TerminalInput.key(.escape)

    /// `claude --continue` resumes the most recent conversation in this
    /// directory.
    public let continueConversationArgs: [String]? = ["--continue"]

    public init() {}

    public func launchArgs(
        cwd: URL,
        model: ModelRef?,
        approvalPolicy: ApprovalPolicy
    ) -> [String] {
        var args: [String]

        switch approvalPolicy {
        case .safeAuto:
            args = ["--permission-mode", "acceptEdits"]
        case .fullBypass:
            args = ["--dangerously-skip-permissions"]
        }

        if let model = model {
            args.append("--model")
            args.append(model.rawValue)
        }

        return args
    }

    public func modelFlagValue(for humanName: String) -> String? {
        let normalized = humanName.lowercased().trimmingCharacters(in: .whitespaces)

        let aliases: [String: String] = [
            "opus": "opus",
            "sonnet": "sonnet",
            "haiku": "haiku",
            "fable": "fable",
        ]

        return aliases[normalized]
    }

    public func detectState(fromRecentOutput buffer: String) -> AgentState {
        let window = OutputHeuristics.recentWindow(buffer).lowercased()
        return OutputHeuristics.resolve(window: window) { text in
            text.contains(">>>")
                || text.contains("claude >")
                || text.contains("? for shortcuts")
                || OutputHeuristics.endsWithPrompt(text)
        }
    }
}

public final class CodexAdapter: AgentAdapter {
    public static let kind = AgentKind.codex
    public static let executablePath = "codex"

    public let interruptInput = TerminalInput.interrupt

    /// Unknown. Codex has a `resume` subcommand rather than a flag, and the
    /// exact form has not been confirmed against the installed CLI — so
    /// relaunching Codex starts a fresh conversation rather than guessing at an
    /// invocation that would fail outright. See STATUS.md open questions.
    public let continueConversationArgs: [String]? = nil

    public init() {}

    public func launchArgs(
        cwd: URL,
        model: ModelRef?,
        approvalPolicy: ApprovalPolicy
    ) -> [String] {
        var args: [String] = []

        if let model = model {
            args.append("-m")
            args.append(model.rawValue)
        }

        switch approvalPolicy {
        case .safeAuto:
            args += ["--ask-for-approval", "on-request", "--sandbox", "workspace-write"]
        case .fullBypass:
            args += ["--ask-for-approval", "never", "--sandbox", "danger-full-access"]
        }

        return args
    }

    public func modelFlagValue(for humanName: String) -> String? {
        humanName.lowercased().trimmingCharacters(in: .whitespaces)
    }

    public func detectState(fromRecentOutput buffer: String) -> AgentState {
        let window = OutputHeuristics.recentWindow(buffer).lowercased()
        // The old check here was `contains(">") || contains("codex")`, which is
        // true of essentially every byte Codex ever prints.
        return OutputHeuristics.resolve(window: window) { text in
            OutputHeuristics.endsWithPrompt(text)
        }
    }
}

public final class CursorAdapter: AgentAdapter {
    public static let kind = AgentKind.cursor
    public static let executablePath = "agent"

    public let interruptInput = TerminalInput.key(.escape)

    /// From `agent --help`: `--continue  Continue previous session`.
    public let continueConversationArgs: [String]? = ["--continue"]

    public init() {}

    public func launchArgs(
        cwd: URL,
        model: ModelRef?,
        approvalPolicy: ApprovalPolicy
    ) -> [String] {
        var args: [String] = []

        if let model = model {
            args.append("--model")
            args.append(model.rawValue)
        }

        // From `agent --help`:
        //   --auto-review  server classifier auto-runs safe tool calls and
        //                  prompts for the rest
        //   -f, --force    allow commands unless explicitly denied (`--yolo`
        //                  is an alias)
        switch approvalPolicy {
        case .safeAuto:
            args.append("--auto-review")
        case .fullBypass:
            args.append("--force")
        }

        return args
    }

    public func modelFlagValue(for humanName: String) -> String? {
        humanName.lowercased().trimmingCharacters(in: .whitespaces)
    }

    public func detectState(fromRecentOutput buffer: String) -> AgentState {
        let window = OutputHeuristics.recentWindow(buffer).lowercased()
        return OutputHeuristics.resolve(window: window) { text in
            OutputHeuristics.endsWithPrompt(text)
        }
    }
}

public final class OpenCodeAdapter: AgentAdapter {
    public static let kind = AgentKind.opencode
    public static let executablePath = "opencode"

    public let interruptInput = TerminalInput.interrupt

    /// From `opencode --help`: `-c, --continue  continue the last session`.
    public let continueConversationArgs: [String]? = ["--continue"]

    public init() {}

    public func launchArgs(
        cwd: URL,
        model: ModelRef?,
        approvalPolicy: ApprovalPolicy
    ) -> [String] {
        var args: [String] = []

        if let model = model {
            args.append("-m")
            args.append(model.rawValue)
        }

        // From `opencode --help`: `--auto` auto-approves permissions that are
        // not explicitly denied. There is no separate "safe" flag — prompting
        // is the default — so safeAuto simply adds nothing.
        if approvalPolicy == .fullBypass {
            args.append("--auto")
        }

        return args
    }

    public func modelFlagValue(for humanName: String) -> String? {
        humanName.lowercased().trimmingCharacters(in: .whitespaces)
    }

    public func detectState(fromRecentOutput buffer: String) -> AgentState {
        let window = OutputHeuristics.recentWindow(buffer).lowercased()
        return OutputHeuristics.resolve(window: window) { text in
            OutputHeuristics.endsWithPrompt(text)
        }
    }
}
