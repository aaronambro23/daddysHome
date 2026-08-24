import Foundation
import SwiftTerm

/// What an agent's terminal is showing, as a person looking at it would see.
public struct ScreenSnapshot: Sendable, Equatable {

    /// The viewport, top row first, trailing blanks trimmed off each row.
    /// Blank rows are kept — they are structure, not noise.
    public let rows: [String]
    public let cursorRow: Int
    public let cursorColumn: Int
    /// True while the agent is drawing in the alternate buffer, i.e. a
    /// full-screen mode that replaced whatever was on screen before.
    public let isAlternateScreen: Bool
    public let columns: Int

    public init(
        rows: [String],
        cursorRow: Int,
        cursorColumn: Int,
        isAlternateScreen: Bool,
        columns: Int
    ) {
        self.rows = rows
        self.cursorRow = cursorRow
        self.cursorColumn = cursorColumn
        self.isAlternateScreen = isAlternateScreen
        self.columns = columns
    }

    public static let empty = ScreenSnapshot(
        rows: [],
        cursorRow: 0,
        cursorColumn: 0,
        isAlternateScreen: false,
        columns: 0
    )

    public var isEmpty: Bool { visibleRows.isEmpty }

    /// Rows with anything on them, top to bottom.
    public var visibleRows: [String] {
        rows.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// The bottom `count` non-empty rows, joined into one string.
    ///
    /// Joined rather than matched row by row because the shadow mirrors the
    /// real pane width: in a narrow split, a footer like
    /// `⏵⏵ accept edits on (shift+tab to cycle)` wraps onto a second row, and a
    /// per-row match would miss it entirely. A marker split mid-*word* still
    /// misses, which is why nothing depends on catching it in a single frame.
    public func tail(_ count: Int) -> String {
        visibleRows.suffix(count).joined(separator: " ")
    }

    /// The last thing the agent actually said, ignoring the chrome it keeps
    /// permanently pinned to the bottom of the screen.
    ///
    /// Taking the literal bottom row would return Claude's mode footer forever
    /// — the same static string on every card, which is worse than the byte
    /// stream this replaced.
    public var lastMeaningfulLine: String {
        for row in visibleRows.reversed() {
            let line = row.trimmingCharacters(in: .whitespaces)
            if Self.isChrome(line) { continue }
            return line
        }
        return ""
    }

    /// Composer borders, mode footers and bare prompts: present whatever the
    /// agent is doing, and therefore never news.
    static func isChrome(_ line: String) -> Bool {
        if line.isEmpty { return true }
        if line.range(of: #"^[─│╭╮╰╯├┤┬┴┼╌━┃┏┓┗┛▔▁\s]*$"#, options: .regularExpression) != nil {
            return true
        }
        // Tolerates a boxed composer: `│ >                    │`. Kept in step
        // with `OutputHeuristics.endsWithPrompt`, which asks the same question.
        if line.range(of: #"^[│|╰─\s]*[>❯$#»]\s*[│|]?\s*$"#, options: .regularExpression) != nil {
            return true
        }
        let lowered = line.lowercased()
        return lowered.contains("shift+tab to cycle")
            || lowered.contains("? for shortcuts")
            || lowered.contains("for shortcuts")
    }
}

/// A headless terminal emulator that exists only to answer "what is on screen".
///
/// State detection used to pattern-match the raw PTY byte stream. Agent TUIs
/// redraw by moving the cursor and erasing lines rather than by printing
/// newlines, so stripping escape codes out of that stream leaves every *erased*
/// repaint behind as ordinary text. A 24-line window over it therefore held a
/// dozen stale copies of `esc to interrupt` long after the agent had stopped —
/// which is exactly why WORKING latched and never cleared.
///
/// This is the same emulator the visible pane already uses, running with no
/// renderer attached. A line erased here is actually gone.
///
/// **Not thread-safe.** SwiftTerm's `Terminal` has no internal locking, so the
/// owner serialises every call into it — see `PTYProcess.screenLock`.
final class ShadowScreen {

    private let terminal: Terminal
    private let delegate: SilentTerminalDelegate

    /// Bumped on every feed and resize, so a caller can tell "nothing has
    /// happened since I last looked" without rendering anything.
    private(set) var revision: UInt64 = 0

    init(columns: Int, rows: Int) {
        let delegate = SilentTerminalDelegate()
        self.delegate = delegate
        self.terminal = Terminal(
            delegate: delegate,
            options: TerminalOptions(
                cols: max(2, columns),
                rows: max(1, rows),
                // Only the viewport is ever read. Scrollback would be retained
                // per session for nothing.
                scrollback: 0,
                // The default is 320MB per terminal, and this one will never
                // display an image.
                kittyImageCacheLimitBytes: 1
            )
        )
    }

    func feed(_ text: String) {
        guard !text.isEmpty else { return }
        terminal.feed(text: text)

        // DECSET 2026 (synchronized output) arms a one-second watchdog that
        // fires on the *main* queue and mutates this terminal — the one object
        // here that must only ever be touched from the owner's queue. Closing
        // the frame now runs that teardown on our thread instead, leaving the
        // watchdog nothing to do but read a Bool and return. Synchronized
        // output is a hint to renderers, and this one has no renderer.
        if terminal.synchronizedOutputActive {
            terminal.feed(text: "\u{1b}[?2026l")
        }

        revision &+= 1
    }

    func resize(columns: Int, rows: Int) {
        terminal.resize(cols: max(2, columns), rows: max(1, rows))
        revision &+= 1
    }

    func snapshot() -> ScreenSnapshot {
        var rows: [String] = []
        rows.reserveCapacity(terminal.rows)
        for row in 0..<terminal.rows {
            rows.append(terminal.getLine(row: row)?.translateToString(trimRight: true) ?? "")
        }

        // `getCursorLocation` is (x, y) — column first.
        let cursor = terminal.getCursorLocation()

        return ScreenSnapshot(
            rows: rows,
            cursorRow: cursor.y,
            cursorColumn: cursor.x,
            isAlternateScreen: terminal.isCurrentBufferAlternate,
            columns: terminal.cols
        )
    }
}

/// The shadow observes; it never answers.
///
/// `send` is the terminal's reply channel for device queries — DA, DSR, CPR.
/// The visible `TerminalSurface` already answers those by writing to the pty,
/// and a second reply arrives at the agent as stray keystrokes in its composer.
/// When no view is attached nobody answers, which is what happened before this
/// existed, so staying silent is also behaviour-preserving.
private final class SilentTerminalDelegate: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {}
}
