import Foundation

/// `@unchecked Sendable` for the same reason `PTYProcess` is: every mutable
/// field below is guarded by `lock`, and this type has always been reached from
/// more than one queue — the pty's read callbacks have called into it since
/// launch callbacks existed. The deferred state-detection run made the compiler
/// say so out loud.
public final class SessionManager: @unchecked Sendable {
    private var sessions: [String: Session] = [:]
    private var ptyProcesses: [String: PTYProcess] = [:]
    private var adapters: [AgentKind: AgentAdapter] = [:]
    private var sessionErrors: [String: (error: String, count: Int, lastAt: Date)] = [:]
    private var retryAttempts: [String: Int] = [:]
    private var pendingModelSwitch: [String: ModelRef] = [:]
    private let markdownWriter = MarkdownWriter()
    private let lock = NSLock()
    private let maxRetries = 3
    private let errorThresholdCount = 5

    // MARK: State detection throttle
    //
    // Detection runs on the pty's own read queue, so whatever it costs is paid
    // *before the next chunk can be delivered to the renderer*. Paying it per
    // chunk meant an agent redrawing a status line several times a second was
    // stripping ANSI out of the entire retained buffer several times a second,
    // back-pressuring the read loop until the agent's own writes blocked.

    private var lastDetectionAt: [String: Date] = [:]
    /// Output that arrived inside the throttle window and is waiting for the
    /// trailing run. Exactly one trailing run is ever scheduled per session.
    private var pendingDetection: [String: String] = [:]
    private let detectionQueue = DispatchQueue(label: "com.daddy.session.detection")

    /// A state change is still noticed within a quarter second, which is far
    /// faster than the one-second cadence the dashboard reads at.
    private static let detectionInterval: TimeInterval = 0.25

    /// `OutputHeuristics.recentWindow` keeps 24 lines whatever it is handed, so
    /// handing it a 64KB buffer was stripping ~56KB of escape codes per chunk
    /// to throw the result away.
    private static let detectionWindowBytes = 8192

    public init() {
        self.adapters = [
            .claude: ClaudeAdapter(),
            .codex: CodexAdapter(),
            .cursor: CursorAdapter(),
            .opencode: OpenCodeAdapter(),
        ]
    }

    public func createSession(
        id: String = UUID().uuidString,
        projectID: String,
        workUnitID: String,
        agent: AgentKind,
        model: ModelRef? = nil,
        cwd: URL,
        providerSessionID: String? = nil
    ) throws -> Session {
        let session = Session(
            id: id,
            projectID: projectID,
            workUnitID: workUnitID,
            agent: agent,
            model: model,
            cwd: cwd,
            providerSessionID: providerSessionID
        )

        lock.lock()
        defer { lock.unlock() }
        sessions[session.id] = session
        return session
    }

    /// Puts back a session from a previous run of the app, with no process
    /// behind it.
    ///
    /// The card it belongs to is dead by definition — the pty died with the app
    /// that owned it — so the session is registered as exited. What it carries
    /// that a brand new session would not is `providerSessionID`, which is what
    /// lets "Resume chat" reopen the actual conversation rather than guessing.
    @discardableResult
    public func restoreSession(
        id: String,
        projectID: String,
        workUnitID: String,
        agent: AgentKind,
        model: ModelRef? = nil,
        cwd: URL,
        providerSessionID: String?
    ) -> Session {
        let session = Session(
            id: id,
            projectID: projectID,
            workUnitID: workUnitID,
            agent: agent,
            model: model,
            cwd: cwd,
            providerSessionID: providerSessionID
        )
        session.state = .exited(exitCode: 0)

        lock.lock()
        defer { lock.unlock() }
        sessions[session.id] = session
        return session
    }

