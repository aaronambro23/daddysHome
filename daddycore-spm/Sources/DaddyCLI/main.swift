import Foundation
import DaddyCore

@main
struct DaddyCLI {
    static func main() {
        let args = CommandLine.arguments

        if args.count < 2 {
            printUsage()
            exit(1)
        }

        let command = args[1]

        switch command {
        case "launch":
            handleLaunch(args: Array(args.dropFirst(2)))
        case "status":
            handleStatus(args: Array(args.dropFirst(2)))
        case "help":
            printUsage()
        default:
            print("Unknown command: \(command)")
            printUsage()
            exit(1)
        }
    }

    static func handleLaunch(args: [String]) {
        guard args.count >= 2 else {
            print("Usage: daddy-cli launch <agent> <project-path> [model]")
            print("Agents: claude, codex, cursor, opencode")
            exit(1)
        }

        let agentName = args[0]
        let projectPath = args[1]
        let model = args.count > 2 ? args[2] : nil

        guard let agent = AgentKind(rawValue: agentName.lowercased()) else {
            print("Unknown agent: \(agentName)")
            exit(1)
        }

        let projectURL = URL(fileURLWithPath: projectPath)

        let manager = SessionManager()

        do {
            let session = try manager.createSession(
                projectID: agentName,
                workUnitID: agentName,
                agent: agent,
                model: model.map { ModelRef(agent: agent, rawValue: $0) },
                cwd: projectURL
            )

            print("Launching \(agent.rawValue) in \(projectPath)...")
            try manager.launchSession(session)

            print("Session \(session.id) launched successfully")
            print("Agent: \(agent.rawValue)")
            print("State: ready")

            Thread.sleep(forTimeInterval: 2.0)

            if let updatedSession = manager.session(session.id) {
                print("After 2s - State: \(updatedSession.state)")
            }

            try manager.terminateSession(session.id)
            print("Session terminated")

        } catch {
            print("Error: \(error.localizedDescription)")
            exit(1)
        }
    }

    static func handleStatus(args: [String]) {
        print("Status command not yet implemented")
    }

    static func printUsage() {
        print("""
        daddy-cli — Daddy control plane CLI

        Usage:
          daddy-cli launch <agent> <project-path> [model]
          daddy-cli help

        Agents:
          claude     Claude Code
          codex      Codex
          cursor     Cursor Agent CLI
          opencode   OpenCode

        Examples:
          daddy-cli launch claude ~/Documents/my-project opus
          daddy-cli launch codex ~/Documents/my-project
        """)
    }
}
