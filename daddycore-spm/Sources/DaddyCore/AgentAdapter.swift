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

        // `approvalPolicy` is deliberately not translated here. Claude and Codex
        // have flags whose names are already established in this file; this CLI
        // does not, and inventing one makes the launch fail outright rather than
        // just ignore the setting. Wire it up once the real flag is confirmed.
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

        // See CursorAdapter: no confirmed approval flag, so none is invented.
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
