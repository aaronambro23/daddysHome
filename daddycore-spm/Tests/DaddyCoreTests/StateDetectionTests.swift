import XCTest
@testable import DaddyCore

/// Regression tests for the bug that made the dashboard untrustworthy: state was
/// inferred from the whole retained transcript, so any word that ever appeared
/// was permanent evidence.
final class StateDetectionTests: XCTestCase {

    // MARK: - The original bug

    func testWordFailedEarlierDoesNotPinTheSessionToError() {
        let adapter = ClaudeAdapter()

        // The agent said "failed" once, a long time ago, and has since moved on.
        var transcript = "3 tests failed in auth_spec.rb\n"
        transcript += (1...60).map { "  patched line \($0)\n" }.joined()
        transcript += "> "

        XCTAssertEqual(adapter.detectState(fromRecentOutput: transcript), .ready)
    }

    func testNarratingAnErrorWhileWorkingIsWorkingNotError() {
        let adapter = ClaudeAdapter()

        let transcript = """
        I found the error in the parser — it drops the final token.
        ✻ Thinking… (esc to interrupt)
        """

        XCTAssertEqual(adapter.detectState(fromRecentOutput: transcript), .working)
    }

    func testClaudeCurrentFooterTransitionsFromWorkingToReady() {
        let adapter = ClaudeAdapter()

        XCTAssertEqual(
            adapter.detectState(
                fromRecentOutput: "✻ Working…\nesc to interrupt"
            ),
            .working
        )

        XCTAssertEqual(
            adapter.detectState(
                fromRecentOutput: """
                ✻ Working… (esc to interrupt)
                Finished the fix.
                ❯
                ⏵⏵ accept edits on (shift+tab to cycle) · ↔ for agents
                """
            ),
            .ready,
            "the current idle footer must override an older busy line in the same redraw"
        )
    }

    func testClaudeIdleFooterDoesNotHideRateLimitOrFailure() {
        let adapter = ClaudeAdapter()
        let footer = "⏵⏵ accept edits on (shift+tab to cycle) · ↔ for agents"

        XCTAssertEqual(
            adapter.detectState(fromRecentOutput: "rate limit exceeded\n\(footer)"),
            .rateLimited
        )
        XCTAssertEqual(
            adapter.detectState(fromRecentOutput: "Error: invalid API key\n\(footer)"),
            .error("Detected failure in recent output")
        )
    }

    func testRealFailureIsStillDetected() {
        let adapter = ClaudeAdapter()

        XCTAssertEqual(
            adapter.detectState(fromRecentOutput: "claude: command not found"),
            .error("Detected failure in recent output")
        )
        XCTAssertEqual(
            adapter.detectState(fromRecentOutput: "some context\nError: invalid API key"),
            .error("Detected failure in recent output")
        )
    }

    // MARK: - Unknown is not ready

    func testUnrecognisedOutputIsUnknownRatherThanReady() {
        let adapter = ClaudeAdapter()

        let state = adapter.detectState(fromRecentOutput: "Reticulating splines.\nAlmost there.")
        XCTAssertEqual(state, .unknown, "silence about state must not be reported as ready")
    }

    func testCodexNoLongerCallsEverythingReady() {
        let adapter = CodexAdapter()

        // The old implementation returned .ready for this, because it contained
        // ">" — as does nearly every line any of these CLIs print.
        let state = adapter.detectState(fromRecentOutput: "reading src/main.rs -> 412 lines")
        XCTAssertNotEqual(state, .ready)
    }

    func testCodexPromptIsStillReady() {
        XCTAssertEqual(CodexAdapter().detectState(fromRecentOutput: "done.\n❯ "), .ready)
    }

    // MARK: - Windowing

    func testOnlyTheTailIsEvidence() {
        // Rate limit hit early, cleared, and the agent is working again.
        var transcript = "rate limit reached, backing off\n"
        transcript += (1...80).map { "line \($0)\n" }.joined()
        transcript += "✻ Analyzing the diff… (esc to interrupt)"

        XCTAssertEqual(ClaudeAdapter().detectState(fromRecentOutput: transcript), .working)
    }

    func testCurrentRateLimitIsDetected() {
        XCTAssertEqual(
            ClaudeAdapter().detectState(fromRecentOutput: "You've reached your usage limit."),
            .rateLimited
        )
    }

    // MARK: - Window mechanics

    func testANSIEscapesAreStrippedBeforeMatching() {
        let coloured = "\u{1b}[1;31mError:\u{1b}[0m boom\n"
        XCTAssertEqual(OutputHeuristics.stripANSI(coloured), "Error: boom\n")
    }

    func testOSCSequencesAreStripped() {
        let titled = "\u{1b}]0;my title\u{07}hello"
        XCTAssertEqual(OutputHeuristics.stripANSI(titled), "hello")
    }

    func testCarriageReturnRedrawKeepsOnlyWhatWasVisible() {
        // A spinner overwriting itself on one line.
        let redrawn = "⠋ working\r⠙ working\r✓ done"
        XCTAssertEqual(OutputHeuristics.recentWindow(redrawn), "✓ done")
    }

    func testWindowKeepsOnlyTheTrailingLines() {
        let many = (1...200).map { "line \($0)" }.joined(separator: "\n")
        let window = OutputHeuristics.recentWindow(many, lines: 5)

        XCTAssertEqual(window, "line 196\nline 197\nline 198\nline 199\nline 200")
        XCTAssertFalse(window.contains("line 1\n"))
    }

    func testBlankLinesDoNotConsumeTheWindow() {
        let padded = "signal\n" + String(repeating: "\n", count: 50)
        XCTAssertEqual(OutputHeuristics.recentWindow(padded, lines: 3), "signal")
    }

    // MARK: - Every adapter got the fix

    func testNoAdapterFallsThroughToReady() {
        let adapters: [AgentAdapter] = [
            ClaudeAdapter(), CodexAdapter(), CursorAdapter(), OpenCodeAdapter(),
        ]

        for adapter in adapters {
            XCTAssertEqual(
                adapter.detectState(fromRecentOutput: "unremarkable chatter"),
                .unknown,
                "\(type(of: adapter)) still guesses ready"
            )
        }
    }

    func testEveryAdapterDetectsRateLimit() {
        let adapters: [AgentAdapter] = [
            ClaudeAdapter(), CodexAdapter(), CursorAdapter(), OpenCodeAdapter(),
        ]

        for adapter in adapters {
            XCTAssertEqual(
                adapter.detectState(fromRecentOutput: "rate limit exceeded"),
                .rateLimited,
                "\(type(of: adapter)) missed a rate limit"
            )
        }
    }

    // MARK: - Persistence of the new case

    func testUnknownRoundTripsThroughCodable() throws {
        let encoded = try JSONEncoder().encode(AgentState.unknown)
        XCTAssertEqual(try JSONDecoder().decode(AgentState.self, from: encoded), .unknown)
    }
}
