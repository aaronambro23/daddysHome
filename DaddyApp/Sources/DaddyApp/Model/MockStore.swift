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
final class MockStore {
    // Navigation
    var tab: DaddyTab = .fleet
    var selectedProjectID: String?
    var selectedAgentID: String?

    // Data
    var projects: [MockProject] = []
    var agents: [MockAgent] = []
    var workUnits: [MockWorkUnit] = []
    var voiceLog: [VoiceEntry] = []
    var terminal: [TerminalLine] = []

    // Composer
    var composeText: String = ""

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
    private var streamCursor: [String: Int] = [:]

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
        rebuildTerminal()
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

    func workUnits(for projectID: String?) -> [MockWorkUnit] {
        guard let projectID else { return workUnits }
        return workUnits.filter { $0.projectID == projectID }
    }

    func project(_ id: String) -> MockProject? {
        projects.first { $0.id == id }
    }

    var terminalForSelection: [TerminalLine] {
        guard let id = selectedAgentID else { return [] }
        return terminal.filter { $0.agentID == id }
    }

    // MARK: - Selection

    func select(project id: String) {
        selectedProjectID = (selectedProjectID == id) ? nil : id
        if let current = selectedAgent, let pid = selectedProjectID, current.projectID != pid {
            selectedAgentID = visibleAgents.first?.id
            rebuildTerminal()
        }
    }

    func select(agent id: String) {
        guard selectedAgentID != id else { return }
        selectedAgentID = id
        rebuildTerminal()
    }

    // MARK: - Actions

    // MARK: - Real sessions

    /// Which agent kinds actually have a binary on this machine. Used to grey
    /// out launch options rather than let them fail silently.
    func isInstalled(_ kind: AgentKind) -> Bool {
        ExecutableResolver.resolve(Self.executableName(for: kind)) != nil
    }

    static func executableName(for kind: AgentKind) -> String {
        switch kind {
        case .claude: return "claude"
        case .codex: return "codex"
        case .cursor: return "agent"
        case .opencode: return "opencode"
        }
    }

    /// Spawns a real CLI in a real pty and adds a card backed by it.
    func launchReal(_ kind: AgentKind, in project: MockProject) {
        launchError = nil

        let cwd = URL(fileURLWithPath: (project.path as NSString).expandingTildeInPath)
        let workUnitID = "live-\(Int(Date().timeIntervalSince1970) % 10_000)"

        do {
            let session = try sessionManager.createSession(
                projectID: project.id,
                workUnitID: workUnitID,
                agent: kind,
                cwd: cwd
            )
            try sessionManager.launchSession(session, approvalPolicy: approvalPolicy)

            let card = MockAgent(
                id: session.id,
                projectID: project.id,
                agent: kind,
                workUnitID: workUnitID,
                model: Self.defaultModel(for: kind),
                state: .working,
                startedAt: Date(),
                lastOutputAt: Date(),
                sessionID: session.id
            )
            agents.append(card)
            selectedProjectID = project.id
            selectedAgentID = card.id
        } catch {
            launchError = "\(kind.rawValue): \(error.localizedDescription)"
        }
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
        if let agent = agents.first(where: { $0.id == agentID }), let id = agent.sessionID {
            try? sessionManager.interruptSession(id)
            mutate(agentID) { $0.lastOutputAt = Date() }
            return
        }

        mutate(agentID) { agent in
            agent.state = .ready
            agent.lastOutputAt = Date()
        }
        append(agentID, .error, "^C  interrupt sent — agent returned to prompt")
    }

    func stop(_ agentID: String) {
        if let agent = agents.first(where: { $0.id == agentID }), let id = agent.sessionID {
            try? sessionManager.terminateSession(id)
            mutate(agentID) { agent in
                agent.state = .exited(exitCode: 0)
                agent.lastOutputAt = Date()
            }
            return
        }

        mutate(agentID) { agent in
            agent.state = .exited(exitCode: 0)
            agent.lastOutputAt = Date()
        }
        append(agentID, .dim, "session terminated (exit 0)")
    }

