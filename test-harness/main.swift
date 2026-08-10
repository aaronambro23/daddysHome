import Foundation

// A simple test harness to exercise SessionManager with real CLIs
// This will help empirically verify adapter behavior before UI integration

let manager = SessionManager()
let projectDir = FileManager.default.currentDirectoryPath
let projectURL = URL(fileURLWithPath: projectDir)

print("=== DaddyCore Session Manager Test ===")
print("Project directory: \(projectDir)")

do {
    // Create a session for Claude
    let session = try manager.createSession(
        projectID: "test-project",
        workUnitID: "test-work",
        agent: .claude,
        cwd: projectURL
    )

    print("\n✓ Created session: \(session.id)")
    print("  Agent: \(session.agent)")
    print("  Initial state: \(session.state)")

    // Attempt to launch
    print("\n→ Launching Claude Code...")
    do {
        try manager.launchSession(session)
        print("✓ Session launched")

        if let launchedSession = manager.session(session.id) {
            print("  Session state: \(launchedSession.state)")
        }

        // Wait a bit for output to arrive
        Thread.sleep(forTimeInterval: 1.0)

        if let sessionAfterWait = manager.session(session.id) {
            print("  Session state after 1s: \(sessionAfterWait.state)")
        }

        // Clean up
        try manager.terminateSession(session.id)
        print("\n✓ Session terminated")
    } catch {
        print("⚠ Failed to launch Claude: \(error)")
        print("  (This is expected if Claude Code is not in PATH)")
    }

    // Test with a simpler CLI (echo)
    print("\n=== Testing with 'echo' command ===")

    let echoSession = try manager.createSession(
        projectID: "test-project",
        workUnitID: "echo-test",
        agent: .claude,
        model: ModelRef(agent: .claude, rawValue: "sonnet"),
        cwd: projectURL
    )

    let adapter = ClaudeAdapter()
    let echoArgs = ["hello", "from", "daddy"]

    print("Adapter launch args for claude:")
    let launchArgs = adapter.launchArgs(cwd: projectURL, model: echoSession.model, approvalPolicy: .safeAuto)
    print("  \(launchArgs)")

    print("\nModel flag values:")
    print("  'opus' -> \(adapter.modelFlagValue(for: "opus") ?? "nil")")
    print("  'Sonnet' -> \(adapter.modelFlagValue(for: "Sonnet") ?? "nil")")
    print("  'Haiku' -> \(adapter.modelFlagValue(for: "Haiku") ?? "nil")")

    print("\n✓ Test harness complete")

} catch {
    print("✗ Error: \(error)")
    exit(1)
}
