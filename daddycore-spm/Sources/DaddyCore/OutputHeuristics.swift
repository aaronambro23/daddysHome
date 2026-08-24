import Foundation

/// Reading an agent's terminal for what it says about the agent's state.
///
/// This used to work on the raw PTY byte stream — strip the escape codes, keep
/// the last 24 lines, match patterns against that. It had one fatal flaw, and
/// the flaw survived two rounds of narrowing the patterns.
///
/// Agent TUIs do not redraw by printing newlines. They move the cursor up and
/// erase the line. Strip the escape codes out of that stream and every *erased*
/// repaint is still sitting there as ordinary text — so a "window" over it held
/// a dozen stale copies of `esc to interrupt` long after the agent had stopped
/// talking. WORKING latched and never cleared. Worse, detection only ran when
/// output arrived, and an idle agent produces none: the last verdict was always
/// computed on the tail of the *working* burst, and nothing ever revisited it.
///
/// So the input is now a `ScreenSnapshot` — what the terminal actually shows,
/// rendered by the same emulator that draws the visible pane. An erased line is
/// gone. The bottom of the screen is the bottom of the screen.
///
/// Three rules survive from the old design, and one is new:
///
/// 1. **Only the bottom of the screen is live status.** What is higher up is
///    transcript — things the agent said, including things it said about
///    running and failing.
/// 2. **Say `.unknown` when it is unknown.** A wrong "ready" invites you to
///    interrupt something mid-thought.
/// 3. **Match markers, not vocabulary.** The old `\b(thinking|working|
///    running)\b` matched any agent that used those words in a sentence.
/// 4. **Rows may wrap.** The shadow mirrors the real pane width, so in a narrow
///    split a one-line footer becomes two rows. Bottom-anchored matching joins
///    the rows before looking.
public enum OutputHeuristics {

    /// How many non-empty rows at the bottom count as the live status area.
    ///
    /// Six, because Claude Code's busy screen is five rows before anything
    /// wraps — status line, composer top border, composer, bottom border,
    /// mode footer — and the status line is the top of those. A smaller window
    /// silently drops the one row that says the agent is working.
    public static let tailRows = 6

    // MARK: - Signals

