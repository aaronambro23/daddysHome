import Foundation
import DaddyCore

enum OrchestratorWorkspace: String, Equatable {
    case fleet
    case orchestrator
}

enum OrchestratorMessageRole: String, Codable, Equatable {
    case user
    case assistant
    case tool
    case system
}

struct OrchestratorMessage: Identifiable, Codable {
    let id: UUID
    let role: OrchestratorMessageRole
    var content: String
    let createdAt: Date
    var attachmentIDs: [UUID]
    var wasStopped: Bool

    init(
        role: OrchestratorMessageRole,
        content: String,
        attachmentIDs: [UUID] = [],
        createdAt: Date = Date(),
        id: UUID = UUID(),
        wasStopped: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.attachmentIDs = attachmentIDs
        self.wasStopped = wasStopped
    }
}

enum OrchestratorAttachmentKind: String, Codable, Hashable {
    case text
    case image
    case pdf
}

struct OrchestratorAttachment: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let path: String
    let kind: OrchestratorAttachmentKind
    let extractedText: String

    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        kind: OrchestratorAttachmentKind,
        extractedText: String = ""
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.kind = kind
        self.extractedText = extractedText
    }
}

enum OrchestratorWorkCategory: String, CaseIterable, Codable, Identifiable, Hashable {
    case bugs
    case uiux
    case futureFeatures = "future-features"
    case concepts
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bugs: return "BUGS"
        case .uiux: return "UI/UX"
        case .futureFeatures: return "FUTURE FEATURES"
        case .concepts: return "CONCEPTS"
        case .other: return "OTHER"
        }
    }

    var folderName: String { rawValue }
}

enum OrchestratorWorkStatus: String, CaseIterable, Codable, Hashable {
    case inbox
    case refined
    case dispatched
    case inProgress = "in-progress"
    case blocked
    case done
    case archived

    var title: String {
        switch self {
        case .inbox: return "INBOX"
        case .refined: return "REFINED"
        case .dispatched: return "DISPATCHED"
        case .inProgress: return "IN PROGRESS"
        case .blocked: return "BLOCKED"
        case .done: return "DONE"
        case .archived: return "ARCHIVED"
        }
    }
}

enum OrchestratorPriority: String, CaseIterable, Codable, Hashable {
    case low
    case medium
    case high
    case urgent
}

struct OrchestratorWorkItem: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var summary: String
    var rawCapture: String
    var category: OrchestratorWorkCategory
    var status: OrchestratorWorkStatus
    var priority: OrchestratorPriority
    var projectID: String?
    var attachmentIDs: [UUID]
    var linkedSessionIDs: [String]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        rawCapture: String,
        category: OrchestratorWorkCategory,
        status: OrchestratorWorkStatus = .inbox,
        priority: OrchestratorPriority = .medium,
        projectID: String? = nil,
        attachmentIDs: [UUID] = [],
        linkedSessionIDs: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.rawCapture = rawCapture
        self.category = category
        self.status = status
        self.priority = priority
        self.projectID = projectID
        self.attachmentIDs = attachmentIDs
        self.linkedSessionIDs = linkedSessionIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct PendingOrchestratorDispatch: Identifiable {
    let id = UUID()
    let workItemID: UUID
    let agent: AgentKind
    let projectID: String
    let existingSessionID: String?
    let prompt: String
}

struct OrchestratorConversationSnapshot: Codable {
    var key: String
    var category: OrchestratorWorkCategory?
    var messages: [OrchestratorMessage]
    var attachments: [OrchestratorAttachment]
    var pendingAttachmentIDs: [UUID]
    var createdAt: Date
    var updatedAt: Date
    var keepLongTerm: Bool

    var expiresAt: Date? {
        guard !keepLongTerm else { return nil }
        return Calendar.current.date(byAdding: .day, value: 30, to: createdAt)
    }

    var hasContent: Bool {
        !messages.isEmpty || !attachments.isEmpty || !pendingAttachmentIDs.isEmpty
    }
}