    /// Nudge a stopped agent to keep going, without throwing away what it has
    /// already worked out. The counterpart to `interrupt`.
    func resume(_ agentID: String) {
        guard let agent = agents.first(where: { $0.id == agentID }) else { return }

        if let id = agent.sessionID {
            do {
                try sessionManager.resumeSession(id)
                mutate(agentID) { $0.lastOutputAt = Date() }
            } catch {
                launchError = "resume: \(error.localizedDescription)"
            }
            return
        }

        mutate(agentID) { agent in
            agent.state = .working
            agent.lastOutputAt = Date()
        }
        append(agentID, .command, "> continue")
    }

    func relaunch(_ agentID: String) {
        guard let agent = agents.first(where: { $0.id == agentID }) else { return }

        // A real card gets a real process. This used to fall through to the
        // mock path, so a dead live agent sat at "launching" forever: `tick()`
        // only promotes launching → working for demo agents.
        if let id = agent.sessionID {
            mutate(agentID) { agent in
                agent.state = .launching
                agent.startedAt = Date()
                agent.lastOutputAt = Date()
            }
            do {
                try sessionManager.restartSession(id, approvalPolicy: approvalPolicy)
                rebuildTerminal()
            } catch {
                launchError = "relaunch: \(error.localizedDescription)"
                mutate(agentID) { $0.state = .error(error.localizedDescription) }
            }
            return
        }

        mutate(agentID) { agent in
            agent.state = .launching
            agent.startedAt = Date()
            agent.lastOutputAt = Date()
        }
        append(agentID, .rule, "")
        append(agentID, .command,
               "$ \(agent.agent.rawValue) --permission-mode \(approvalPolicy.rawValue) --model \(agent.model)")
        append(agentID, .dim, "starting session…")
    }

    func send(_ text: String, to agentID: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Real session: the text goes into the pty, and the agent's own output
        // comes back through the terminal renderer. Nothing to fake.
        if let agent = agents.first(where: { $0.id == agentID }), let id = agent.sessionID {
            try? sessionManager.sendPrompt(trimmed, to: id)
            mutate(agentID) { $0.lastOutputAt = Date() }
            composeText = ""
            return
        }

        append(agentID, .command, "> \(trimmed)")
        mutate(agentID) { agent in
            agent.state = .working
            agent.lastOutputAt = Date()
        }
        composeText = ""
    }

    func handOff(_ agentID: String, to kind: AgentKind) {
        guard let source = agents.first(where: { $0.id == agentID }) else { return }
        let new = MockAgent(
            id: UUID().uuidString,
            projectID: source.projectID,
            agent: kind,
            workUnitID: source.workUnitID,
            model: Self.defaultModel(for: kind),
            state: .launching,
            startedAt: Date(),
            lastOutputAt: Date()
        )
        agents.append(new)
        selectedAgentID = new.id
        append(new.id, .command,
               "$ \(kind.rawValue) --permission-mode \(approvalPolicy.rawValue) --model \(new.model)")
        append(new.id, .dim, "handed off from \(source.displayName) · \(source.workUnitID)")
    }

    func markDone(_ workUnitID: String) {
        guard let idx = workUnits.firstIndex(where: { $0.id == workUnitID }) else { return }
        workUnits[idx].status = workUnits[idx].status == .done ? .active : .done
        workUnits[idx].lastActivityAt = Date()
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

        // Real sessions report their own state; never script over them.
        for agent in agents where agent.isRealSession {
            guard let sessionID = agent.sessionID else { continue }

            if let live = sessionManager.session(sessionID) {
                mutate(agent.id) { $0.state = live.state }
            }

            // The pty vanishing means the process died on its own.
            if let pty = sessionManager.getPTYProcess(for: sessionID), !pty.isProcessRunning {
                mutate(agent.id) { $0.state = .exited(exitCode: 0) }
            }
        }

        // Stream scripted output for demo agents only.
        for agent in agents where agent.state == .working && !agent.isRealSession {
            guard tickCount % 2 == 0 || agent.id == selectedAgentID else { continue }
            appendStreamLine(for: agent)
            mutate(agent.id) { $0.lastOutputAt = Date() }
        }

        // Launching demo agents come up after a beat.
        for agent in agents where agent.state == .launching && !agent.isRealSession {
            mutate(agent.id) { $0.state = .working }
            append(agent.id, .output, "> ready · picking up \(agent.workUnitID)")
        }

        // Every few seconds one live agent changes state, so the dashboard is
        // never static while you look at it.
        if tickCount % 7 == 0 { advanceOneState() }
    }

