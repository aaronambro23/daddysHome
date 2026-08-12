import Foundation
import DaddyCore

// MARK: - View Models
//
// DaddyCore's `Session` is a non-observable `final class`, so SwiftUI cannot
// see mutations on it. These are value types so the `@Observable` store can
// diff them properly. `AgentKind` and `AgentState` are reused straight from
// DaddyCore, so `StateColors` and the badge rendering stay shared with the
// real session path.

struct MockProject: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
}

struct MockAgent: Identifiable {
    let id: String
    let projectID: String
    let agent: AgentKind
    var workUnitID: String
    var model: String
    var state: AgentState
    var startedAt: Date
    var lastOutputAt: Date

    /// Non-nil when this card is backed by a real `SessionManager` session and
    /// a live pty. Nil means it is seeded demo data with a scripted transcript.
    var sessionID: String?

    /// True when a real process is behind this card, as opposed to seeded
    /// demo data. Distinct from `isRunning`, which is about agent state.
    var isRealSession: Bool { sessionID != nil }

    var displayName: String { agent.rawValue.uppercased() }

    var uptime: String {
        let elapsed = Int(Date().timeIntervalSince(startedAt))
        if elapsed < 60 { return "\(elapsed)s" }
        if elapsed < 3600 { return "\(elapsed / 60)m \(elapsed % 60)s" }
        return "\(elapsed / 3600)h \((elapsed % 3600) / 60)m"
    }

    var isLive: Bool {
        if case .exited = state { return false }
        return true
    }
}

struct MockWorkUnit: Identifiable {
    enum Status: String {
        case active = "ACTIVE"
        case idle = "IDLE"
        case done = "DONE"
    }

    let id: String
    let projectID: String
    var name: String
    var status: Status
    var summary: String
    var lastActivityAt: Date
}

struct TerminalLine: Identifiable {
    enum Kind {
        case command
        case output
        case dim
        case error
        case rule
    }

    let id = UUID()
    let agentID: String
    let kind: Kind
    let text: String
}

struct VoiceEntry: Identifiable {
    let id = UUID()
    let at: Date
    let transcript: String
    let resolution: String
    let didSucceed: Bool
}

// MARK: - Formatting

func formatTimeAgo(_ date: Date) -> String {
    let elapsed = Date().timeIntervalSince(date)
    if elapsed < 60 { return "now" }
    if elapsed < 3600 { return "\(Int(elapsed / 60))m" }
    return "\(Int(elapsed / 3600))h"
}
