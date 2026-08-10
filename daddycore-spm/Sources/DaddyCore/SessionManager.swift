import Foundation

final class SessionManager {
    private var sessions: [String: Session] = [:]
    private var ptyProcesses: [String: PTYProcess] = [:]
    private var adapters: [AgentKind: AgentAdapter] = [:]
    private let lock = NSLock()

    init() {
        self.adapters = [
            .claude: ClaudeAdapter(),
            .codex: CodexAdapter(),
            .cursor: CursorAdapter(),
            .opencode: OpenCodeAdapter(),
        ]
    }

    func createSession(
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

    func launchSession(_ session: Session, approvalPolicy: ApprovalPolicy = .safeAuto) throws {
        guard let adapter = adapters[session.agent] else {
            throw SessionError.unknownAgent(session.agent)
        }

        let execPath = type(of: adapter).executablePath
        let args = adapter.launchArgs(cwd: session.cwd, model: session.model, approvalPolicy: approvalPolicy)

        let ptyProcess = PTYProcess(executablePath: execPath, arguments: args, cwd: session.cwd)

        try ptyProcess.launch()

        lock.lock()
        defer { lock.unlock() }
        ptyProcesses[session.id] = ptyProcess

        var sessionCopy = session
        sessionCopy.state = .ready
        sessions[session.id] = sessionCopy

        captureSessionOutput(sessionID: session.id)
    }

    func sendPrompt(_ prompt: String, to sessionID: String) throws {
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

    func interruptSession(_ sessionID: String) throws {
        lock.lock()
        guard let ptyProcess = ptyProcesses[sessionID],
              let session = sessions[sessionID],
              let adapter = adapters[session.agent] else {
            lock.unlock()
            throw SessionError.sessionNotFound(sessionID)
        }
        lock.unlock()

        try adapter.interrupt(ptyProcess)
    }

    func terminateSession(_ sessionID: String) throws {
        lock.lock()
        guard let ptyProcess = ptyProcesses[sessionID] else {
            lock.unlock()
            throw SessionError.sessionNotFound(sessionID)
        }
        lock.unlock()

        ptyProcess.terminate()

        lock.lock()
        defer { lock.unlock() }
        ptyProcesses.removeValue(forKey: sessionID)

        if var session = sessions[sessionID] {
            session.state = .exited(exitCode: 0)
            sessions[sessionID] = session
        }
    }

    func session(_ sessionID: String) -> Session? {
        lock.lock()
        defer { lock.unlock() }
        return sessions[sessionID]
    }

    func allSessions() -> [Session] {
        lock.lock()
        defer { lock.unlock() }
        return Array(sessions.values)
    }

    private func captureSessionOutput(sessionID: String) {
        lock.lock()
        guard let ptyProcess = ptyProcesses[sessionID] else {
            lock.unlock()
            return
        }
        lock.unlock()

        ptyProcess.registerOutputCallback { [weak self] output in
            self?.updateSessionState(sessionID: sessionID, newOutput: output)
        }
    }

    private func updateSessionState(sessionID: String, newOutput: String) {
        lock.lock()
        guard let session = sessions[sessionID],
              let adapter = adapters[session.agent] else {
            lock.unlock()
            return
        }
        lock.unlock()

        let newState = adapter.detectState(fromRecentOutput: newOutput)

        lock.lock()
        defer { lock.unlock() }
        var updatedSession = session
        updatedSession.state = newState
        updatedSession.lastOutputAt = Date()
        sessions[sessionID] = updatedSession

    }

    enum SessionError: LocalizedError {
        case sessionNotFound(String)
        case unknownAgent(AgentKind)

        var errorDescription: String? {
            switch self {
            case .sessionNotFound(let id):
                return "Session not found: \(id)"
            case .unknownAgent(let agent):
                return "Unknown agent: \(agent)"
            }
        }
    }
}
