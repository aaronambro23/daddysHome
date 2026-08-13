import Foundation

public enum ApprovalPolicy: String {
    case safeAuto = "safe-auto"
    case fullBypass = "full-bypass"
}

public protocol AgentAdapter: AnyObject {
    static var kind: AgentKind { get }
    static var executablePath: String { get }

    func launchArgs(
        cwd: URL,
        model: ModelRef?,
        approvalPolicy: ApprovalPolicy
    ) -> [String]

    func modelFlagValue(for humanName: String) -> String?

    func sendPrompt(_ text: String, to pty: PTYProcess) throws

    func selectModel(_ model: ModelRef, on pty: PTYProcess) throws

    func interrupt(_ pty: PTYProcess) throws

    func detectState(fromRecentOutput buffer: String) -> AgentState
}

public final class ClaudeAdapter: AgentAdapter {
    public static let kind = AgentKind.claude
    public static let executablePath = "claude"

    public init() {}

    public func launchArgs(
        cwd: URL,
        model: ModelRef?,
        approvalPolicy: ApprovalPolicy
    ) -> [String] {
        var args = ["--permission-mode", "acceptEdits"]

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

    public func sendPrompt(_ text: String, to pty: PTYProcess) throws {
        try pty.write(text + "\n")
    }

    public func selectModel(_ model: ModelRef, on pty: PTYProcess) throws {
        try pty.write("/model " + model.rawValue + "\r")
        Thread.sleep(forTimeInterval: 0.5)
    }

    public func interrupt(_ pty: PTYProcess) throws {
        try pty.write("\u{1b}")
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

        args.append("--ask-for-approval")
        args.append("on-request")
        args.append("--sandbox")
        args.append("workspace-write")

        return args
    }

    public func modelFlagValue(for humanName: String) -> String? {
        let normalized = humanName.lowercased().trimmingCharacters(in: .whitespaces)
        return normalized
    }

    public func sendPrompt(_ text: String, to pty: PTYProcess) throws {
        try pty.write(text + "\n")
    }

    public func selectModel(_ model: ModelRef, on pty: PTYProcess) throws {
        try pty.write("/model " + model.rawValue + "\r")
        Thread.sleep(forTimeInterval: 0.5)
    }

    public func interrupt(_ pty: PTYProcess) throws {
        try pty.write("\u{03}")
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

        return args
    }

    public func modelFlagValue(for humanName: String) -> String? {
        let normalized = humanName.lowercased().trimmingCharacters(in: .whitespaces)
        return normalized
    }

    public func sendPrompt(_ text: String, to pty: PTYProcess) throws {
        try pty.write(text + "\n")
    }

    public func selectModel(_ model: ModelRef, on pty: PTYProcess) throws {
        try pty.write("/model " + model.rawValue + "\r")
        Thread.sleep(forTimeInterval: 0.5)
    }

    public func interrupt(_ pty: PTYProcess) throws {
        try pty.write("\u{1b}")
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

        return args
    }

    public func modelFlagValue(for humanName: String) -> String? {
        let normalized = humanName.lowercased().trimmingCharacters(in: .whitespaces)
        return normalized
    }

    public func sendPrompt(_ text: String, to pty: PTYProcess) throws {
        try pty.write(text + "\n")
    }

    public func selectModel(_ model: ModelRef, on pty: PTYProcess) throws {
        try pty.write("/model " + model.rawValue + "\r")
        Thread.sleep(forTimeInterval: 0.5)
    }

    public func interrupt(_ pty: PTYProcess) throws {
        try pty.write("\u{03}")
    }

    public func detectState(fromRecentOutput buffer: String) -> AgentState {
        let window = OutputHeuristics.recentWindow(buffer).lowercased()
        return OutputHeuristics.resolve(window: window) { text in
            OutputHeuristics.endsWithPrompt(text)
        }
    }
}
