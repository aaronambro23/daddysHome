import XCTest
@testable import DaddyCore
import Foundation

final class TerminalLauncherTests: XCTestCase {

    private let launcher = TerminalLauncher()

    // MARK: Quoting
    //
    // Two layers of escaping: the command sits inside an AppleScript string
    // literal, which is then handed to a shell. Both have to survive.

    func testShellQuotesPathsWithSpaces() {
        // "Obsidian Vault" and "Elite Breathing" are real project names here.
        let command = launcher.shellCommand(
            executable: "/usr/local/bin/claude",
            projectPath: URL(fileURLWithPath: "/Users/x/Documents/Obsidian Vault"),
            prompt: nil
        )
        XCTAssertTrue(command.contains("'/Users/x/Documents/Obsidian Vault'"))
        XCTAssertTrue(command.hasPrefix("cd '"))
    }

    func testShellQuotesApostrophesInPrompt() {
        // Prompts are English sentences; apostrophes are guaranteed to appear
        // and would otherwise terminate the quoted string.
        let command = launcher.shellCommand(
            executable: "/bin/claude",
            projectPath: URL(fileURLWithPath: "/tmp/p"),
            prompt: "don't redo what's done"
        )
        XCTAssertFalse(command.contains("don't redo"), "Raw apostrophe leaked into shell text")
        XCTAssertTrue(command.contains("'\\''"), "Expected POSIX single-quote escaping")
    }

    func testAppleScriptQuotingEscapesQuotesAndBackslashes() {
        XCTAssertEqual(TerminalLauncher.appleScriptQuote("say \"hi\""), "say \\\"hi\\\"")
        XCTAssertEqual(TerminalLauncher.appleScriptQuote("back\\slash"), "back\\\\slash")
    }

    func testPromptIsCollapsedToOneLine() {
        // Prompts are written as multi-line Swift literals; a newline inside
        // `do script` would run half a command.
        let prompt = TerminalLauncher.continuePrompt(documentPath: "docs/handoffs/002-x.md")
        let collapsed = TerminalLauncher.collapseWhitespace(prompt)
        XCTAssertFalse(collapsed.contains("\n"))
        XCTAssertFalse(collapsed.contains("  "))

        let command = launcher.shellCommand(
            executable: "/bin/claude",
            projectPath: URL(fileURLWithPath: "/tmp/p"),
            prompt: prompt
        )
        XCTAssertFalse(command.contains("\n"))
    }

    // MARK: Command shape

    func testCommandCdsThenRunsAgent() {
        let command = launcher.shellCommand(
            executable: "/opt/homebrew/bin/codex",
            projectPath: URL(fileURLWithPath: "/tmp/proj"),
            prompt: "do the thing"
        )
        XCTAssertEqual(command, "cd '/tmp/proj' && '/opt/homebrew/bin/codex' 'do the thing'")
    }

    func testExtraArgumentsComeBeforeThePrompt() {
        let command = launcher.shellCommand(
            executable: "/bin/claude",
            projectPath: URL(fileURLWithPath: "/tmp/p"),
            prompt: "go",
            extraArguments: ["--model", "opus-5"]
        )
        XCTAssertEqual(command, "cd '/tmp/p' && '/bin/claude' '--model' 'opus-5' 'go'")
    }

    func testNoPromptOmitsTheArgument() {
        let command = launcher.shellCommand(
            executable: "/bin/claude",
            projectPath: URL(fileURLWithPath: "/tmp/p"),
            prompt: nil
        )
        XCTAssertEqual(command, "cd '/tmp/p' && '/bin/claude'")
    }

    // MARK: Prompts

    func testContinuePromptNamesTheDocumentAndForbidsRework() {
        let prompt = TerminalLauncher.continuePrompt(documentPath: "docs/handoffs/002-payments.md")
        XCTAssertTrue(prompt.contains("docs/handoffs/002-payments.md"))
        XCTAssertTrue(prompt.contains("AGENTS.md"))
        XCTAssertTrue(prompt.lowercased().contains("not yet ticked"))
        // The expensive failure is a fresh agent redoing finished work.
        XCTAssertTrue(prompt.lowercased().contains("do not redo"))
    }

    func testNewBatchPromptZeroPadsAndAsksFirst() {
        let prompt = TerminalLauncher.newBatchPrompt(nextNumber: 7)
        XCTAssertTrue(prompt.contains("007-"))
        XCTAssertTrue(prompt.contains(WorkflowContract.handoffDirectory))
        // The contract says ask before coding; the launch prompt must agree.
        XCTAssertTrue(prompt.lowercased().contains("ask me"))
    }

    // MARK: Failure modes

    func testMissingProjectDirectoryThrows() {
        XCTAssertThrowsError(
            try launcher.launch(
                agent: .claude,
                executableName: "sh",
                projectPath: URL(fileURLWithPath: "/tmp/definitely-missing-\(UUID().uuidString)"),
                prompt: nil
            )
        ) { error in
            guard case TerminalLauncher.LaunchError.projectMissing = error else {
                return XCTFail("Expected projectMissing, got \(error)")
            }
        }
    }

    func testMissingExecutableThrows() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertThrowsError(
            try launcher.launch(
                agent: .claude,
                executableName: "not-a-real-binary-\(UUID().uuidString)",
                projectPath: dir,
                prompt: nil
            )
        ) { error in
            guard case TerminalLauncher.LaunchError.executableMissing = error else {
                return XCTFail("Expected executableMissing, got \(error)")
            }
        }
    }
}
