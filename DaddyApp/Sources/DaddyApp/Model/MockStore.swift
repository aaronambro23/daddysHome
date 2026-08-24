import SwiftUI
import DaddyCore

// MARK: - Store
//
// Everything on screen is driven from here. The data is seeded rather than
// live, but every control mutates real state and `tick()` advances the world
// on its own, so the UI behaves like the finished product.
//
// Swapping in live data later is a single-site change: replace `seed()` and
// `tick()` with reads from `SessionManager`.

@Observable
@MainActor
final class MockStore {
    // Workspace
    var workspace: OrchestratorWorkspace = .fleet

    // Navigation
    var selectedProjectID: String?
    var selectedAgentID: String?

    /// The agent being looked at in the drilled-in detail view, if any.
    ///
    /// Deliberately on the store rather than local to `AgentDashboard`: the old
    /// expansion state was view-local, which let it drift out of step with
    /// `selectedAgentID` and left the view with no reachable way back to the
    /// grid. Selection and drill-in are now separate, and both live here.
    var detailAgentID: String?

    /// Agent IDs in the order they were last focused, most recent first. Drives
    /// "put me back where I was" when you return to a project.
    private var detailHistory: [String] = []

    // Data
    var projects: [MockProject] = []
    var agents: [MockAgent] = []
    var voiceLog: [VoiceEntry] = []
    var providerUsage: [AgentKind: ProviderUsageSnapshot] = [:]

    // Orchestrator
    var orchestratorMessages: [OrchestratorMessage] = []
    var orchestratorAttachments: [OrchestratorAttachment] = []
    var pendingOrchestratorAttachmentIDs: [UUID] = []
    var orchestratorCategory: OrchestratorWorkCategory?
    @ObservationIgnored var orchestratorMessagesByCategory: [String: [OrchestratorMessage]] = [:]
    @ObservationIgnored var orchestratorAttachmentsByCategory: [String: [OrchestratorAttachment]] = [:]
    @ObservationIgnored var pendingOrchestratorAttachmentIDsByCategory: [String: [UUID]] = [:]
    var orchestratorWorkItems: [OrchestratorWorkItem] = []
    var selectedOrchestratorWorkItemID: UUID?
    var orchestratorStreamingText = ""
    var orchestratorBusy = false
    var orchestratorError: String?
    var pendingOrchestratorDispatch: PendingOrchestratorDispatch?

    @ObservationIgnored var orchestratorTurnTask: Task<Void, Never>?
    @ObservationIgnored var orchestratorTurnID: UUID?

    /// Work units marked done by hand. The units themselves are derived from
    /// live sessions, so only this override needs storing.
    var doneWorkUnits: Set<String> = []

    /// Conversations already on disk, per project id, newest first.
    ///
    /// Includes the ones started in a plain terminal — they are the same files
    /// Claude writes either way, and there is no reason for Daddy to pretend it
    /// cannot see them. Filled in by `refreshPastChats`, never read from disk
    /// on the main thread.
    var pastChats: [String: [PastChat]] = [:]

    @ObservationIgnored private var pastChatsReadAt: [String: Date] = [:]

    /// How stale the list is allowed to get. Long, because it only changes when
    /// a conversation ends.
    private static let pastChatsInterval: TimeInterval = 20

    /// Agent kinds with a binary on this machine. Filled in shortly after
    /// launch by `refreshInstalledAgents()`; empty until then, so the launch
    /// menu shows everything as unavailable for a moment rather than blocking.
    var installedAgents: Set<AgentKind> = []


    // Settings
    //
    // Every one of these reaches something. `defaultModel`, `launchAtLogin`,
    // `notifyOnRateLimit` and `notifyOnError` used to sit here too, wired to
    // controls in the settings drawer and to nothing else — a picker that
    // moved and changed no behavior is worse than no picker.

    /// Handed to `SessionManager` at launch; decides the CLI's approval flags.
    var approvalPolicy: ApprovalPolicy = .safeAuto {
        didSet { Defaults.set(approvalPolicy.rawValue, for: .approvalPolicy) }
    }

    /// The mode new sessions start in. A single card can be switched away from
    /// it afterwards without disturbing this — see `setWorkMode`.
    var workMode: WorkMode = .detailed {
        didSet { Defaults.set(workMode.rawValue, for: .workMode) }
    }

    /// The local model used by the Orchestrator workspace.
    var orchestratorModel: String = "gemma4:e4b" {
        didSet { Defaults.set(orchestratorModel, for: .orchestratorModel) }
    }

    /// Posts a notification when a background session wants input.
    var notifyOnReady: Bool = true

    /// Point size for both terminals. A change is a real font reset and a
    /// TIOCSWINSZ at the far end, so surfaces apply it only when it moves.
    var terminalFontSize: Double = 11.5 {
        didSet { Defaults.set(terminalFontSize, for: .terminalFontSize) }
    }

    static let terminalFontRange: ClosedRange<Double> = 9...20

    func nudgeTerminalFont(by delta: Double) {
        let next = terminalFontSize + delta
        terminalFontSize = min(
            Self.terminalFontRange.upperBound,
            max(Self.terminalFontRange.lowerBound, next)
        )
    }

