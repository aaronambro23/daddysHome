import Foundation

public enum AgentKind: String, Codable, Sendable {
    case claude
    case codex
    case cursor
    case opencode
}

public enum AgentState: Equatable, Codable {
    case launching
    case ready
    case working
    case rateLimited
    case error(String)
    case exited(exitCode: Int32)

    enum CodingKeys: String, CodingKey {
        case launching, ready, working, rateLimited, error, exited
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .launching:
            try container.encodeNil(forKey: .launching)
        case .ready:
            try container.encodeNil(forKey: .ready)
        case .working:
            try container.encodeNil(forKey: .working)
        case .rateLimited:
            try container.encodeNil(forKey: .rateLimited)
        case .error(let msg):
            try container.encode(msg, forKey: .error)
        case .exited(let code):
            try container.encode(code, forKey: .exited)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.launching) {
            self = .launching
        } else if container.contains(.ready) {
            self = .ready
        } else if container.contains(.working) {
            self = .working
        } else if container.contains(.rateLimited) {
            self = .rateLimited
        } else if container.contains(.error) {
            let msg = try container.decode(String.self, forKey: .error)
            self = .error(msg)
        } else if container.contains(.exited) {
            let code = try container.decode(Int32.self, forKey: .exited)
            self = .exited(exitCode: code)
        } else {
            self = .launching
        }
    }
}

public struct ModelRef: Codable {
    public let agent: AgentKind
    public let rawValue: String

    public init(agent: AgentKind, rawValue: String) {
        self.agent = agent
        self.rawValue = rawValue
    }
}

public struct Project: Identifiable, Codable {
    public let id: String
    public let name: String
    public let path: URL
}

public struct WorkUnit: Identifiable, Codable {
    public enum Status: String, Codable {
        case active
        case idle
        case done
    }

    public let id: String
    public let projectID: String
    public let name: String
    public var status: Status
    public let markdownDir: URL
    public let createdAt: Date
    public var lastActivityAt: Date
}

public final class Session: Identifiable {
    public let id: String
    public let projectID: String
    public let workUnitID: String
    public let agent: AgentKind
    public var model: ModelRef?
    public let cwd: URL
    public var state: AgentState
    public let createdAt: Date
    public var lastOutputAt: Date

    public init(
        id: String = UUID().uuidString,
        projectID: String,
        workUnitID: String,
        agent: AgentKind,
        model: ModelRef? = nil,
        cwd: URL
    ) {
        self.id = id
        self.projectID = projectID
        self.workUnitID = workUnitID
        self.agent = agent
        self.model = model
        self.cwd = cwd
        self.state = .launching
        self.createdAt = Date()
        self.lastOutputAt = Date()
    }
}

public struct Focus {
    public var projectID: String?
    public var workUnitID: String?
    public var sessionID: String?

    public var isEmpty: Bool {
        projectID == nil && workUnitID == nil && sessionID == nil
    }
}
