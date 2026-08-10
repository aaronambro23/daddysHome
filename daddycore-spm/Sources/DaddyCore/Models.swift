import Foundation

enum AgentKind: String, Codable {
    case claude
    case codex
    case cursor
    case opencode
}

enum AgentState: Equatable {
    case launching
    case ready
    case working
    case rateLimited
    case error(String)
    case exited(exitCode: Int32)
}

struct ModelRef: Codable {
    let agent: AgentKind
    let rawValue: String
}

struct Project: Identifiable, Codable {
    let id: String
    let name: String
    let path: URL
}

struct WorkUnit: Identifiable, Codable {
    enum Status: String, Codable {
        case active
        case idle
        case done
    }

    let id: String
    let projectID: String
    let name: String
    var status: Status
    let markdownDir: URL
    let createdAt: Date
    var lastActivityAt: Date
}

final class Session: Identifiable {
    let id: String
    let projectID: String
    let workUnitID: String
    let agent: AgentKind
    var model: ModelRef?
    let cwd: URL
    var state: AgentState
    let createdAt: Date
    var lastOutputAt: Date

    init(
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

struct Focus {
    var projectID: String?
    var workUnitID: String?
    var sessionID: String?

    var isEmpty: Bool {
        projectID == nil && workUnitID == nil && sessionID == nil
    }
}