    private var tickCount: Int = 0

    /// Owns every real pty. Seeded demo agents do not touch this.
    @ObservationIgnored let sessionManager = SessionManager()

    /// Remembers which agents you had when you quit, so they are still there
    /// when you come back — each one able to reopen its actual conversation
    /// rather than starting blank.
    @ObservationIgnored let sessionStore = SessionStore()

    /// Fetches provider quota windows and keeps the last successful snapshots.
    @ObservationIgnored private let providerUsageService = ProviderUsageService()

    /// Your own shells. Not agents — see `ShellSessions`. The ptys live in
    /// there; which ones a project has, in what order, and which is on screen
    /// live in `shellTabs`/`activeShellTabID` below, because this property is
    /// `@ObservationIgnored` and a change inside the registry would never
    /// redraw the tab strip.
    @ObservationIgnored let shellSessions = ShellSessions()

    /// The shells each project has open, in tab order.
    var shellTabs: [String: [ShellTab]] = [:]

    /// Which of them is on screen, per project.
    var activeShellTabID: [String: String] = [:]

    /// Turns a spoken sentence into an intent. Existed and was unit-tested long
    /// before anything called it.
    @ObservationIgnored let commandParser = CommandParser()

    @ObservationIgnored let orchestratorMarkdownStore = OrchestratorMarkdownStore()
    @ObservationIgnored let ollamaClient = OllamaClient()

    /// Reads HEX's own recording history, so voice commands do not depend on
    /// whichever SwiftUI control or embedded terminal currently owns focus.
    @ObservationIgnored private var hexWatcher: HEXWatcher?

    /// Surfaced in the UI when a launch fails (missing binary, bad cwd).
    var launchError: String?

    init() {
        // Before anything that could write them back: these assignments fire
        // the `didSet` observers above, and reading has to come first or a
        // fresh launch would save its own defaults over the stored ones.
        loadDefaults()

        seed()
        orchestratorWorkItems = orchestratorMarkdownStore.loadWorkItems()
        restoreSessions()
        selectedProjectID = projects.first?.id
        selectedAgentID = agents.first?.id
        refreshInstalledAgents()
        refreshProviderUsage()

        hexWatcher = HEXWatcher()
        hexWatcher?.start { [weak self] transcript in
            self?.submitVoice(transcript)
        }
    }

    // MARK: - Derived

    var visibleAgents: [MockAgent] {
        guard let pid = selectedProjectID else { return agents }
        return agents.filter { $0.projectID == pid }
    }

    var selectedAgent: MockAgent? {
        agents.first { $0.id == selectedAgentID }
    }

    /// Resolved rather than stored, so a dismissed or vanished agent drops the
    /// detail view instead of leaving it pointing at nothing.
    var detailAgent: MockAgent? {
        guard let id = detailAgentID else { return nil }
        return agents.first { $0.id == id }
    }

    var selectedProject: MockProject? {
        projects.first { $0.id == selectedProjectID }
    }

    var rootProjects: [MockProject] {
        projects.filter { $0.parentID == nil }
    }

    func childProjects(for projectID: String) -> [MockProject] {
        projects.filter { $0.parentID == projectID }
    }

    var liveAgentCount: Int {
        agents.filter(\.isLive).count
    }

    func agentCount(for projectID: String) -> Int {
        agents.filter { $0.projectID == projectID && $0.isLive }.count
    }

