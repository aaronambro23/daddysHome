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

    /// Reads HEX's own recording history, so voice commands do not depend on
    /// whichever SwiftUI control or embedded terminal currently owns focus.
    @ObservationIgnored private var hexWatcher: HEXWatcher?

    /// Surfaced in the UI when a launch fails (missing binary, bad cwd).
    var launchError: String?

    init() {
        seed()
        selectedProjectID = projects.first?.id
        selectedAgentID = agents.first?.id
        refreshInstalledAgents()

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

    func select(project id: String) {
        guard selectedProjectID != id else { return }
        selectedProjectID = id
        if let current = selectedAgent, let pid = selectedProjectID, current.projectID != pid {
            selectedAgentID = visibleAgents.first?.id
        }
    }

    /// Agent cards are navigation, not a two-stage preview. One click selects
    /// the session and enters its terminal focus workspace.
    func openDetail(_ id: String) {
        selectedAgentID = id
        detailAgentID = id
    }

    func closeDetail() {
        detailAgentID = nil
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
            // Launching from inside the detail view moves the detail view with
            // you, rather than leaving it parked on the previous agent while
            // the selection quietly moves underneath it.
            if detailAgentID != nil { detailAgentID = card.id }
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
        if detailAgentID == agentID {
            detailAgentID = nil
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
                mutate(agent.id) {
                    if case .ready = live.state, !hasSpoken {
                        $0.state = .launching
                    } else {
                        $0.state = live.state
                    }
                    // Without this the card's timestamp measured "time since you
                    // last clicked something", not "time since the agent spoke".
                    $0.lastOutputAt = live.lastOutputAt
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

                // The pty vanishing means the process died on its own.
                if !pty.isProcessRunning {
                    mutate(agent.id) { $0.state = .exited(exitCode: pty.exitCode ?? 0) }
                }
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

    // MARK: - Agent State File Reading

    /// Reads live agent state from {project}/.daddy/agents/{agent-id}.json
    /// Returns (model, workUnitID) or (nil, nil) if file doesn't exist or is invalid.
    func readAgentStateFromFile(agentID: String, projectPath: String) -> (model: String?, workUnitID: String?) {
        let daddyDir = URL(fileURLWithPath: projectPath).appendingPathComponent(".daddy")
        let agentsDir = daddyDir.appendingPathComponent("agents")
        let stateFile = agentsDir.appendingPathComponent("\(agentID).json")

        guard FileManager.default.fileExists(atPath: stateFile.path) else {
            return (nil, nil)
        }

        do {
            let data = try Data(contentsOf: stateFile)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let model = json?["model"] as? String
            let workUnitID = json?["workUnitID"] as? String
            return (model, workUnitID)
        } catch {
            return (nil, nil)
        }
    }
}
