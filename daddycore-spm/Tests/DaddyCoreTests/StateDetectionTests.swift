import XCTest
@testable import DaddyCore

/// Detection reads the agent's *rendered screen*, not the byte stream that
/// produced it.
///
/// The tests that used to live here handed adapters clean multi-line strings.
/// That is not what a pty delivers, and the difference was the bug: agent TUIs
/// redraw by moving the cursor and erasing lines, so stripping escape codes out
/// of the stream leaves every erased repaint behind as ordinary text. The old
/// suite passed while the app latched on WORKING forever, because the fixtures
/// described a screen the parser never actually received.
///
/// So the fixtures here are raw byte streams, fed through the same emulator the
/// visible pane uses. `screen(_:)` is the whole difference.
final class StateDetectionTests: XCTestCase {

    // MARK: - Helpers

    /// Renders a raw terminal stream the way the agent's own terminal would.
    private func screen(_ raw: String, columns: Int = 120, rows: Int = 30) -> ScreenSnapshot {
        let shadow = ShadowScreen(columns: columns, rows: rows)
        shadow.feed(raw)
        return shadow.snapshot()
    }

    /// A screen built directly from rows, for testing the matchers themselves.
    private func rows(_ lines: String...) -> ScreenSnapshot {
        ScreenSnapshot(
            rows: lines,
            cursorRow: 0,
            cursorColumn: 0,
            isAlternateScreen: false,
            columns: 120
        )
    }

    private let clear = "\u{1b}[2J\u{1b}[H"
    /// Cursor up one line, then erase that whole line — how a TUI repaints in
    /// place. Everything it erases used to survive `stripANSI` as text.
    private let eraseLineAbove = "\u{1b}[1A\u{1b}[2K"

    private let claudeFooter = "  ⏵⏵ accept edits on (shift+tab to cycle) · ↔ for agents"
    private let composer = "╭──────────────────────────╮\r\n│ >                        │\r\n╰──────────────────────────╯\r\n"

    // MARK: - The bug this file exists for

    /// The regression. A spinner drawn, erased, redrawn, erased, and replaced
    /// by the idle composer — which is what every finished Claude turn looks
    /// like on the wire.
    ///
    /// Against the old byte-stream detector this returned `.working`, because
    /// both erased copies of "esc to interrupt" were still sitting in the
    /// stripped buffer. That is why a card went amber on the first prompt and
    /// stayed amber for the rest of its life.
    func testErasedSpinnerFramesDoNotLatchWorking() {
        let raw = clear
            + "Finished the fix.\r\n"
            + "✻ Thinking… (3s · ↑ 1.2k tokens · esc to interrupt)\r\n"
            + eraseLineAbove
            + "✻ Thinking… (7s · ↑ 2.4k tokens · esc to interrupt)\r\n"
            + eraseLineAbove
            + composer
            + claudeFooter

        // What the old detector saw: strip the escapes out of the same stream
        // and *both* erased frames are still there, in plain text. This is the
        // bug, stated as an assertion.
        let asTheOldDetectorSawIt = OutputHeuristics.stripANSI(raw)
        XCTAssertEqual(
            asTheOldDetectorSawIt.components(separatedBy: "esc to interrupt").count - 1,
            2,
            "the byte stream really does still contain both erased spinner frames"
        )

        // What the screen actually shows.
        let rendered = screen(raw)
        XCTAssertFalse(
            rendered.visibleRows.contains { $0.contains("esc to interrupt") },
            "an erased repaint must not survive into the rendered screen"
        )
        XCTAssertEqual(ClaudeAdapter().detectState(from: rendered), .ready)
    }

    /// The same screen with the spinner still on it is still working.
    func testLiveSpinnerAboveTheComposerIsWorking() {
        let raw = clear
            + "✻ Thinking… (7s · ↑ 2.4k tokens · esc to interrupt)\r\n"
            + composer
            + claudeFooter

        XCTAssertEqual(ClaudeAdapter().detectState(from: screen(raw)), .working)
    }

