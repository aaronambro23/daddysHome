import Foundation

public final class SessionManager {
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

    public init() {
        self.adapters = [
            .claude: ClaudeAdapter(),
            .codex: CodexAdapter(),
            .cursor: CursorAdapter(),
            .opencode: OpenCodeAdapter(),
        ]
    }

    public func createSession(
        projectID: String,
        workUnitID: String,
        agent: AgentKind,
        model: ModelRef? = nil,
        cwd: URL
    ) throws -> Session {
        let session = Session(
            projectID: projectID,
            workUnitID: workUnitID,
            agent: agent,
            model: model,
            cwd: cwd
        )

        lock.lock()
        defer { lock.unlock() }
        sessions[session.id] = session
        return session
    }

    /// Whether this agent can pick up its previous conversation on relaunch.
    public func canContinueConversation(_ kind: AgentKind) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return adapters[kind]?.continueConversationArgs != nil
    }

    public func launchSession(
        _ session: Session,
        approvalPolicy: ApprovalPolicy = .safeAuto,
        continuingConversation: Bool = false
    ) throws {
        guard let adapter = adapters[session.agent] else {
            throw SessionError.unknownAgent(session.agent)
        }

        let execPath = type(of: adapter).executablePath
        var args = adapter.launchArgs(cwd: session.cwd, model: session.model, approvalPolicy: approvalPolicy)

        if continuingConversation, let resumeArgs = adapter.continueConversationArgs {
            args += resumeArgs
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
        continuingConversation: Bool = false
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
            continuingConversation: continuingConversation
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

    private func updateSessionState(sessionID: String, newOutput: String) {
        lock.lock()
        guard let session = sessions[sessionID],
              let adapter = adapters[session.agent] else {
            lock.unlock()
            return
        }
        // A process that has exited stays exited. Output can still arrive after
        // termination — the final flush — and it must not resurrect the session.
        if case .exited = session.state {
            lock.unlock()
            return
        }
        lock.unlock()

        let newState = adapter.detectState(fromRecentOutput: newOutput)

        lock.lock()
        defer { lock.unlock() }
        let updatedSession = session
        // `.unknown` means the output did not say, which is not a reason to
        // discard what it last did say. Keep the previous state instead.
        if newState != .unknown {
            updatedSession.state = newState
        }
        updatedSession.lastOutputAt = Date()

        // Confirm pending model switch: if we see the agent back at a prompt
        // with no error, commit the model change.
        if let pendingModel = pendingModelSwitch[sessionID] {
            let outputLower = newOutput.lowercased()
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
