import SwiftUI
import DaddyCore

// MARK: - Tabs

enum DaddyTab: String, CaseIterable, Identifiable {
    case overview
    case batches
    case voice
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .batches: return "Batches"
        case .voice: return "Voice"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .batches: return "list.bullet.rectangle"
        case .voice: return "waveform"
        case .settings: return "slider.horizontal.3"
        }
    }
}

// MARK: - Store
//
// Navigation, the real project list, and preferences. Nothing here is invented:
// projects come from disk, and everything about batches is read from the
// projects themselves by `HandoffViewModel`.
//
// This replaced `MockStore`, which carried fabricated agents, a scripted
// terminal transcript and a pty launch path. Work happens in the user's own
// terminal on this branch, so Daddy tracks and briefs rather than hosts.

@Observable
final class AppStore {
    // Navigation
    var tab: DaddyTab = .overview
    var selectedProjectID: String?

    // Data
    var projects: [Project] = []
    var voiceLog: [VoiceEntry] = []

    // Voice
    var composeText: String = ""
    var isListening: Bool = false

    // Preferences
    var defaultModel: String = "opus-5"
    var launchAtLogin: Bool = false

    /// Agent CLIs found on PATH, resolved once off the main thread.
    ///
    /// Resolving lazily from a view body is what crashed the app: it reaches
    /// `Process.waitUntilExit()`, which pumps the run loop, and doing that
    /// inside a menu's modal tracking loop re-enters AppKit layout and aborts.
    /// Views must only ever read this cached set.
    private(set) var installedAgents: Set<AgentKind> = []

    init() {
        loadProjects()
        seedVoiceLog()
        selectedProjectID = projects.first?.id
        resolveInstalledAgents()
    }

    // MARK: - Projects

    /// Real directories under `~/Documents`, via DaddyCore's discovery.
    private func loadProjects() {
        let manager = WorkflowStateManager()
        // discoverProjects only returns newly-seen directories, so union it
        // with everything already persisted.
        let discovered = manager.discoverProjects() + manager.getAllProjects()

        var seen = Set<String>()
        projects = discovered
            // getAllProjects returns everything ever discovered, including
            // directories since renamed or deleted, so drop the ghosts.
            .filter { FileManager.default.fileExists(atPath: $0.path.path) }
            .filter { seen.insert($0.id).inserted }
            .map {
                Project(
                    id: $0.id,
                    name: $0.name,
                    path: $0.path.path.replacingOccurrences(
                        of: FileManager.default.homeDirectoryForCurrentUser.path,
                        with: "~"
                    )
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func reloadProjects() {
        let previous = selectedProjectID
        loadProjects()
        selectedProjectID = projects.contains { $0.id == previous }
            ? previous
            : projects.first?.id
    }

    var selectedProject: Project? {
        projects.first { $0.id == selectedProjectID }
    }

    func project(_ id: String) -> Project? {
        projects.first { $0.id == id }
    }

    func select(project id: String) {
        selectedProjectID = id
    }

    /// Selects a project and jumps to its batches — the Overview click-through.
    func openBatches(for id: String) {
        selectedProjectID = id
        tab = .batches
    }

    // MARK: - Agent availability

    private func resolveInstalledAgents() {
        let kinds = AgentKind.allCases
        DispatchQueue.global(qos: .utility).async {
            // ExecutableResolver spawns a login shell to read PATH. Doing that
            // on the main thread is what aborted the app from the Launch menu.
            let found = Set(kinds.filter {
                ExecutableResolver.resolve($0.executableName) != nil
            })
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.installedAgents = found }
            }
        }
    }

    func isInstalled(_ kind: AgentKind) -> Bool {
        installedAgents.contains(kind)
    }

    // MARK: - Voice

    func toggleListening() {
        isListening.toggle()
    }

    private func seedVoiceLog() {
        // Placeholder until the HEX intake lands; the Voice tab is otherwise
        // an empty shell.
        voiceLog = []
    }
}

// MARK: - AgentKind helpers

extension AgentKind: @retroactive CaseIterable {
    public static var allCases: [AgentKind] { [.claude, .codex, .cursor, .opencode] }

    /// The binary name on PATH. Cursor's CLI is `agent`, not `cursor`.
    var executableName: String {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex"
        case .cursor: return "agent"
        case .opencode: return "opencode"
        }
    }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .opencode: return "opencode"
        }
    }
}