    /// Claude's footer is pinned below the composer whether or not it is busy,
    /// so it can never mean "idle" on its own.
    func testClaudeFooterIsNotAnIdleSignalByItself() {
        let busy = rows(
            "✻ Working… (esc to interrupt)",
            "╭────────╮", "│ >      │", "╰────────╯",
            claudeFooter
        )
        XCTAssertEqual(ClaudeAdapter().detectState(from: busy), .working)
    }

    // MARK: - Only the bottom of the screen is live status

    /// The word "running" in something the agent *said* is not a status line.
    /// The old detector matched a bare word list anywhere in its window, so any
    /// agent that mentioned running, working or thinking pinned itself busy.
    func testProseAboveTheComposerIsNotAStatusLine() {
        let idle = rows(
            "I am running the tests now and thinking about the failure.",
            "Generating a patch was the last thing I did.",
            "╭────────╮", "│ >      │", "╰────────╯",
            claudeFooter
        )
        XCTAssertEqual(ClaudeAdapter().detectState(from: idle), .ready)
    }

    /// A stale "failed" high up the transcript is history, not status — and it
    /// must not pin the session to `.error`.
    func testFailedEarlierInTheTranscriptDoesNotPinToError() {
        var lines = ["the previous attempt failed and I fixed it"]
        lines += (1...20).map { "  patched line \($0)" }
        lines += ["done.", "❯ "]

        let rendered = ScreenSnapshot(
            rows: lines,
            cursorRow: 0,
            cursorColumn: 0,
            isAlternateScreen: false,
            columns: 120
        )
        XCTAssertEqual(CodexAdapter().detectState(from: rendered), .ready)
    }

    func testNarratingAnErrorWhileWorkingIsWorkingNotError() {
        let busy = rows(
            "Error: the build broke, let me look",
            "✻ Fixing… (esc to interrupt)"
        )
        XCTAssertEqual(ClaudeAdapter().detectState(from: busy), .working)
    }

    // MARK: - Signals that must survive

    func testIdleComposerDoesNotHideRateLimitOrFailure() {
        let limited = rows("You've hit your rate limit.", claudeFooter)
        XCTAssertEqual(ClaudeAdapter().detectState(from: limited), .rateLimited)

        let broken = rows("Error: invalid API key", claudeFooter)
        XCTAssertEqual(
            ClaudeAdapter().detectState(from: broken),
            .error("Detected failure in recent output")
        )
    }

    func testRealFailureIsStillDetected() {
        XCTAssertEqual(
            ClaudeAdapter().detectState(from: rows("claude: command not found")),
            .error("Detected failure in recent output")
        )
        XCTAssertEqual(
            ClaudeAdapter().detectState(from: rows("some context", "Error: invalid API key")),
            .error("Detected failure in recent output")
        )
    }

    func testCtrlCInterruptHintCountsAsWorking() {
        XCTAssertEqual(
            CodexAdapter().detectState(from: rows("▌ Working (5s • Ctrl+C to interrupt)")),
            .working
        )
    }

    // MARK: - Unknown is not ready

    func testUnrecognisedOutputIsUnknownRatherThanReady() {
        XCTAssertEqual(
            ClaudeAdapter().detectState(from: rows("Reticulating splines.", "Almost there.")),
            .unknown
        )
    }

    func testAnEmptyScreenIsUnknown() {
        XCTAssertEqual(ClaudeAdapter().detectState(from: .empty), .unknown)
    }

    func testBarePromptIsReady() {
        XCTAssertEqual(CodexAdapter().detectState(from: rows("done.", "❯ ")), .ready)
    }

    /// A boxed composer ends in a border, not in the prompt character.
    func testBoxedComposerCountsAsAPrompt() {
        XCTAssertEqual(
            CursorAdapter().detectState(from: rows("done.", "│ >                    │")),
            .ready
        )
    }

    // MARK: - Every adapter

    func testNoAdapterFallsThroughToReady() {
        for adapter in [
            ClaudeAdapter() as AgentAdapter, CodexAdapter(), CursorAdapter(), OpenCodeAdapter(),
        ] {
            XCTAssertEqual(
                adapter.detectState(from: rows("unremarkable chatter")),
                .unknown,
                "\(type(of: adapter)) must not guess READY"
            )
        }
    }

