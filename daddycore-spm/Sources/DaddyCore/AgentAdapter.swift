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

    func launchArgs(
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

    func modelFlagValue(for humanName: String) -> String? {
        let normalized = humanName.lowercased().trimmingCharacters(in: .whitespaces)

        let aliases: [String: String] = [
            "opus": "opus",
            "sonnet": "sonnet",
            "haiku": "haiku",
            "fable": "fable",
        ]

        return aliases[normalized]
    }

    func sendPrompt(_ text: String, to pty: PTYProcess) throws {
        try pty.write(text + "\n")
    }

    func selectModel(_ model: ModelRef, on pty: PTYProcess) throws {
        try pty.write("/model " + model.rawValue + "\r")
        Thread.sleep(forTimeInterval: 0.5)
    }

    func interrupt(_ pty: PTYProcess) throws {
        try pty.write("\u{1b}")
    }

    func detectState(fromRecentOutput buffer: String) -> AgentState {
        let lower = buffer.lowercased()

        if lower.contains("rate limited") || lower.contains("rate-limited") {
            return .rateLimited
        }

        if lower.contains("error") || lower.contains("exception") {
            return .error("Detected error in output")
        }

        if lower.contains(">>>") || lower.contains("claude >") {
            return .ready
        }

        if lower.contains("thinking") || lower.contains("processing") {
            return .working
        }

        return .ready
    }
}

public final class CodexAdapter: AgentAdapter {
    static let kind = AgentKind.codex
    static let executablePath = "codex"

    func launchArgs(
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

    func modelFlagValue(for humanName: String) -> String? {
        let normalized = humanName.lowercased().trimmingCharacters(in: .whitespaces)
        return normalized
    }

    func sendPrompt(_ text: String, to pty: PTYProcess) throws {
        try pty.write(text + "\n")
    }

    func selectModel(_ model: ModelRef, on pty: PTYProcess) throws {
        try pty.write("/model " + model.rawValue + "\r")
        Thread.sleep(forTimeInterval: 0.5)
    }

    func interrupt(_ pty: PTYProcess) throws {
        try pty.write("\u{03}")
    }

    func detectState(fromRecentOutput buffer: String) -> AgentState {
        let lower = buffer.lowercased()

        if lower.contains("rate limited") || lower.contains("rate-limited") {
            return .rateLimited
        }

        if lower.contains("error") {
            return .error("Detected error in output")
        }

        if lower.contains(">") || lower.contains("codex") {
            return .ready
        }

        return .ready
    }
}

public final class CursorAdapter: AgentAdapter {
    static let kind = AgentKind.cursor
    static let executablePath = "agent"

    func launchArgs(
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

    func modelFlagValue(for humanName: String) -> String? {
        let normalized = humanName.lowercased().trimmingCharacters(in: .whitespaces)
        return normalized
    }

    func sendPrompt(_ text: String, to pty: PTYProcess) throws {
        try pty.write(text + "\n")
    }

    func selectModel(_ model: ModelRef, on pty: PTYProcess) throws {
        try pty.write("/model " + model.rawValue + "\r")
        Thread.sleep(forTimeInterval: 0.5)
    }

    func interrupt(_ pty: PTYProcess) throws {
        try pty.write("\u{1b}")
    }

    func detectState(fromRecentOutput buffer: String) -> AgentState {
        let lower = buffer.lowercased()

        if lower.contains("rate limited") || lower.contains("rate-limited") {
            return .rateLimited
        }

        if lower.contains("error") {
            return .error("Detected error in output")
        }

        return .ready
    }
}

public final class OpenCodeAdapter: AgentAdapter {
    static let kind = AgentKind.opencode
    static let executablePath = "opencode"

    func launchArgs(
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

    func modelFlagValue(for humanName: String) -> String? {
        let normalized = humanName.lowercased().trimmingCharacters(in: .whitespaces)
        return normalized
    }

    func sendPrompt(_ text: String, to pty: PTYProcess) throws {
        try pty.write(text + "\n")
    }

    func selectModel(_ model: ModelRef, on pty: PTYProcess) throws {
        try pty.write("/model " + model.rawValue + "\r")
        Thread.sleep(forTimeInterval: 0.5)
    }

    func interrupt(_ pty: PTYProcess) throws {
        try pty.write("\u{03}")
    }

    func detectState(fromRecentOutput buffer: String) -> AgentState {
        let lower = buffer.lowercased()

        if lower.contains("rate limited") || lower.contains("rate-limited") {
            return .rateLimited
        }

        if lower.contains("error") {
            return .error("Detected error in output")
        }

        return .ready
    }
}