    public static func indicatesRateLimit(_ screen: ScreenSnapshot) -> Bool {
        let all = screen.visibleRows.joined(separator: " ").lowercased()
        return matches(all, #"rate[-\s]?limit"#)
            || matches(all, #"\busage limit\b"#)
            || matches(all, #"\btoo many requests\b"#)
    }

    /// Only patterns that mean *the agent itself* is broken.
    ///
    /// Matched per row, so `^` still anchors to the start of a line — joining
    /// first would quietly turn every anchored pattern into something else.
    public static func indicatesFailure(_ screen: ScreenSnapshot) -> Bool {
        for row in screen.visibleRows {
            let line = row.lowercased()
            if matches(line, #"^\s*(fatal )?error[:\s]"#) { return true }
            if matches(line, #"^\s*panic:"#) { return true }
            if matches(line, #"\bcommand not found\b"#) { return true }
            if matches(line, #"\b(econnrefused|enotfound|etimedout|econnreset)\b"#) { return true }
            if matches(line, #"\b(invalid api key|authentication failed|unauthorized)\b"#) {
                return true
            }
            if matches(line, #"\btraceback \(most recent call last\)"#) { return true }
        }
        return false
    }

    /// Whether the *live status area* says the agent is mid-turn.
    ///
    /// Every one of these is a marker a TUI prints only while it is actually
    /// busy — chiefly the instruction for how to stop it. The old bare-word
    /// list is gone: an agent writing "running the tests now" in prose is not a
    /// status line, and treating it as one is half of why badges stuck.
    public static func indicatesWorking(_ screen: ScreenSnapshot) -> Bool {
        let tail = screen.tail(tailRows).lowercased()

        if matches(tail, #"\besc(ape)? to (interrupt|cancel|stop)\b"#) { return true }
        if matches(tail, #"\bctrl\+?c to (interrupt|stop|cancel)\b"#) { return true }
        if matches(tail, #"\bpress esc\b.*\b(interrupt|cancel|stop)\b"#) { return true }

        // A live status line ends its verb in an ellipsis — "Thinking…",
        // "Working…". Prose does not. The glyph matters: this is U+2026, not
        // three periods.
        if matches(tail, #"\b(thinking|working|processing|analysing|analyzing|generating|running|reading|writing|searching|compacting)…"#) {
            return true
        }

        return containsSpinner(tail)
    }

    /// An idle input prompt somewhere in the live status area.
    ///
    /// Not strictly the last row: agents park a mode footer below the composer,
    /// so the prompt is often second or third from the bottom.
    public static func endsWithPrompt(_ screen: ScreenSnapshot) -> Bool {
        for row in screen.visibleRows.suffix(tailRows) {
            let line = row.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            // Tolerates a boxed composer: `│ >                    │`.
            if matches(line, #"^[│|╰─\s]*[>❯$#»]\s*[│|]?\s*$"#) { return true }
        }
        return false
    }

    /// Braille/arc spinners plus the asterisk frames Claude cycles through.
    ///
    /// Note what is *not* here: `·`. It is a spinner frame in some TUIs, and it
    /// is also the separator in Claude's permanently visible footer
    /// (`(shift+tab to cycle) · ↔ for agents`) — including it pinned every
    /// Claude session to WORKING for its entire life.
    private static let spinnerFrames = Set("⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏◐◓◑◒✻✽✢✳✶")

    private static func containsSpinner(_ tail: String) -> Bool {
        tail.contains { spinnerFrames.contains($0) }
    }

    private static func matches(_ haystack: String, _ pattern: String) -> Bool {
        haystack.range(of: pattern, options: [.regularExpression]) != nil
    }

    // MARK: - Shared resolution

    /// Rate limit first — unambiguous and actionable. Then *working*, before
    /// failure: an agent narrating an error it is currently fixing is working,
    /// not broken. Failure only for the narrow patterns above. Then the
    /// adapter's own idea of idle. Then `.unknown`, honestly.
    public static func resolve(
        screen: ScreenSnapshot,
        isReady: (ScreenSnapshot) -> Bool
    ) -> AgentState {
        if screen.isEmpty { return .unknown }
        if indicatesRateLimit(screen) { return .rateLimited }
        if indicatesWorking(screen) { return .working }
        if indicatesFailure(screen) { return .error("Detected failure in recent output") }
        if isReady(screen) { return .ready }
        return .unknown
    }

    // MARK: - Escape sequences

    /// Strips CSI (`ESC [ … final`), OSC (`ESC ] … BEL`/`ST`) and two-character
    /// escape sequences, leaving the text a human would have seen.
    ///
    /// Kept because it is genuinely useful for turning a captured byte stream
    /// into something readable. It is deliberately **not** used for state
    /// detection any more — see this type's documentation for why that never
    /// worked. `recentWindow` is gone for the same reason: "a window over a
    /// byte stream" is the abstraction that caused the bug, and leaving it here
    /// would invite the bug back.
    public static func stripANSI(_ text: String) -> String {
        guard text.contains("\u{1b}") else { return text }

        var out = String()
        out.reserveCapacity(text.count)

        var i = text.startIndex
        while i < text.endIndex {
            guard text[i] == "\u{1b}" else {
                out.append(text[i])
                i = text.index(after: i)
                continue
            }

            var j = text.index(after: i)
            guard j < text.endIndex else { break }   // trailing lone ESC

            switch text[j] {
            case "[":
                // CSI: parameters and intermediates, then a final byte @-~.
                j = text.index(after: j)
                while j < text.endIndex, !("\u{40}"..."\u{7e}").contains(text[j]) {
                    j = text.index(after: j)
                }
                if j < text.endIndex { j = text.index(after: j) }

            case "]":
                // OSC: runs until BEL or ST (ESC \).
                j = text.index(after: j)
                while j < text.endIndex {
                    if text[j] == "\u{07}" { j = text.index(after: j); break }
                    if text[j] == "\u{1b}" {
                        let k = text.index(after: j)
                        if k < text.endIndex, text[k] == "\\" {
                            j = text.index(after: k)
                            break
                        }
                    }
                    j = text.index(after: j)
                }

            default:
                // Two-character escape.
                j = text.index(after: j)
            }

            i = j
        }

        return out
    }
}