    /// Whether this agent can pick up its previous conversation on relaunch.
    public func canContinueConversation(_ kind: AgentKind) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return adapters[kind]?.canReopenConversations ?? false
    }

    public func launchSession(
        _ session: Session,
        approvalPolicy: ApprovalPolicy = .safeAuto,
        continuingConversation: Bool = false,
        workMode: WorkMode = .detailed
    ) throws {
        guard let adapter = adapters[session.agent] else {
            throw SessionError.unknownAgent(session.agent)
        }

        let resumption = resumption(for: session, adapter: adapter, continuing: continuingConversation)

        // Committed to the session *before* launch, so the card owns the id
        // even if the process dies on its first breath.
        if case .fresh(let minted?) = resumption {
            session.providerSessionID = minted
        }

        session.workMode = workMode

        let execPath = type(of: adapter).executablePath
        var args = adapter.launchArgs(
            cwd: session.cwd,
            model: session.model,
            approvalPolicy: approvalPolicy,
            resumption: resumption
        )

        // Detailed mode is the contract's own default, so it injects nothing —
        // and a CLI with no system-prompt flag gets the mode from AGENTS.md
        // instead, which is why that file has to define them.
        if let prompt = workMode.systemPrompt,
           let modeArgs = adapter.systemPromptArgs(prompt) {
            args += modeArgs
        }

        let ptyProcess = PTYProcess(executablePath: execPath, arguments: args, cwd: session.cwd)

        try ptyProcess.launch()

        // Create handoff document in /documents/handoffs/ directory
        createHandoffDocument(projectID: session.projectID, workUnitID: session.workUnitID, agent: session.agent)

        lock.lock()
        ptyProcesses[session.id] = ptyProcess

        // `Session` is a reference type — this mutates the caller's instance
        // too. Named accordingly so it does not read as a copy.
        session.state = .ready
        sessions[session.id] = session
        lock.unlock()

        // Registered *after* unlocking, deliberately.
        //
        // This used to call a helper that took the lock again while this method
        // still held it. `NSLock` is not recursive, so launching an agent
        // deadlocked the calling thread — the main thread, in the app — and the
        // window beachballed forever. It was masked for a long time by a crash
        // that happened earlier in the same click.
        ptyProcess.registerOutputCallback { [weak self] output in
            self?.updateSessionState(sessionID: session.id, newOutput: output)
        }
    }

    /// Decides what this launch should do about history.
    ///
    /// A fresh launch on a CLI that accepts a pre-assigned id gets one minted
    /// here, so the conversation is identifiable from the first byte. A
    /// continuing launch reopens the exact conversation when the id is known
    /// and otherwise falls back to the newest one in the directory — which is
    /// the best those CLIs can currently do, and is wrong whenever two agents
    /// share a project. See the batch document for what closing that needs.
    private func resumption(
        for session: Session,
        adapter: AgentAdapter,
        continuing: Bool
    ) -> Resumption {
        guard continuing, adapter.canReopenConversations else {
            // A fresh launch always gets a *new* id, even on a session that
            // already carries one. Reusing it would be the opposite of what
            // "fresh start" means, and Claude rejects an id that is already on
            // disk anyway — which would stop the agent from starting at all.
            guard adapter.mintsSessionID else { return .fresh(sessionID: nil) }
            return .fresh(sessionID: UUID().uuidString)
        }

        if let known = session.providerSessionID {
            return .conversation(id: known)
        }
        return .mostRecent
    }

    /// Change a running session's mode.
    ///
    /// A launched process cannot have its system prompt rewritten, so this is a
    /// message rather than a flag — which is also why it works on all four CLIs
    /// while the launch-time injection only works on Claude.
    public func switchWorkMode(_ mode: WorkMode, for sessionID: String) throws {
        let (pty, adapter) = try liveSession(sessionID)
        try adapter.sendPrompt(mode.switchInstruction, to: pty)

        lock.lock()
        defer { lock.unlock() }
        sessions[sessionID]?.workMode = mode
        sessions[sessionID]?.lastOutputAt = Date()
    }

    /// Internal, for tests: the resume decision without launching anything.
    ///
    /// Exercising it through `launchSession` would mean running a real agent
    /// CLI, which is exactly the kind of test that only passes on the machine
    /// it was written on.
    func resumptionForTesting(session: Session, continuing: Bool) -> Resumption {
        guard let adapter = adapters[session.agent] else { return .fresh(sessionID: nil) }
        return resumption(for: session, adapter: adapter, continuing: continuing)
    }

    public func sendPrompt(_ prompt: String, to sessionID: String) throws {
        lock.lock()
        guard let ptyProcess = ptyProcesses[sessionID],
              let session = sessions[sessionID],
              let adapter = adapters[session.agent] else {
            lock.unlock()
            throw SessionError.sessionNotFound(sessionID)
        }
        lock.unlock()

        try adapter.sendPrompt(prompt, to: ptyProcess)

        lock.lock()
        defer { lock.unlock() }
        if sessions[sessionID] != nil {
            sessions[sessionID]?.lastOutputAt = Date()
        }
    }

    public func interruptSession(_ sessionID: String) throws {
        let (pty, adapter) = try liveSession(sessionID)
        try adapter.interrupt(pty)
    }

    /// Tell a stopped agent to keep going. The other half of `interruptSession`
    /// — without it you can halt an agent but never restart its train of
    /// thought, which is most of the point of holding the process.
    public func resumeSession(_ sessionID: String) throws {
        let (pty, adapter) = try liveSession(sessionID)
        try adapter.resume(pty)

        lock.lock()
        defer { lock.unlock() }
        sessions[sessionID]?.lastOutputAt = Date()
    }

    /// Switch a running agent to a different model, by its human name.
    ///
    /// Nothing reads the output back to confirm the switch took — see the open
    /// Mark a model switch as pending so updateSessionState can confirm it.
    /// Only commit the change if the next output looks successful (no error,
    /// prompt appears).
    public func selectModel(_ humanName: String, for sessionID: String) throws {
        lock.lock()
        guard let pty = ptyProcesses[sessionID],
              let session = sessions[sessionID],
              let adapter = adapters[session.agent] else {
            lock.unlock()
            throw SessionError.sessionNotFound(sessionID)
        }
        lock.unlock()

        guard let rawValue = adapter.modelFlagValue(for: humanName) else {
            throw SessionError.unknownModel(humanName, session.agent)
        }

        let model = ModelRef(agent: session.agent, rawValue: rawValue)
        try adapter.selectModel(model, on: pty)

        lock.lock()
        defer { lock.unlock() }
        // Track this as pending — only commit it to the session when we confirm
        // the output shows success (no error, prompt appears).
        pendingModelSwitch[sessionID] = model
    }

    /// Kill whatever is running and start the same session again from scratch.
    ///
    /// Distinct from `resumeSession`: this throws the conversation away. It is
    /// what "relaunch" on a dead card should do.
    public func restartSession(
        _ sessionID: String,
        approvalPolicy: ApprovalPolicy = .safeAuto,
        continuingConversation: Bool = false,
        workMode: WorkMode? = nil
    ) throws {
        lock.lock()
        guard let session = sessions[sessionID] else {
            lock.unlock()
            throw SessionError.sessionNotFound(sessionID)
        }
        lock.unlock()

        teardownPTY(for: sessionID)

        session.state = .launching
        try launchSession(
            session,
            approvalPolicy: approvalPolicy,
            continuingConversation: continuingConversation,
            // Nil means "whatever this session was already running under" — a
            // relaunch should not silently drop a card back to the global
            // default just because the default is what a new card would get.
            workMode: workMode ?? session.workMode
        )
    }

    public func terminateSession(_ sessionID: String) throws {
        lock.lock()
        guard let ptyProcess = ptyProcesses[sessionID] else {
            lock.unlock()
            throw SessionError.sessionNotFound(sessionID)
        }
        lock.unlock()

        // Synchronous: the session is removed from the table on the next line,
        // so this is the last chance to reach the process group. A fire-and-
        // forget terminate would leak the agent and all of its descendants.
        ptyProcess.shutdown()

        lock.lock()
        defer { lock.unlock() }
        ptyProcesses.removeValue(forKey: sessionID)

        if let session = sessions[sessionID] {
            // Report what actually happened, not a hardcoded success.
            session.state = .exited(exitCode: ptyProcess.exitCode ?? 0)
            sessions[sessionID] = session
        }
    }

    /// Swaps the adapter used for a kind.
    ///
    /// Internal: tests use it to launch a harmless stand-in binary through the
    /// real `launchSession` path, so the lifecycle can be exercised without an
    /// agent CLI installed.
    func register(_ adapter: AgentAdapter, for kind: AgentKind) {
        lock.lock()
        defer { lock.unlock() }
        adapters[kind] = adapter
    }

    /// Attaches an already-launched process to a session.
    ///
    /// Internal, not public: the app always goes through `launchSession`. Tests
    /// use this to drive the lifecycle with a stand-in process rather than
    /// requiring an agent CLI to be installed.
    func attach(_ pty: PTYProcess, to sessionID: String) {
        lock.lock()
        defer { lock.unlock() }
        ptyProcesses[sessionID] = pty
    }

    /// Removes a session entirely, killing it first if it is still running.
    ///
    /// `terminateSession` deliberately keeps the record so the card can still
    /// show how the agent ended. This is the other half: once you have read
    /// that, you need a way to be rid of it, or dead sessions accumulate for as
    /// long as the app is open.
    public func forgetSession(_ sessionID: String) {
        teardownPTY(for: sessionID)

        lock.lock()
        defer { lock.unlock() }
        sessions.removeValue(forKey: sessionID)
        sessionErrors.removeValue(forKey: sessionID)
        retryAttempts.removeValue(forKey: sessionID)
        lastDetectionAt.removeValue(forKey: sessionID)
        pendingDetection.removeValue(forKey: sessionID)
    }

    /// Shuts down the pty attached to a session, leaving the session itself in
    /// the table.
    ///
    /// Both restart and recover used to just drop the reference, which leaked
    /// the old agent and every process it had spawned.
    func teardownPTY(for sessionID: String) {
        lock.lock()
        let existing = ptyProcesses.removeValue(forKey: sessionID)
        lock.unlock()

        existing?.shutdown()
    }

    private func liveSession(_ sessionID: String) throws -> (PTYProcess, AgentAdapter) {
        lock.lock()
        defer { lock.unlock() }

        guard let pty = ptyProcesses[sessionID],
              let session = sessions[sessionID],
              let adapter = adapters[session.agent] else {
            throw SessionError.sessionNotFound(sessionID)
        }
        return (pty, adapter)
    }

    public func session(_ sessionID: String) -> Session? {
        lock.lock()
        defer { lock.unlock() }
        return sessions[sessionID]
    }

    public func allSessions() -> [Session] {
        lock.lock()
        defer { lock.unlock() }
        return Array(sessions.values)
    }

    /// Called on the pty's read queue for every chunk. Keeps the cheap part
    /// (when did this agent last speak) exact, and rate-limits the expensive
    /// part (what is it doing) to `detectionInterval`.
    private func updateSessionState(sessionID: String, newOutput: String) {
        let window = String(newOutput.suffix(Self.detectionWindowBytes))

        lock.lock()
        guard let session = sessions[sessionID], adapters[session.agent] != nil else {
            lock.unlock()
            return
        }
        // A process that has exited stays exited. Output can still arrive after
        // termination — the final flush — and it must not resurrect the session.
        if case .exited = session.state {
            lock.unlock()
            return
        }

        // Free, and read by the dashboard every second, so keep it truthful at
        // the moment the output actually arrived rather than when detection
        // eventually gets around to it.
        session.lastOutputAt = Date()

        let now = Date()
        let elapsed = lastDetectionAt[sessionID].map { now.timeIntervalSince($0) }
            ?? .greatestFiniteMagnitude

        if elapsed >= Self.detectionInterval {
            lastDetectionAt[sessionID] = now
            pendingDetection.removeValue(forKey: sessionID)
            lock.unlock()
            runStateDetection(sessionID: sessionID, window: window)
            return
        }

        // Inside the window. Hold the newest output and make sure exactly one
        // trailing run is queued — without it, the last chunk of a burst is
        // precisely the one that gets dropped, and a session that finishes
        // talking would sit on WORKING forever.
        let alreadyScheduled = pendingDetection[sessionID] != nil
        pendingDetection[sessionID] = window
        lock.unlock()

        guard !alreadyScheduled else { return }

        detectionQueue.asyncAfter(deadline: .now() + (Self.detectionInterval - elapsed)) {
            [weak self] in
            guard let self else { return }

            self.lock.lock()
            let pending = self.pendingDetection.removeValue(forKey: sessionID)
            if pending != nil { self.lastDetectionAt[sessionID] = Date() }
            self.lock.unlock()

            guard let pending else { return }
            self.runStateDetection(sessionID: sessionID, window: pending)
        }
    }

    /// The expensive half: ANSI stripping, windowing and pattern matching.
    /// Never call this on every chunk — see `updateSessionState`.
    private func runStateDetection(sessionID: String, window: String) {
        lock.lock()
        guard let session = sessions[sessionID],
              let adapter = adapters[session.agent] else {
            lock.unlock()
            return
        }
        if case .exited = session.state {
            lock.unlock()
            return
        }
        lock.unlock()

        let newState = adapter.detectState(fromRecentOutput: window)

        lock.lock()
        defer { lock.unlock() }

        // Re-checked, because detection now runs unlocked and the trailing run
        // is deferred: the session can have exited in between.
        guard let updatedSession = sessions[sessionID] else { return }
        if case .exited = updatedSession.state { return }

        // `.unknown` means the output did not say, which is not a reason to
        // discard what it last did say. Keep the previous state instead.
        if newState != .unknown {
            updatedSession.state = newState
        }

        // Confirm pending model switch: if we see the agent back at a prompt
        // with no error, commit the model change.
        if let pendingModel = pendingModelSwitch[sessionID] {
            let outputLower = window.lowercased()
            let hasError = outputLower.contains("error") || outputLower.contains("failed") ||
                          outputLower.contains("unknown model") || outputLower.contains("not found")
            let isReady = newState == .ready || newState == .working

            if !hasError && isReady {
                // Model switch succeeded
                updatedSession.model = pendingModel
                pendingModelSwitch.removeValue(forKey: sessionID)
            } else if hasError {
                // Model switch failed, stop waiting
                pendingModelSwitch.removeValue(forKey: sessionID)
            }
            // If still waiting (output is unclear), keep the pending flag
        }

        sessions[sessionID] = updatedSession
    }

    /// Sessions that still have a process behind them. This used to be a second
    /// copy of `allSessions()`, which made the name a lie.
    public func getActiveSessions() -> [Session] {
        lock.lock()
        defer { lock.unlock() }
        return sessions.values.filter { session in
            if case .exited = session.state { return false }
            return ptyProcesses[session.id]?.isProcessRunning ?? false
        }
    }

    public func getPTYProcess(for sessionID: String) -> PTYProcess? {
        lock.lock()
        defer { lock.unlock() }
        return ptyProcesses[sessionID]
    }

    public func recordSessionError(_ sessionID: String, error: String) {
        lock.lock()
        defer { lock.unlock() }

        if let existing = sessionErrors[sessionID] {
            sessionErrors[sessionID] = (error, existing.count + 1, Date())
        } else {
            sessionErrors[sessionID] = (error, 1, Date())
        }
    }

    public func getSessionError(_ sessionID: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return sessionErrors[sessionID]?.error
    }

    public func sessionHasCriticalErrors(_ sessionID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return (sessionErrors[sessionID]?.count ?? 0) >= errorThresholdCount
    }

    public func recoverSession(_ sessionID: String) throws {
        lock.lock()
        guard let session = sessions[sessionID] else {
            lock.unlock()
            throw SessionError.sessionNotFound(sessionID)
        }

        // `retryAttempts` used to be read and written outside the lock.
        let attempts = (retryAttempts[sessionID] ?? 0) + 1
        guard attempts <= maxRetries else {
            lock.unlock()
            throw SessionError.retryLimitReached(sessionID)
        }
        retryAttempts[sessionID] = attempts
        sessionErrors[sessionID] = nil
        lock.unlock()

        // Kills the old process group rather than orphaning it.
        teardownPTY(for: sessionID)

        session.state = .launching
        try launchSession(session)
    }

    private func createHandoffDocument(projectID: String, workUnitID: String, agent: AgentKind) {
        // Install workflow contract files first (AGENTS.md and CLAUDE.md)
        installWorkflowContract(projectPath: projectID)

        // Create handoff document in project's /documents/handoffs/ directory.
        // File is named after the work unit with .md extension.
        let fm = FileManager.default
        let projectPath = projectID
        let handoffsDir = projectPath + "/documents/handoffs"

        do {
            try fm.createDirectory(atPath: handoffsDir, withIntermediateDirectories: true)

            let filename = workUnitID + ".md"
            let filepath = handoffsDir + "/" + filename

            // Create initial handoff document if it doesn't exist
            if !fm.fileExists(atPath: filepath) {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                let timestamp = dateFormatter.string(from: Date())

                let content = """
                # \(workUnitID)

                **Agent**: \(agent.rawValue)
                **Created**: \(timestamp)
                **Status**: In Progress

                ## Task
                [Task description here]

                ## Progress
                - Agent started

                ## Changes
                [Changes will be documented here]

                ## Next Steps
                [To be determined]
                """

                try content.write(toFile: filepath, atomically: true, encoding: String.Encoding.utf8)
            }
        } catch {
            // Silently fail if we can't create the document — don't crash the session
            print("Failed to create handoff document: \(error)")
        }
    }

    private func installWorkflowContract(projectPath: String) {
        let fm = FileManager.default
        let projectName = (projectPath as NSString).lastPathComponent

        // Create AGENTS.md with the workflow contract
        let agentsPath = projectPath + "/AGENTS.md"
        if !fm.fileExists(atPath: agentsPath) {
            do {
                let contract = WorkflowContract.agentsMarkdown(projectName: projectName)
                try contract.write(toFile: agentsPath, atomically: true, encoding: String.Encoding.utf8)
            } catch {
                print("Failed to create AGENTS.md: \(error)")
            }
        }

        // Create CLAUDE.md that imports AGENTS.md
        let claudePath = projectPath + "/CLAUDE.md"
        if !fm.fileExists(atPath: claudePath) {
            do {
                try WorkflowContract.claudeImport.write(toFile: claudePath, atomically: true, encoding: String.Encoding.utf8)
            } catch {
                print("Failed to create CLAUDE.md: \(error)")
            }
        }
    }

    public enum SessionError: LocalizedError {
        case sessionNotFound(String)
        case unknownAgent(AgentKind)
        case retryLimitReached(String)
        case unknownModel(String, AgentKind)

        public var errorDescription: String? {
            switch self {
            case .sessionNotFound(let id):
                return "Session not found: \(id)"
            case .unknownAgent(let agent):
                return "Unknown agent: \(agent)"
            case .retryLimitReached(let id):
                return "Gave up recovering session \(id) after repeated failures"
            case .unknownModel(let name, let agent):
                return "\(agent.rawValue) has no model called \"\(name)\""
            }
        }
    }
}