    func testEveryAdapterDetectsRateLimits() {
        for adapter in [
            ClaudeAdapter() as AgentAdapter, CodexAdapter(), CursorAdapter(), OpenCodeAdapter(),
        ] {
            XCTAssertEqual(
                adapter.detectState(from: rows("rate limit exceeded")),
                .rateLimited,
                "\(type(of: adapter)) must notice a rate limit"
            )
        }
    }

    // MARK: - Screen mechanics

    /// The shadow mirrors the real pane width, so a footer wraps in a narrow
    /// split. Bottom-anchored matching joins the rows before looking.
    func testWrappedStatusLineIsStillDetected() {
        let narrow = screen(
            clear + "✻ Thinking… (12s · ↑ 4.1k tokens · esc to interrupt)",
            columns: 28,
            rows: 12
        )
        XCTAssertGreaterThan(narrow.visibleRows.count, 1, "this fixture must actually wrap")
        XCTAssertTrue(OutputHeuristics.indicatesWorking(narrow))
    }

    /// `·` is a spinner frame in some TUIs and also the separator in Claude's
    /// permanent footer. Treating it as a spinner pinned every Claude session
    /// to WORKING for its entire life.
    func testFooterSeparatorIsNotASpinner() {
        XCTAssertFalse(OutputHeuristics.indicatesWorking(rows(claudeFooter)))
    }

    /// The last row is permanent chrome, so "the last line the agent said" has
    /// to look past it or every card shows the same static string forever.
    func testLastMeaningfulLineSkipsComposerAndFooter() {
        let rendered = rows(
            "Applied the patch to OutputHeuristics.swift",
            "╭────────╮", "│ >      │", "╰────────╯",
            claudeFooter
        )
        XCTAssertEqual(
            rendered.lastMeaningfulLine,
            "Applied the patch to OutputHeuristics.swift"
        )
    }

    func testResizeIsMirroredIntoTheRenderedWidth() {
        let shadow = ShadowScreen(columns: 120, rows: 30)
        shadow.feed("hello")
        XCTAssertEqual(shadow.snapshot().columns, 120)

        shadow.resize(columns: 60, rows: 20)
        XCTAssertEqual(shadow.snapshot().columns, 60)
        XCTAssertEqual(shadow.snapshot().rows.count, 20)
    }

    func testRevisionAdvancesOnFeedAndResize() {
        let shadow = ShadowScreen(columns: 80, rows: 24)
        let start = shadow.revision
        shadow.feed("a")
        XCTAssertGreaterThan(shadow.revision, start)

        let afterFeed = shadow.revision
        shadow.feed("")                       // nothing to do
        XCTAssertEqual(shadow.revision, afterFeed)

        shadow.resize(columns: 100, rows: 24)
        XCTAssertGreaterThan(shadow.revision, afterFeed)
    }

    /// Synchronized output (DECSET 2026) arms a watchdog on the *main* queue
    /// that would otherwise mutate this terminal from the wrong thread. The
    /// frame is closed on the feeding thread instead.
    func testSynchronizedOutputFrameIsClosedOnFeed() {
        let shadow = ShadowScreen(columns: 80, rows: 24)
        shadow.feed("\u{1b}[?2026hpartial redraw")
        XCTAssertFalse(shadow.snapshot().rows.isEmpty)
    }

    // MARK: - Escape sequences

    func testStripANSIRemovesColourAndTitles() {
        let coloured = "\u{1b}[31mError: boom\u{1b}[0m\n"
        XCTAssertEqual(OutputHeuristics.stripANSI(coloured), "Error: boom\n")

        let titled = "\u{1b}]0;my title\u{07}hello"
        XCTAssertEqual(OutputHeuristics.stripANSI(titled), "hello")
    }

    // MARK: - Persistence

    func testUnknownStateSurvivesCoding() throws {
        let data = try JSONEncoder().encode(AgentState.unknown)
        XCTAssertEqual(try JSONDecoder().decode(AgentState.self, from: data), .unknown)
    }
}