    /// Work units are derived from sessions, not stored. There is no persistence
    /// on this branch, so the only honest source is what is actually running —
    /// an empty list means nothing has been launched, not that data is missing.
    /// (`simple` is the branch that owns the written record; see BRANCHES.md.)
    func workUnits(for projectID: String?) -> [MockWorkUnit] {
        let relevant = projectID.map { pid in agents.filter { $0.projectID == pid } } ?? agents

        return Dictionary(grouping: relevant, by: \.workUnitID)
            .map { unitID, cards -> MockWorkUnit in
                let newest = cards.max(by: { $0.lastOutputAt < $1.lastOutputAt })
                let names = cards.map(\.displayName).sorted().joined(separator: " · ")

                return MockWorkUnit(
                    id: unitID,
                    projectID: newest?.projectID ?? "",
                    name: unitID,
                    status: doneWorkUnits.contains(unitID) ? .done
                        : (cards.contains(where: \.isLive) ? .active : .idle),
                    summary: "\(names) · \(project(newest?.projectID ?? "")?.name ?? "")",
                    lastActivityAt: newest?.lastOutputAt ?? Date()
                )
            }
            .sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    func project(_ id: String) -> MockProject? {
        projects.first { $0.id == id }
    }

    // MARK: - Selection

    /// Switching project takes the terminal with you.
    ///
    /// It used to change `selectedProjectID` and nothing else. `detailAgentID`
    /// kept pointing at an agent in the *old* project, so the toolbar went on
    /// describing a session you had navigated away from, while `TerminalPane`
    /// — which reads `selectedAgentID`, just cleared — dropped to "Select an
    /// agent to view its output". A full window of nothing, with no way back to
    /// the fleet except the chevron, and no docked terminal either, because you
    /// had never actually left focus mode.
    ///
    /// So the detail view follows the project: to its best agent if it has one,
    /// out to the fleet if it does not.
    func select(project id: String) {
        guard selectedProjectID != id else { return }
        selectedProjectID = id

        let target = bestAgent(in: id)
        selectedAgentID = target?.id

        // Only when already focused. Picking a project from the fleet should
        // stay on the fleet.
        guard detailAgentID != nil else { return }

        if let target {
            openDetail(target.id)
        } else {
            closeDetail()
        }
    }

    /// The agent to land on when you arrive at a project, in the order a person
    /// would expect: the one you were last looking at, then whatever is most
    /// recently running, then nothing — which means the fleet.
    private func bestAgent(in projectID: String) -> MockAgent? {
        let live = agents.filter { $0.projectID == projectID && $0.isLive }
        guard !live.isEmpty else { return nil }

        if let remembered = detailHistory.lazy
            .compactMap({ id in live.first { $0.id == id } })
            .first {
            return remembered
        }

        return live.max { $0.lastOutputAt < $1.lastOutputAt }
    }

    /// Point the docked terminal at a session without leaving the fleet.
    ///
    /// A card click used to call `openDetail` directly, so glancing at another
    /// agent's output cost you the whole grid and a trip back. Selecting is now
    /// the cheap half of that gesture and `openDetail` is the deliberate one:
    /// double click, ⌘→, or the tile menu. Finished agents are selectable —
    /// their output is still worth reading — but only live ones can be opened.
    func select(agent id: String) {
        guard agents.contains(where: { $0.id == id }) else { return }
        selectedAgentID = id
    }

    /// Enter the focus workspace for a session. Deliberate by design; see
    /// `select(agent:)` for the one-click half.
    func openDetail(_ id: String) {
        guard agents.contains(where: { $0.id == id && $0.isLive }) else { return }

        selectedAgentID = id
        detailAgentID = id

        // The rail lists live agents across every project, so opening one can
        // mean crossing into a different project. Bring the selection with it,
        // or the tree, the FOCUS footer and the switcher all keep describing
        // the project you just left.
        if let projectID = agents.first(where: { $0.id == id })?.projectID {
            selectedProjectID = projectID
        }

        // Most recently opened first. This is what "the one I had open" means
        // when you come back to a project — `lastOutputAt` answers a different
        // question, since the agent you were reading may well be the quietest.
        detailHistory.removeAll { $0 == id }
        detailHistory.insert(id, at: 0)
    }

    /// Switch the terminal to another live session without restacking focus
    /// chrome. `openDetail` is what moves the identity slot; this is the hop
    /// during a Ctrl+Tab burst.
    func previewDetail(_ id: String) {
        guard agents.contains(where: { $0.id == id && $0.isLive }) else { return }
        selectedAgentID = id
    }

    func closeDetail() {
        detailAgentID = nil
    }

    /// An exited session should not keep owning a terminal pane. The workspace
    /// returns to the fleet and docked output follows another live agent in the
    /// same visible scope, if one exists. The caller separately decides whether
    /// the finished card remains available for resume or is discarded.
    private func repairSelectionAfterExit(_ agentID: String) {
        if detailAgentID == agentID {
            closeDetail()
        }

        guard selectedAgentID == agentID else { return }
        selectedAgentID = liveSelectionFallback(excluding: agentID)?.id
    }

    private func liveSelectionFallback(excluding agentID: String) -> MockAgent? {
        let scopedLive = visibleAgents.filter { $0.id != agentID && $0.isLive }
        if let newestInScope = scopedLive.max(by: { $0.lastOutputAt < $1.lastOutputAt }) {
            return newestInScope
        }

        guard selectedProjectID == nil else { return nil }
        return agents
            .filter { $0.id != agentID && $0.isLive }
            .max(by: { $0.lastOutputAt < $1.lastOutputAt })
    }

    // MARK: - Actions

    // MARK: - Real sessions

    /// Which agent kinds have a binary on this machine.
    ///
    /// Computed once, off the main thread — never from inside a view body. The
    /// launch menu used to ask `ExecutableResolver` directly while rendering,
    /// and resolving a bare name can spawn a login shell to read its PATH.
    /// Running a process during layout crashed the app every time the menu was
    /// opened. Nothing here touches the disk.
    func isInstalled(_ kind: AgentKind) -> Bool {
        installedAgents.contains(kind)
    }

    /// Probes the PATH away from the main thread and publishes the result.
    private func refreshInstalledAgents() {
        Task { installedAgents = await Self.probeInstalledAgents() }
    }

    /// Static and off-main on purpose: resolving a bare name can spawn a login
    /// shell, and that must never happen on the thread SwiftUI draws on.
    private static func probeInstalledAgents() async -> Set<AgentKind> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var found: Set<AgentKind> = []
                for kind in [AgentKind.claude, .codex, .cursor, .opencode]
                where ExecutableResolver.resolve(executableName(for: kind)) != nil {
                    found.insert(kind)
                }
                continuation.resume(returning: found)
            }
        }
    }

    func refreshProviderUsage() {
        Task {
            providerUsage = await providerUsageService.refresh()
        }
    }

    /// `nonisolated` because the PATH probe runs off the main actor.
    nonisolated static func executableName(for kind: AgentKind) -> String {
        switch kind {
        case .claude: return "claude"
        case .codex: return "codex"
        case .cursor: return "agent"
        case .opencode: return "opencode"
        }
    }

    /// Spawns a real CLI in a real pty and adds a card backed by it.
    @discardableResult
    func launchReal(
        _ kind: AgentKind,
        in project: MockProject,
        workUnitID: String? = nil
    ) -> MockAgent? {
        launchError = nil

        let cwd = URL(fileURLWithPath: (project.path as NSString).expandingTildeInPath)
        let unit = workUnitID ?? newWorkUnitID()

        do {
            let session = try sessionManager.createSession(
                projectID: project.id,
                workUnitID: unit,
                agent: kind,
                cwd: cwd
            )
            try sessionManager.launchSession(
                session,
                approvalPolicy: approvalPolicy,
                workMode: workMode
            )

            let card = MockAgent(
                id: session.id,
                projectID: project.id,
                agent: kind,
                workUnitID: unit,
                model: Self.defaultModel(for: kind),
                state: .launching,
                startedAt: Date(),
                lastOutputAt: Date(),
                sessionID: session.id
            )
            agents.append(card)
            selectedProjectID = project.id
            selectedAgentID = card.id
            // Launching from inside the detail view moves the detail view with
            // you, rather than leaving it parked on the previous agent while
            // the selection quietly moves underneath it.
            if detailAgentID != nil { detailAgentID = card.id }
            persistSessions()
            return card
        } catch {
            launchError = "\(kind.rawValue): \(error.localizedDescription)"
            return nil
        }
    }

    /// Was `"live-\(epoch % 10_000)"`, which repeats every 2.7 hours — two
    /// sessions started either side of that boundary shared a work unit.
    private var workUnitCounter = 0
    func newWorkUnitID() -> String {
        workUnitCounter += 1

        let stamp = DateFormatter()
        stamp.dateFormat = "MMdd-HHmm"
        return "live-\(stamp.string(from: Date()))-\(workUnitCounter)"
    }

    /// The live pty behind an agent card, if it has one.
    func pty(for agent: MockAgent) -> PTYProcess? {
        guard let sessionID = agent.sessionID else { return nil }
        return sessionManager.getPTYProcess(for: sessionID)
    }

    /// Terminate every real session. Called on app teardown so agents and
    /// their descendants do not outlive the window.
    func shutdownAllRealSessions() {
        // Before the killing starts: once these are terminated the cards are
        // exited, and exited cards are not what we want to come back to.
        persistSessions()

        for agent in agents where agent.isRealSession {
            if let id = agent.sessionID {
                try? sessionManager.terminateSession(id)
            }
        }
        // A shell running a dev server owns a tree of node processes and a
        // bound port. Leaving those behind would leak a server on every quit.
        shellSessions.shutdownAll()
    }

    // MARK: - Shells

    /// The shells a project has open, in tab order. Safe from a view body.
    func shellTabs(for projectID: String) -> [ShellTab] {
        self.shellTabs[projectID] ?? []
    }

    /// The tab on screen for a project. Safe from a view body.
    func activeShellTab(for projectID: String) -> ShellTab? {
        let tabs = shellTabs(for: projectID)
        guard let id = activeShellTabID[projectID] else { return tabs.first }
        return tabs.first { $0.id == id } ?? tabs.first
    }

    /// The pty behind a tab, if it has been started. Safe from a view body —
    /// it never launches anything.
    func shell(for tab: ShellTab) -> PTYProcess? {
        shellSessions.existing(id: tab.id)
    }

    /// Gives a project its first shell if it has none.
    ///
    /// Call this from `onAppear`/`onChange`, never from a `body`: it spawns a
    /// process, and spawning during layout is what crashed the launch menu.
    func ensureShell(for project: MockProject) {
        guard shellTabs(for: project.id).isEmpty else { return }
        openShellTab(for: project)
    }

    /// Another shell in the same project, and focus moves to it. Spawns —
    /// same rule as `ensureShell`.
    @discardableResult
    func openShellTab(for project: MockProject) -> ShellTab? {
        let cwd = URL(fileURLWithPath: (project.path as NSString).expandingTildeInPath)

        // Numbered from the highest so far rather than from the count, so
        // closing the middle tab never produces two shells with the same name.
        let existing = shellTabs(for: project.id)
        let ordinal = (existing.map(\.ordinal).max() ?? 0) + 1
        let tab = ShellTab(id: UUID().uuidString, projectID: project.id, ordinal: ordinal)

        do {
            try shellSessions.shell(id: tab.id, cwd: cwd)
        } catch {
            launchError = "shell: \(error.localizedDescription)"
            return nil
        }

        self.shellTabs[project.id] = existing + [tab]
        activeShellTabID[project.id] = tab.id
        return tab
    }

    func selectShellTab(_ tab: ShellTab) {
        activeShellTabID[tab.projectID] = tab.id
    }

    /// Closes a shell and everything it was running.
    ///
    /// The pane is never left empty: closing the last tab immediately opens a
    /// fresh shell, which is what closing the last tab does everywhere else and
    /// is better than a dead panel with no way back.
    func closeShellTab(_ tab: ShellTab) {
        var tabs = shellTabs(for: tab.projectID)
        guard let index = tabs.firstIndex(of: tab) else { return }

        shellSessions.close(id: tab.id)
        tabs.remove(at: index)
        self.shellTabs[tab.projectID] = tabs

        guard activeShellTabID[tab.projectID] == tab.id else { return }

        if tabs.isEmpty {
            activeShellTabID[tab.projectID] = nil
            if let project = project(tab.projectID) { openShellTab(for: project) }
        } else {
            // The neighbour on the left, or the new last one — never a jump to
            // the far end of the strip.
            activeShellTabID[tab.projectID] = tabs[min(index, tabs.count - 1)].id
        }
    }

    // MARK: - Actions

    func interrupt(_ agentID: String) {
        guard let id = agents.first(where: { $0.id == agentID })?.sessionID else { return }
        try? sessionManager.interruptSession(id)
        mutate(agentID) { $0.lastOutputAt = Date() }
    }

    /// Stop the agent and clear it away.
    ///
    /// Stopping used to leave the dead card sitting there so you could read how
    /// the agent ended — but "Session ended" across the full width of the
    /// window is not a reading experience, it is a dead end you can still click
    /// into, get switched back to, and see in the focus switcher. Stopping is a
    /// deliberate act; the agent goes.
    ///
    /// The cost, knowingly: a stopped agent can no longer be resumed, because
    /// its session record goes with it. Agents that exit on their own still
    /// leave a card behind, and those are the ones "Resume chat" is for.
    func stop(_ agentID: String) {
        guard let agent = agents.first(where: { $0.id == agentID }),
              let sessionID = agent.sessionID else { return }

        try? sessionManager.terminateSession(sessionID)

        // Move the detail view somewhere real first, while the card still
        // exists to be moved away from.
        leaveDetailIfShowing(agentID)
        discard(agentID, sessionID: sessionID)
    }

    /// Stopping the agent you are focused on leaves a workspace with nothing in
    /// it. Move somewhere with something in it instead: the next live agent if
    /// there is one, the fleet otherwise.
    private func leaveDetailIfShowing(_ agentID: String) {
        guard detailAgentID == agentID else { return }

        // Same scope the focus switcher offers first, then anywhere — being
        // thrown to another project's agent beats being thrown to nothing.
        let successor = visibleAgents.first { $0.id != agentID && $0.isLive }
            ?? agents.first { $0.id != agentID && $0.isLive }

        if let successor {
            openDetail(successor.id)
        } else {
            closeDetail()
        }
    }

    /// Nudge a stopped agent to keep going, without throwing away what it has
    /// already worked out. The counterpart to `interrupt`.
    func resume(_ agentID: String) {
        guard let id = agents.first(where: { $0.id == agentID })?.sessionID else { return }
        do {
            try sessionManager.resumeSession(id)
            mutate(agentID) { $0.lastOutputAt = Date() }
        } catch {
            launchError = "resume: \(error.localizedDescription)"
        }
    }

    /// Whether this agent's CLI can pick up its previous conversation.
    func canResumeChat(_ kind: AgentKind) -> Bool {
        sessionManager.canContinueConversation(kind)
    }

    /// Start the process again.
    ///
    /// `continuingConversation` is the difference between "run this CLI again"
    /// and "carry on where we left off" — the CLI reopens its own last session
    /// rather than a blank one. Not every agent can do it; see `canResumeChat`.
    func relaunch(_ agentID: String, continuingConversation: Bool = false) {
        guard let id = agents.first(where: { $0.id == agentID })?.sessionID else { return }

        mutate(agentID) { agent in
            agent.state = .launching
            agent.startedAt = Date()
            agent.lastOutputAt = Date()
        }

        do {
            try sessionManager.restartSession(
                id,
                approvalPolicy: approvalPolicy,
                continuingConversation: continuingConversation
            )
            // A fresh start mints a new conversation id, so what was recorded a
            // moment ago now points at the wrong one.
            persistSessions()
            refreshPastChats(for: agents.first { $0.id == agentID }?.projectID ?? "", force: true)
        } catch {
            launchError = "relaunch: \(error.localizedDescription)"
            mutate(agentID) { $0.state = .error(error.localizedDescription) }
        }
    }

    /// The text goes into the pty; the agent's own output comes back through the
    /// terminal renderer. There is nothing to fake on the way.
    func send(_ text: String, to agentID: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let id = agents.first(where: { $0.id == agentID })?.sessionID else { return }

        try? sessionManager.sendPrompt(trimmed, to: id)
        mutate(agentID) { $0.lastOutputAt = Date() }
    }

    /// Remove a finished agent from the dashboard.
    ///
    /// Without this a dead card stays forever: `stop` leaves it visible on
    /// purpose, so you can see how the agent ended, but nothing cleared it
    /// afterwards.
    func dismiss(_ agentID: String) {
        guard let agent = agents.first(where: { $0.id == agentID }) else { return }
        discard(agentID, sessionID: agent.sessionID)
    }

    /// Take the card off the screen now; reap the session behind it later.
    ///
    /// `forgetSession` shuts the pty down *synchronously*, polling for up to
    /// two seconds for the process group to die. This type is `@MainActor`, so
    /// doing that inline is a frozen window — survivable when dismissing an
    /// agent that died a while ago, not when stopping one that is still
    /// exiting. The card is gone from the UI either way.
    private func discard(_ agentID: String, sessionID: String?) {
        agents.removeAll { $0.id == agentID }
        detailHistory.removeAll { $0 == agentID }
        persistSessions()

        if selectedAgentID == agentID {
            selectedAgentID = visibleAgents.first?.id ?? agents.first?.id
        }
        if detailAgentID == agentID {
            detailAgentID = nil
        }

        guard let sessionID else { return }
        let manager = sessionManager
        Task.detached(priority: .utility) {
            manager.forgetSession(sessionID)
        }
    }

    /// Stop every live agent of one kind in the current scope. The tile menu's
    /// one bulk action — killing four runaway Claudes one menu at a time is the
    /// thing the old UI made tedious.
    func stopAll(_ kind: AgentKind) {
        for agent in visibleAgents where agent.agent == kind && agent.isLive {
            stop(agent.id)
        }
    }

    /// Debug escape hatch: terminate and remove every live agent in the
    /// selected project, regardless of provider.
    ///
    /// IDs are snapshotted before `stop` mutates `agents`. No selected project
    /// means no action; the all-projects scope must never become a global kill
    /// switch by accident.
    func dismissAllActiveAgentsInSelectedProject() {
        guard let projectID = selectedProjectID else { return }
        let agentIDs = agents
            .filter { $0.projectID == projectID && $0.isLive }
            .map(\.id)

        for agentID in agentIDs {
            stop(agentID)
        }
    }

    /// Clear every finished agent at once.
    func dismissAllExited() {
        for agent in agents where !agent.isLive {
            dismiss(agent.id)
        }
    }

    /// Clear finished cards for one provider in the selected project. A nil
    /// project means the dashboard is in its explicit all-projects scope.
    func dismissAllExited(_ kind: AgentKind, in projectID: String?) {
        for agent in agents
        where !agent.isLive
            && agent.agent == kind
            && (projectID == nil || agent.projectID == projectID) {
            dismiss(agent.id)
        }
    }

    /// Start a different agent on the same work, in the same project.
    ///
    /// This used to append a card with no process behind it, so a handoff
    /// produced something that looked like an agent and could not be talked to.
    func handOff(_ agentID: String, to kind: AgentKind) {
        guard let source = agents.first(where: { $0.id == agentID }),
              let project = project(source.projectID) else { return }

        launchReal(kind, in: project, workUnitID: source.workUnitID)
    }

    func markDone(_ workUnitID: String) {
        if doneWorkUnits.contains(workUnitID) {
            doneWorkUnits.remove(workUnitID)
        } else {
            doneWorkUnits.insert(workUnitID)
        }
    }

    /// The one entry point for spoken input. `HEXWatcher` supplies recordings
    /// targeted at Daddy, and this routes them to a real agent.
    @MainActor
    func submitVoice(_ transcript: String) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let outcome = VoiceRouter(store: self).route(trimmed)

        voiceLog.insert(
            VoiceEntry(at: Date(), transcript: trimmed,
                       resolution: outcome.summary, didSucceed: outcome.didSucceed),
            at: 0
        )
    }

    /// Switch the model on a live session. Returns false if the agent has no
    /// model by that name, so the caller can say so rather than fail silently.
    func switchModel(_ humanName: String, on agentID: String) -> Bool {
        guard let agent = agents.first(where: { $0.id == agentID }) else { return false }

        guard let sessionID = agent.sessionID else {
            mutate(agentID) { $0.model = humanName }
            return true
        }

        do {
            try sessionManager.selectModel(humanName, for: sessionID)
            mutate(agentID) { $0.model = humanName }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Tick
    //
    // Called once a second from the root view's `.task` loop.

    func tick() {
        tickCount += 1

        if let projectID = selectedProjectID {
            refreshPastChats(for: projectID)
        }

        // Every card is a real session now, so state comes from the process and
        // nothing invents it. The dashboard sits still when nothing is happening,
        // which is correct: it used to shuffle states on a timer so it would look
        // busy while you watched.
        for agent in agents {
            guard let sessionID = agent.sessionID else { continue }

            // `launchSession` marks a session `.ready` the moment `forkpty`
            // returns, which is before the CLI has printed a single byte — so
            // a card announced READY while its agent was still booting and
            // could not be typed at. An agent that has said nothing is still
            // launching, whatever the session says.
            let hasSpoken = !(sessionManager.getPTYProcess(for: sessionID)?
                .recentOutput.isEmpty ?? true)

            if let live = sessionManager.session(sessionID) {
                let oldState = agent.state
                let newState: AgentState
                if case .ready = live.state, !hasSpoken {
                    newState = .launching
                } else {
                    newState = live.state
                }

                mutate(agent.id) {
                    $0.state = newState
                    $0.lastOutputAt = live.lastOutputAt
                }

                let becameReady: Bool
                if case .ready = newState, case .ready = oldState {
                    becameReady = false
                } else if case .ready = newState {
                    becameReady = true
                } else {
                    becameReady = false
                }

                if becameReady, notifyOnReady, !NSApplication.shared.isActive {
                    updateDockBadge()
                    NSApplication.shared.requestUserAttention(.criticalRequest)
                }
            }

            if let pty = sessionManager.getPTYProcess(for: sessionID) {
                // Only the tail is cleaned. `recentOutput` runs to 64KB and
                // `stripANSI` walks every character of what it is given, and
                // this loop runs for every agent every second.
                let tail = String(pty.recentOutput.suffix(4096))
                let line = OutputHeuristics.lastVisibleLine(
                    OutputHeuristics.recentWindow(tail, lines: 3)
                )
                if line != agent.lastLine {
                    mutate(agent.id) { $0.lastLine = line }
                }

                // The pty vanishing means the process died on its own. If
                // Ctrl-C immediately preceded that exit, it was the user's
                // deliberate CLI-exit gesture: repair navigation and remove
                // the card as one lifecycle event. A Ctrl-C that only cancelled
                // work leaves the process running and never reaches this path.
                if !pty.isProcessRunning {
                    if pty.exitedAfterInterrupt {
                        repairSelectionAfterExit(agent.id)
                        discard(agent.id, sessionID: sessionID)
                        continue
                    }

                    mutate(agent.id) { $0.state = .exited(exitCode: pty.exitCode ?? 0) }
                    repairSelectionAfterExit(agent.id)
                }
            }
        }

        // Rescan for projects occasionally — a repo cloned while Daddy is open
        // should show up without a restart.
        if tickCount % 30 == 0 { refreshProjects() }

        // Provider quota endpoints are account-wide and some are aggressively
        // rate-limited. Five minutes keeps the dashboard useful without turning
        // four fleet cards into a polling storm.
        if tickCount % 300 == 0 { refreshProviderUsage() }
    }

    // MARK: - Buffer plumbing

    private func mutate(_ agentID: String, _ body: (inout MockAgent) -> Void) {
        guard let idx = agents.firstIndex(where: { $0.id == agentID }) else { return }
        body(&agents[idx])
    }

    /// Updates the Dock icon badge to show the count of ready agents.
    private func updateDockBadge() {
        let readyCount = agents.filter { if case .ready = $0.state { return true } else { return false } }.count
        NSApplication.shared.dockTile.badgeLabel = readyCount > 0 ? "\(readyCount)" : ""
    }

}

// MARK: - Seed Data

extension MockStore {
    static func defaultModel(for kind: AgentKind) -> String {
        switch kind {
        case .claude: return "opus-5"
        case .codex: return "gpt-5-codex"
        case .cursor: return "composer-1"
        case .opencode: return "sonnet-5"
        }
    }

    /// Reads the world as it actually is. There is no seeded data left: an
    /// empty dashboard means no agents are running, which is the truth.
    func seed() {
        refreshProjects()
    }

    /// Rescans the disk for projects, off the main thread.
    ///
    /// Walking `~/Documents` two levels deep is not free, and it runs on a timer
    /// — doing it on the main thread would stutter the UI at best. Same rule as
    /// `refreshInstalledAgents`: no filesystem work where SwiftUI is drawing.
    func refreshProjects() {
        Task {
            let found = await Self.scanProjects()
            guard found != projects else { return }

            projects = found
            if selectedProjectID == nil { selectedProjectID = found.first?.id }
        }
    }

    private static func scanProjects() async -> [MockProject] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let projects = ProjectScanner.scan().flatMap { root in
                    [
                        MockProject(
                            id: root.id,
                            name: root.name,
                            path: root.path,
                            parentID: nil
                        )
                    ] + root.children.map {
                        MockProject(
                            id: $0.id,
                            name: $0.name,
                            path: $0.path,
                            parentID: root.id
                        )
                    }
                }
                continuation.resume(returning: projects)
            }
        }
    }

    // MARK: - Settings that persist

    private func loadDefaults() {
        if let raw = Defaults.string(.approvalPolicy),
           let policy = ApprovalPolicy(rawValue: raw) {
            approvalPolicy = policy
        }
        if let raw = Defaults.string(.workMode), let mode = WorkMode(rawValue: raw) {
            workMode = mode
        }
        if let model = Defaults.string(.orchestratorModel), !model.isEmpty {
            orchestratorModel = model
        }
        if let size = Defaults.double(.terminalFontSize),
           Self.terminalFontRange.contains(size) {
            terminalFontSize = size
        }
    }

    // MARK: - Work mode

    /// The mode a specific card is running under, which is not necessarily the
    /// global default — that is the whole point of being able to switch one.
    func workMode(of agent: MockAgent) -> WorkMode {
        guard let sessionID = agent.sessionID,
              let session = sessionManager.session(sessionID) else { return workMode }
        return session.workMode
    }

    /// Switch one running session without touching the default.
    ///
    /// A live process cannot have its system prompt rewritten, so this arrives
    /// as a message in the conversation. That is visible in the transcript,
    /// which is the honest way for it to happen — the agent's behaviour is
    /// changing and the change is on the record.
    func setWorkMode(_ mode: WorkMode, for agentID: String) {
        guard let sessionID = agents.first(where: { $0.id == agentID })?.sessionID else { return }
        do {
            try sessionManager.switchWorkMode(mode, for: sessionID)
            mutate(agentID) { $0.lastOutputAt = Date() }
        } catch {
            launchError = "mode: \(error.localizedDescription)"
        }
    }

    // MARK: - Surviving a quit

    /// Puts back the agents you had when you last quit, as dead cards that can
    /// be reopened.
    ///
    /// They come back exited on purpose. The processes died with the app, and a
    /// card claiming READY over a pty that does not exist is worse than an
    /// honest dead one — it can be typed into, and the keystrokes go nowhere.
    func restoreSessions() {
        let records = sessionStore.load()
        guard !records.isEmpty else { return }

        for record in records {
            sessionManager.restoreSession(
                id: record.id,
                projectID: record.projectID,
                workUnitID: record.workUnitID,
                agent: record.agent,
                model: ModelRef(agent: record.agent, rawValue: record.model),
                cwd: URL(fileURLWithPath: record.cwd),
                providerSessionID: record.providerSessionID
            )

            agents.append(
                MockAgent(
                    id: record.id,
                    projectID: record.projectID,
                    agent: record.agent,
                    workUnitID: record.workUnitID,
                    model: record.model,
                    state: .exited(exitCode: 0),
                    startedAt: record.startedAt,
                    lastOutputAt: record.lastOutputAt,
                    sessionID: record.id
                )
            )
        }
    }

    /// Records every card currently on the dashboard.
    ///
    /// Not just the live ones. A card whose agent exited on its own stays on
    /// screen precisely so you can reopen it, and that has to survive a quit
    /// too — otherwise restored cards would evaporate on the *next* launch.
    /// Cards you stopped or dismissed are already gone from `agents` by the
    /// time this runs, which is what keeps "stop" meaning stop.
    func persistSessions() {
        let records: [SessionRecord] = agents.compactMap { agent in
            guard let sessionID = agent.sessionID else { return nil }
            guard let session = sessionManager.session(sessionID) else { return nil }

            return SessionRecord(
                id: agent.id,
                projectID: agent.projectID,
                workUnitID: agent.workUnitID,
                agent: agent.agent,
                model: agent.model,
                cwd: session.cwd.path,
                providerSessionID: session.providerSessionID,
                startedAt: agent.startedAt,
                lastOutputAt: agent.lastOutputAt
            )
        }

        sessionStore.save(records)
    }

    // MARK: - Past chats

    /// Refills `pastChats` for a project, off the main thread.
    ///
    /// Reading them is real disk work — every transcript directory gets probed
    /// — so it can never happen while a menu is being built. Throttled as well
    /// as backgrounded, because `tick()` calls this once a second and the set
    /// of past conversations does not change that often.
    func refreshPastChats(for projectID: String, force: Bool = false) {
        guard let project = project(projectID) else { return }

        if !force, let last = pastChatsReadAt[projectID],
           Date().timeIntervalSince(last) < Self.pastChatsInterval {
            return
        }
        pastChatsReadAt[projectID] = Date()

        let path = (project.path as NSString).expandingTildeInPath
        Task.detached(priority: .utility) {
            let found = ChatHistory.claudeChats(inDirectory: path)
            await MainActor.run { self.pastChats[projectID] = found }
        }
    }

    /// Open one of them as a new card.
    @discardableResult
    func openPastChat(_ chat: PastChat, in project: MockProject) -> MockAgent? {
        launchError = nil

        let cwd = URL(fileURLWithPath: (project.path as NSString).expandingTildeInPath)
        let unit = newWorkUnitID()

        do {
            let session = try sessionManager.createSession(
                projectID: project.id,
                workUnitID: unit,
                agent: chat.agent,
                cwd: cwd,
                providerSessionID: chat.id
            )

            // `continuingConversation` with a known provider id resolves to
            // "reopen exactly this one", not "reopen the newest".
            try sessionManager.launchSession(
                session,
                approvalPolicy: approvalPolicy,
                continuingConversation: true,
                workMode: workMode
            )

            let card = MockAgent(
                id: session.id,
                projectID: project.id,
                agent: chat.agent,
                workUnitID: unit,
                model: Self.defaultModel(for: chat.agent),
                state: .launching,
                startedAt: Date(),
                lastOutputAt: Date(),
                sessionID: session.id
            )
            agents.append(card)
            selectedProjectID = project.id
            selectedAgentID = card.id
            if detailAgentID != nil { detailAgentID = card.id }
            persistSessions()
            return card
        } catch {
            launchError = "\(chat.agent.rawValue): \(error.localizedDescription)"
            return nil
        }
    }
}
