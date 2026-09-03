import Foundation
import SwiftUI
import DaddyCore

enum OrchestratorWorkspace: String, Equatable {
    case fleet
    case orchestrator
    case board
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

    /// Short enough for a group header in a 244pt column.
    var boardTitle: String {
        switch self {
        case .bugs: return "BUGS"
        case .uiux: return "UI/UX"
        case .futureFeatures: return "FEATURES"
        case .concepts: return "CONCEPTS"
        case .other: return "OTHER"
        }
    }

    /// Five hues you can tell apart at a glance, which is the whole job.
    ///
    /// Deliberately not drawn from the agent-state palette: `ready` green and
    /// `working` amber mean something specific about a running process, and
    /// reusing them for "this is a UI task" would make two unrelated things
    /// look related. These are desaturated to sit on dark glass without
    /// shouting over the card text.
    var tint: Color {
        switch self {
        case .bugs: return Color(hex: "#ff8f8f")
        case .uiux: return Color(hex: "#c9a7ff")
        case .futureFeatures: return Color(hex: "#7fe0c4")
        case .concepts: return Color(hex: "#ffcf7f")
        case .other: return Color(hex: "#9aa4b2")
        }
    }
}

enum OrchestratorWorkStatus: String, CaseIterable, Codable, Hashable {
    case inbox
    case refined
    case dispatched
    case inProgress = "in-progress"
    case blocked
    case rework
    case done
    case archived

    var title: String {
        switch self {
        case .inbox: return "BACKLOG"
        case .refined: return "VERIFY"
        case .dispatched: return "DISPATCHED"
        case .inProgress: return "IN PROGRESS"
        case .blocked: return "BLOCKED"
        case .rework: return "REWORK"
        case .done: return "DONE"
        case .archived: return "ARCHIVED"
        }
    }
}

extension OrchestratorWorkStatus {
    /// The columns the board actually shows.
    ///
    /// Capture → agent → did it work → send it back → done. There is no
    /// "refined" gate and no blocked graveyard: an agent is the thing doing
    /// the work, so dispatching *is* the start, and a card that cannot move
    /// still belongs in the pile, not in a column of its own. `rework` is the
    /// one exception — a card that passed verification but needs another
    /// crack is neither done nor back at the start, so it gets its own column.
    ///
    /// `inProgress` and `blocked` still exist on disk (tools and old files
    /// can set them). They are folded into a visible column by `boardColumn`
    /// rather than dropping the card. `archived` is a column only when the
    /// board is asked to show it.
    static let boardColumns: [OrchestratorWorkStatus] = [
        .inbox, .dispatched, .refined, .rework, .done
    ]

    /// Statuses the inspector will let you pick. Hidden cases stay decodable
    /// so old files do not vanish; they just sit in the column they fold into.
    static let editableStatuses: [OrchestratorWorkStatus] = boardColumns + [.archived]

    /// Which visible column this status belongs in.
    var boardColumn: OrchestratorWorkStatus {
        switch self {
        case .inProgress: return .dispatched
        case .blocked: return .inbox
        default: return self
        }
    }

    var boardTint: Color {
        switch self {
        case .inbox, .blocked: return DaddyTheme.idle
        case .refined: return DaddyTheme.accent
        case .rework: return DaddyTheme.failure
        case .dispatched, .inProgress: return DaddyTheme.working
        case .done: return DaddyTheme.ready
        case .archived: return DaddyTheme.textVeryDim
        }
    }
}

enum OrchestratorPriority: String, CaseIterable, Codable, Hashable {
    case low
    case medium
    case high
    case urgent

    var title: String { rawValue.uppercased() }

    var tint: Color {
        switch self {
        case .urgent: return DaddyTheme.failure
        case .high: return DaddyTheme.working
        case .medium: return DaddyTheme.textPrimary
        case .low: return DaddyTheme.textMuted
        }
    }
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

/// One category's run of cards inside one column. Collapse state is keyed by
/// the pair, so folding BUGS away in DONE does not also fold it in INBOX.
struct BoardGroupKey: Hashable {
    let status: OrchestratorWorkStatus
    let category: OrchestratorWorkCategory
}

/// Which project's cards the board is showing.
///
/// Not an optional project id, because "no project selected" and "items that
/// belong to no project" are different questions and the board has to be able
/// to ask both.
enum BoardProjectScope: Hashable {
    case all
    case unassigned
    case project(String)
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
