import Foundation

/// Reading an agent's terminal output for what it says about the agent's state.
///
/// This exists because of one mistake made four times. Each adapter used to
/// match against the whole retained transcript, so a single occurrence of a word
/// like "failed" — in a test log, in a file the agent was reading, in its own
/// explanation of what went wrong — pinned that session to `.error` for the rest
/// of its life. The dashboard then lied for as long as the session lasted.
///
/// Three rules follow from that:
///
/// 1. **Only the tail is evidence.** What an agent printed a thousand lines ago
///    is history, not status.
/// 2. **Escape codes are not text.** Agent TUIs redraw in place, so the raw
///    buffer is mostly cursor movement and colour. Matching against it matches
///    the wrong things.
/// 3. **Say `.unknown` when it is unknown.** Every adapter used to fall through
///    to `.ready`, which made "I can't tell" indistinguishable from "waiting for
///    you". A wrong "ready" invites you to interrupt something mid-thought —
///    exactly the mistake this branch exists to prevent.
public enum OutputHeuristics {

    /// How many trailing lines count as "now".
    public static let windowLines = 24

    // MARK: - Window

    /// The last `lines` non-empty lines of `buffer`, with escape sequences
    /// removed and carriage-return redraws collapsed.
    public static func recentWindow(_ buffer: String, lines: Int = windowLines) -> String {
        let cleaned = stripANSI(buffer)

        // A TUI redrawing a line sends `\r` and overwrites. Only what came after
        // the last `\r` was ever visible.
        let visible = cleaned
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { segment -> Substring in
                segment.split(separator: "\r", omittingEmptySubsequences: false).last ?? segment
            }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        return visible.suffix(lines).joined(separator: "\n")
    }

    /// Strips CSI (`ESC [ … final`), OSC (`ESC ] … BEL`/`ST`) and two-character
    /// escape sequences, leaving the text a human would have seen.
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

    /// The last line with any content — where a prompt would be if there is one.
    public static func lastVisibleLine(_ window: String) -> String {
        window
            .split(separator: "\n", omittingEmptySubsequences: false)
            .last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            ?? ""
    }

    // MARK: - Signals
    //
    // Each takes an already-windowed, already-lowercased string.

    public static func indicatesRateLimit(_ window: String) -> Bool {
        matches(window, #"rate[-\s]?limit"#)
            || matches(window, #"\busage limit\b"#)
            || matches(window, #"\btoo many requests\b"#)
    }

    /// Only patterns that mean *the agent itself* is broken.
    ///
    /// Deliberately narrow. An agent printing the word "error" is usually just
    /// doing its job — reading a stack trace, running a failing test, explaining
    /// a bug. That is not the session being in an error state. The old
    /// unanchored `failed` match is gone for this reason.
    public static func indicatesFailure(_ window: String) -> Bool {
        matches(window, #"(?m)^\s*(fatal )?error[:\s]"#)
            || matches(window, #"\bcommand not found\b"#)
            || matches(window, #"\b(econnrefused|enotfound|etimedout|econnreset)\b"#)
            || matches(window, #"\b(invalid api key|authentication failed|unauthorized)\b"#)
            || matches(window, #"(?m)^\s*panic:"#)
            || matches(window, #"\btraceback \(most recent call last\)"#)
    }

    public static func indicatesWorking(_ window: String) -> Bool {
        // The strongest signal any of these CLIs give: they tell you how to stop
        // them precisely while they are busy.
        matches(window, #"\besc to interrupt\b"#)
            || matches(window, #"\bctrl\+?c to (interrupt|stop|cancel)\b"#)
            || matches(window, #"\b(thinking|processing|working|analyzing|generating|running)\b"#)
            || containsSpinner(window)
    }

    /// A trailing line that looks like an idle input prompt.
    public static func endsWithPrompt(_ window: String) -> Bool {
        let last = lastVisibleLine(window)
        guard !last.isEmpty else { return false }

        // A bare prompt character, optionally inside a TUI input box border.
        // Anything typed after it means a command is in flight, not idle.
        return matches(last, #"^[│|╰─\s]*[>❯$#»]\s*$"#)
    }

    private static let spinnerFrames = Set("⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏◐◓◑◒✻✽✢")

    private static func containsSpinner(_ window: String) -> Bool {
        // A spinner only means "working" if it is on the line still being drawn.
        lastVisibleLine(window).contains { spinnerFrames.contains($0) }
    }

    private static func matches(_ haystack: String, _ pattern: String) -> Bool {
        haystack.range(of: pattern, options: [.regularExpression]) != nil
    }

    // MARK: - Shared resolution

    /// The order matters and is not the order the old code used.
    ///
    /// Rate limit first — it is unambiguous and actionable. Then *working*,
    /// before failure: an agent narrating an error it is currently fixing is
    /// working, not broken. Failure only for the narrow patterns above. Then the
    /// adapter's own idea of an idle prompt. Then `.unknown`, honestly.
    public static func resolve(
        window: String,
        isReady: (String) -> Bool
    ) -> AgentState {
        if indicatesRateLimit(window) { return .rateLimited }
        if indicatesWorking(window) { return .working }
        if indicatesFailure(window) { return .error("Detected failure in recent output") }
        if isReady(window) { return .ready }
        return .unknown
    }
}