    private func advanceOneState() {
        let candidates = agents.filter(\.isLive)
        guard let target = candidates.randomElement() else { return }

        switch target.state {
        case .working:
            if Int.random(in: 0..<10) < 2 {
                mutate(target.id) { $0.state = .rateLimited }
                append(target.id, .error, "rate limit reached — backing off 4m")
            } else {
                mutate(target.id) { $0.state = .ready }
                append(target.id, .output, "✓ done — awaiting instruction")
            }
        case .ready:
            mutate(target.id) { $0.state = .working }
            append(target.id, .output, "> resuming \(target.workUnitID)…")
        case .rateLimited:
            mutate(target.id) { $0.state = .ready }
            append(target.id, .output, "limit cleared — ready")
        case .error:
            mutate(target.id) { $0.state = .ready }
        case .launching, .exited, .unknown:
            break
        }
        mutate(target.id) { $0.lastOutputAt = Date() }
    }

    private func appendStreamLine(for agent: MockAgent) {
        let script = Self.stream(for: agent.agent)
        let cursor = streamCursor[agent.id] ?? 0
        let line = script[cursor % script.count]
        streamCursor[agent.id] = cursor + 1
        append(agent.id, line.0, line.1)
    }

    // MARK: - Buffer plumbing

    private func mutate(_ agentID: String, _ body: (inout MockAgent) -> Void) {
        guard let idx = agents.firstIndex(where: { $0.id == agentID }) else { return }
        body(&agents[idx])
    }

    private func append(_ agentID: String, _ kind: TerminalLine.Kind, _ text: String) {
        terminal.append(TerminalLine(agentID: agentID, kind: kind, text: text))
        // Keep the buffer bounded — this runs forever.
        if terminal.count > 600 {
            terminal.removeFirst(terminal.count - 600)
        }
    }

