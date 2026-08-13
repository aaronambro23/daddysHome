import SwiftUI
import DaddyCore

// MARK: - Tabs

enum DaddyTab: String, CaseIterable, Identifiable {
    case fleet
    case workUnits
    case voice
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fleet: return "Fleet"
        case .workUnits: return "Work Units"
        case .voice: return "Voice"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .fleet: return "square.grid.2x2"
        case .workUnits: return "list.bullet.rectangle"
        case .voice: return "waveform"
        case .settings: return "slider.horizontal.3"
        }
    }
}

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
    // Navigation
    var tab: DaddyTab = .fleet
    var selectedProjectID: String?
    var selectedAgentID: String?

    // Data
    var projects: [MockProject] = []
    var agents: [MockAgent] = []
    var voiceLog: [VoiceEntry] = []

    /// Work units marked done by hand. The units themselves are derived from
    /// live sessions, so only this override needs storing.
    var doneWorkUnits: Set<String> = []

    /// Agent kinds with a binary on this machine. Filled in shortly after
    /// launch by `refreshInstalledAgents()`; empty until then, so the launch
    /// menu shows everything as unavailable for a moment rather than blocking.
    var installedAgents: Set<AgentKind> = []


    // Voice
    var isListening: Bool = false
    var voiceLevel: Double = 0.2

    /// What was dictated, before it is sent. Shown rather than run blind, so a
    /// misheard command can be corrected instead of reaching an agent.
    var voiceText: String = ""

    // Settings
    var defaultModel: String = "opus-5"
    var approvalPolicy: ApprovalPolicy = .safeAuto
    var notifyOnReady: Bool = true
    var notifyOnRateLimit: Bool = true
    var notifyOnError: Bool = true
    var launchAtLogin: Bool = false

    private var tickCount: Int = 0

    /// Owns every real pty. Seeded demo agents do not touch this.
    @ObservationIgnored let sessionManager = SessionManager()

    /// Turns a spoken sentence into an intent. Existed and was unit-tested long
    /// before anything called it.
    @ObservationIgnored let commandParser = CommandParser()

    /// Surfaced in the UI when a launch fails (missing binary, bad cwd).
    var launchError: String?

    init() {
        seed()
        selectedProjectID = projects.first?.id
        selectedAgentID = agents.first?.id
        refreshInstalledAgents()
    }

    // MARK: - Derived

    var visibleAgents: [MockAgent] {
        guard let pid = selectedProjectID else { return agents }
        return agents.filter { $0.projectID == pid }
    }

    var selectedAgent: MockAgent? {
        agents.first { $0.id == selectedAgentID }
    }

    var selectedProject: MockProject? {
        projects.first { $0.id == selectedProjectID }
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

    func select(project id: String) {
        selectedProjectID = (selectedProjectID == id) ? nil : id
        if let current = selectedAgent, let pid = selectedProjectID, current.projectID != pid {
            selectedAgentID = visibleAgents.first?.id
        }
    }

    func select(agent id: String) {
        guard selectedAgentID != id else { return }
        selectedAgentID = id
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
            try sessionManager.launchSession(session, approvalPolicy: approvalPolicy)

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
        for agent in agents where agent.isRealSession {
            if let id = agent.sessionID {
                try? sessionManager.terminateSession(id)
            }
        }
    }

    // MARK: - Actions

    func interrupt(_ agentID: String) {
        guard let id = agents.first(where: { $0.id == agentID })?.sessionID else { return }
        try? sessionManager.interruptSession(id)
        mutate(agentID) { $0.lastOutputAt = Date() }
    }

    func stop(_ agentID: String) {
        guard let id = agents.first(where: { $0.id == agentID })?.sessionID else { return }
        try? sessionManager.terminateSession(id)
        if let live = sessionManager.session(id) {
            mutate(agentID) { agent in
                agent.state = live.state
                agent.lastOutputAt = Date()
            }
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

        if let sessionID = agent.sessionID {
            sessionManager.forgetSession(sessionID)
        }
        agents.removeAll { $0.id == agentID }

        if selectedAgentID == agentID {
            selectedAgentID = visibleAgents.first?.id ?? agents.first?.id
        }
    }

    /// Clear every finished agent at once.
    func dismissAllExited() {
        for agent in agents where !agent.isLive {
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

    func toggleListening() {
        isListening.toggle()
        if isListening {
            voiceLog.insert(
                VoiceEntry(at: Date(), transcript: "listening…",
                           resolution: "HEX armed", didSucceed: true),
                at: 0
            )
        }
    }

    /// The one entry point for spoken input. Dictated text lands in the voice
    /// composer (HEX pastes into whatever has focus, and Daddy only listens
    /// while it is frontmost), and this routes it to a real agent.
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
        voiceText = ""
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

        if isListening {
            voiceLevel = 0.25 + 0.6 * abs(sin(Double(tickCount) * 0.9))
        } else {
            voiceLevel = 0.18
        }

        // Every card is a real session now, so state comes from the process and
        // nothing invents it. The dashboard sits still when nothing is happening,
        // which is correct: it used to shuffle states on a timer so it would look
        // busy while you watched.
        for agent in agents {
            guard let sessionID = agent.sessionID else { continue }

            if let live = sessionManager.session(sessionID) {
                mutate(agent.id) { $0.state = live.state }
            }

            // The pty vanishing means the process died on its own.
            if let pty = sessionManager.getPTYProcess(for: sessionID), !pty.isProcessRunning {
                mutate(agent.id) { $0.state = .exited(exitCode: pty.exitCode ?? 0) }
            }
        }

        // Rescan for projects occasionally — a repo cloned while Daddy is open
        // should show up without a restart.
        if tickCount % 30 == 0 { refreshProjects() }
    }

    // MARK: - Buffer plumbing

    private func mutate(_ agentID: String, _ body: (inout MockAgent) -> Void) {
        guard let idx = agents.firstIndex(where: { $0.id == agentID }) else { return }
        body(&agents[idx])
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
                continuation.resume(returning: ProjectScanner.scan().map {
                    MockProject(id: $0.id, name: $0.name, path: $0.path)
                })
            }
        }
    }
}