    private func rebuildTerminal() {
        guard let agent = selectedAgent else { return }
        guard !terminal.contains(where: { $0.agentID == agent.id }) else { return }
        append(agent.id, .command,
               "$ \(agent.agent.rawValue) --permission-mode \(approvalPolicy.rawValue) --model \(agent.model)")
        append(agent.id, .rule, "")
        append(agent.id, .output, "> working on \(agent.workUnitID)…")
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

    static func stream(for kind: AgentKind) -> [(TerminalLine.Kind, String)] {
        switch kind {
        case .claude:
            return [
                (.dim, "· Reading Sources/DaddyCore/SessionManager.swift"),
                (.output, "  applying edit → SessionManager.swift:118"),
                (.dim, "· Running swift build"),
                (.output, "  Compiling DaddyCore (9 sources)"),
                (.dim, "· Build succeeded in 4.2s"),
                (.output, "  writing DaddyWork/auth-refactor/notes.md"),
            ]
        case .codex:
            return [
                (.dim, "· scanning workspace"),
                (.output, "  patch → tests/test_auth.py"),
                (.dim, "· pytest -q"),
                (.output, "  14 passed, 1 skipped"),
            ]
        case .cursor:
            return [
                (.dim, "· indexing repository"),
                (.output, "  composer: refactor HEXWatcher polling"),
                (.dim, "· awaiting approval for 3 file writes"),
            ]
        case .opencode:
            return [
                (.dim, "· reading prd.md"),
                (.output, "  drafting milestone-7 checklist"),
                (.dim, "· idle"),
            ]
        }
    }

    func seed() {
        let now = Date()

        projects = [
            MockProject(id: "daddysHome", name: "daddysHome", path: "~/Documents/daddy"),
            MockProject(id: "hex-bridge", name: "hex-bridge", path: "~/Documents/hex-bridge"),
            MockProject(id: "daddycore-spm", name: "daddycore-spm", path: "~/Documents/daddycore-spm"),
            MockProject(id: "notes-sync", name: "notes-sync", path: "~/Documents/notes-sync"),
            MockProject(id: "portfolio-site", name: "portfolio-site", path: "~/Documents/portfolio-site"),
            MockProject(id: "tax-2026", name: "tax-2026", path: "~/Documents/tax-2026"),
        ]

        agents = [
            MockAgent(id: "a1", projectID: "daddysHome", agent: .claude,
                      workUnitID: "auth-refactor", model: "opus-5",
                      state: .working,
                      startedAt: now.addingTimeInterval(-1_820),
                      lastOutputAt: now.addingTimeInterval(-4)),
            MockAgent(id: "a2", projectID: "daddysHome", agent: .codex,
                      workUnitID: "test-coverage", model: "gpt-5-codex",
                      state: .ready,
                      startedAt: now.addingTimeInterval(-940),
                      lastOutputAt: now.addingTimeInterval(-96)),
            MockAgent(id: "a3", projectID: "hex-bridge", agent: .cursor,
                      workUnitID: "hotkey-latency", model: "composer-1",
                      state: .rateLimited,
                      startedAt: now.addingTimeInterval(-5_400),
                      lastOutputAt: now.addingTimeInterval(-240)),
            MockAgent(id: "a4", projectID: "daddycore-spm", agent: .opencode,
                      workUnitID: "milestone-7", model: "sonnet-5",
                      state: .working,
                      startedAt: now.addingTimeInterval(-320),
                      lastOutputAt: now.addingTimeInterval(-2)),
            MockAgent(id: "a5", projectID: "notes-sync", agent: .claude,
                      workUnitID: "markdown-sync", model: "opus-5",
                      state: .error("adapter exited unexpectedly"),
                      startedAt: now.addingTimeInterval(-7_200),
                      lastOutputAt: now.addingTimeInterval(-1_500)),
        ]

        workUnits = [
            MockWorkUnit(id: "auth-refactor", projectID: "daddysHome", name: "Authentication refactor",
                         status: .active, summary: "Move token exchange into DaddyCore, drop keychain shim",
                         lastActivityAt: now.addingTimeInterval(-60)),
            MockWorkUnit(id: "test-coverage", projectID: "daddysHome", name: "Test coverage push",
                         status: .active, summary: "CommandParser Spanish cases, 9/14 → 14/14",
                         lastActivityAt: now.addingTimeInterval(-600)),
            MockWorkUnit(id: "liquid-glass", projectID: "daddysHome", name: "Liquid Glass reskin",
                         status: .active, summary: "Real glassEffect surfaces, aurora backdrop, live tabs",
                         lastActivityAt: now.addingTimeInterval(-20)),
            MockWorkUnit(id: "hotkey-latency", projectID: "hex-bridge", name: "Hotkey latency",
                         status: .idle, summary: "Double-tap ⌥ dispatch is ~180ms, target <60ms",
                         lastActivityAt: now.addingTimeInterval(-3_100)),
            MockWorkUnit(id: "milestone-7", projectID: "daddycore-spm", name: "Milestone 7 scoping",
                         status: .active, summary: "Rate-limit backoff policy + session recovery",
                         lastActivityAt: now.addingTimeInterval(-120)),
            MockWorkUnit(id: "markdown-sync", projectID: "notes-sync", name: "Markdown sync",
                         status: .idle, summary: "DaddyWork ↔ Obsidian vault two-way write",
                         lastActivityAt: now.addingTimeInterval(-9_000)),
            MockWorkUnit(id: "pty-hardening", projectID: "daddycore-spm", name: "PTY hardening",
                         status: .done, summary: "NSLock around session table, no more races",
                         lastActivityAt: now.addingTimeInterval(-86_400)),
            MockWorkUnit(id: "menu-bar", projectID: "daddysHome", name: "Menu bar background mode",
                         status: .done, summary: "NSStatusItem persists after window close",
                         lastActivityAt: now.addingTimeInterval(-172_800)),
        ]

        voiceLog = [
            VoiceEntry(at: now.addingTimeInterval(-45),
                       transcript: "daddy, what's claude doing",
                       resolution: "read state · claude · auth-refactor · working", didSucceed: true),
            VoiceEntry(at: now.addingTimeInterval(-300),
                       transcript: "start codex on test coverage",
                       resolution: "launch · codex · daddysHome/test-coverage", didSucceed: true),
            VoiceEntry(at: now.addingTimeInterval(-780),
                       transcript: "pásate a opus",
                       resolution: "set model · opus-5 · claude", didSucceed: true),
            VoiceEntry(at: now.addingTimeInterval(-1_500),
                       transcript: "mark the auth thing done",
                       resolution: "ambiguous work unit — asked to confirm", didSucceed: false),
        ]
    }
}
