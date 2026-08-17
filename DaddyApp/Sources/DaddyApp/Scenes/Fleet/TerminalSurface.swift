import SwiftUI
import SwiftTerm
import DaddyCore

// MARK: - Terminal Surface
//
// SwiftTerm's `TerminalView` used as a **renderer only**.
//
// Deliberately not `LocalProcessTerminalView`: that class spawns and owns its
// own child process, which would give us two process paths — one in DaddyCore
// and one in the view — and DaddyCore would stop being the source of truth for
// anything on screen. Instead `SessionManager` owns the pty via `PTYProcess`,
// and this view only draws bytes and forwards keystrokes.
//
//   PTYProcess ──chunk callback──▶ Terminal.feed()   (output)
//   TerminalView ──delegate.send──▶ PTYProcess.write (input)
//   TerminalView ──delegate.sizeChanged──▶ PTYProcess.resize (TIOCSWINSZ)

struct TerminalSurface: NSViewRepresentable {
    let pty: PTYProcess

    /// `DaddyTheme.terminalSurface` as AppKit sees it. Same `#0d111a`, so the
    /// emulator's ground and the SwiftUI pane behind it are one flat colour
    /// with no seam where the padding ends.
    private static let surfaceColor = NSColor(
        srgbRed: 0x0d / 255, green: 0x11 / 255, blue: 0x1a / 255, alpha: 1
    )

    func makeCoordinator() -> Coordinator {
        Coordinator(pty: pty)
    }

    func makeNSView(context: Context) -> TerminalView {
        let view = DroppableTerminalView(
            frame: CGRect(x: 0, y: 0, width: 640, height: 480),
            font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        )

        view.terminalDelegate = context.coordinator

        // Dropping a file types its path, exactly as Terminal.app and iTerm2
        // do. The agent on the other end just sees a path arrive in its input.
        view.onDropFiles = { [weak coordinator = context.coordinator] urls in
            MainActor.assumeIsolated { coordinator?.insertDroppedFiles(urls) }
        }

        // Opaque, deliberately.
        //
        // This was `.clear`, to let the panel's Liquid Glass show through. The
        // cost was invisible and enormous: SwiftTerm clears each dirty rect to
        // transparent and relies on the layer's background colour showing
        // through for default-background cells, so with a clear layer every
        // repaint punched a hole straight down to the glass — which then had to
        // re-blur an aurora that animates at 30Hz — and CoreText had no known
        // ground to antialias glyphs against.
        //
        // Glass belongs to the panels, the sidebar and the chrome. The terminal
        // is a terminal.
        view.nativeBackgroundColor = Self.surfaceColor
        view.nativeForegroundColor = NSColor.white.withAlphaComponent(0.92)
        view.caretColor = NSColor.white.withAlphaComponent(0.75)
        view.allowMouseReporting = true

        // Option is a compose/AltGr layer, not Meta.
        //
        // On non-US layouts Option is how you type characters the base layout
        // has no key for — Spanish Option+2 is "@", and without it you cannot
        // write an email address, an npm scope, or a git remote. With
        // optionAsMetaKey on, SwiftTerm takes the Meta path and sends ESC plus
        // `charactersIgnoringModifiers`, which is the *base* glyph ("2"), so
        // the composed "@" is discarded before macOS ever produces it.
        //
        // Off matches every mainstream macOS terminal's default (Terminal.app,
        // iTerm2, Ghostty) and enables SwiftTerm's AltGr path, which sends the
        // composed text directly. Meta bindings — Option+B/F word jumps and the
        // Emacs family — are the cost; Cmd+Option+O toggles this at runtime for
        // anyone who wants them back.
        view.optionAsMetaKey = false

        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ view: TerminalView, context: Context) {
        // If the pane is pointed at a different session, rebind the stream.
        context.coordinator.rebindIfNeeded(to: pty, view: view)
    }

    static func dismantleNSView(_ view: TerminalView, coordinator: Coordinator) {
        coordinator.detach()
    }

    // MARK: - Coordinator

    /// Mutable state is only ever touched on the main actor; the one method
    /// reachable from `PTYProcess`'s background queue (`handleChunk`) does
    /// nothing but hop straight back to main.
    final class Coordinator: NSObject, TerminalViewDelegate, @unchecked Sendable {
        @MainActor private var pty: PTYProcess
        @MainActor private weak var view: TerminalView?
        @MainActor private var isAttached = false

        /// Output accumulated since the last flush. Written from the pty queue,
        /// drained on main.
        private let pendingLock = NSLock()
        private var pending = ""
        private var flushScheduled = false

        /// Identifies which pty a delivered chunk belongs to, so output from a
        /// session we have since switched away from is discarded rather than
        /// painted into the wrong terminal.
        private let generationLock = NSLock()
        private var generation: Int = 0

        /// Whether this agent brackets its frames with DECSET 2026
        /// (synchronized output). Latched true the first time we see it and
        /// never re-examined — see `flushPending` for what it decides.
        @MainActor private var usesFrameSync = false

        /// `ESC [ ? 2026 h` — "a frame starts here".
        private static let frameSyncBegin = "\u{1b}[?2026h"

        init(pty: PTYProcess) {
            self.pty = MainActor.assumeIsolated { pty }
        }

        @MainActor
        func attach(to view: TerminalView) {
            self.view = view
            guard !isAttached else { return }
            isAttached = true

            generationLock.lock()
            generation += 1
            let currentGeneration = generation
            generationLock.unlock()

            // Tell the child how big it really is, straight away.
            //
            // `PTYProcess` starts at a fixed 120×30 because the pty exists
            // before any view does. A TUI lays out its first frame against
            // whatever it is told at startup, so if the pane is a different
            // shape that frame is drawn wrong and stays wrong until something
            // else triggers a resize. `sizeChanged` only fires when the size
            // *changes*, which may be never.
            let size = view.getTerminal().getDims()
            pty.resize(columns: UInt16(size.cols), rows: UInt16(size.rows))

            // Replay what the session already produced, so selecting a session
            // mid-flight does not show an empty pane.
            let backlog = pty.recentOutput
            if !backlog.isEmpty {
                view.getTerminal().feed(text: backlog)
                // Seed the frame-sync latch from what the session has already
                // said, so re-opening a Claude/Codex/OpenCode session does not
                // spend its first frames being repainted by hand.
                if backlog.contains(Self.frameSyncBegin) { usesFrameSync = true }
            }

            // The chunk callback, not registerOutputCallback — the latter
            // re-sends the entire retained buffer on every write, which would
            // duplicate the whole transcript into the renderer each time.
            pty.registerChunkCallback { [weak self] text in
                self?.handleChunk(text, generation: currentGeneration)
            }

            takeKeyboardFocus(view)
        }

        /// Puts the caret in the terminal, since that is where you talk to the
        /// agent. Deferred by one turn because the view is not in a window yet
        /// when it is first made.
        @MainActor
        private func takeKeyboardFocus(_ view: TerminalView) {
            DispatchQueue.main.async {
                view.window?.makeFirstResponder(view)
            }
        }

        /// Called on `PTYProcess`'s private serial queue.
        ///
        /// Chunks are accumulated and flushed at most once per frame rather than
        /// fed one at a time. A TUI redrawing its viewport — OpenCode does this
        /// on every scroll step — emits a burst of small writes, and giving each
        /// one its own hop to main and its own full repaint made scrolling tear
        /// line by line. One flush per frame bounds the repaints no matter how
        /// chatty the agent is, and hands the parser bigger blocks besides.
        private func handleChunk(_ text: String, generation incoming: Int) {
            generationLock.lock()
            let isCurrent = incoming == generation
            generationLock.unlock()
            guard isCurrent else { return }

            pendingLock.lock()
            pending += text
            let alreadyScheduled = flushScheduled
            flushScheduled = true
            pendingLock.unlock()

            guard !alreadyScheduled else { return }

            DispatchQueue.main.asyncAfter(deadline: .now() + Self.flushInterval) { [weak self] in
                MainActor.assumeIsolated { self?.flushPending() }
            }
        }

        /// One frame at 60Hz. Long enough to coalesce a redraw burst, short
        /// enough that typing still feels immediate.
        private static let flushInterval: TimeInterval = 1.0 / 60.0

        @MainActor
        private func flushPending() {
            pendingLock.lock()
            let text = pending
            pending = ""
            flushScheduled = false
            pendingLock.unlock()

            guard !text.isEmpty, let view else { return }

            view.getTerminal().feed(text: text)

            // Whether we repaint by hand depends on whether the agent tells us
            // where its frames are.
            //
            // `feed` schedules its own repaint via `queuePendingDisplay`, and
            // that repaint is *surgical*: only the rows `getUpdateRange()`
            // marked dirty, coalesced at 60Hz, and suppressed while the
            // terminal is inside a DECSET 2026 synchronized-output frame. For
            // an agent that brackets its frames with 2026 — Claude, Codex and
            // OpenCode all do — that is exactly right, and forcing a
            // whole-window repaint on top of it is what made their text flash:
            // SwiftTerm clears a rect before painting it, so a full-view
            // repaint that misses the frame deadline is presented
            // cleared-but-not-yet-drawn.
            //
            // Cursor announces no frames at all. Its private modes are 25,
            // 1004, 2004 and 2031 — no 2026 — and it redraws by erasing and
            // rewinding: `ESC[2K ESC[1A` ten times, then reprinting ten lines,
            // about four times a second. Row-level invalidation does not cover
            // everything that pattern changes on screen, and left to it Cursor
            // renders garbage. It needs the full repaint.
            //
            // So: latch onto 2026 the first time we see it and stop nudging
            // forever after. Agents that sync their frames keep SwiftTerm's
            // surgical path; agents that do not get one full repaint per flush.
            // And a flush is a whole frame for Cursor — its ten-line redraw
            // arrives in a single ~900 byte chunk — so this repaints once per
            // frame rather than mid-frame.
            guard !usesFrameSync else { return }

            if text.contains(Self.frameSyncBegin) {
                usesFrameSync = true
            } else {
                view.setNeedsDisplay(view.bounds)
            }
        }

        @MainActor
        func rebindIfNeeded(to newPTY: PTYProcess, view: TerminalView) {
            guard newPTY !== pty else { return }

            // Anything buffered belongs to the session being left behind.
            pendingLock.lock()
            pending = ""
            pendingLock.unlock()

            pty = newPTY
            isAttached = false
            // A different session may be a different agent with a different
            // idea about frame synchronization, so the latch resets with it.
            usesFrameSync = false
            view.getTerminal().resetToInitialState()
            attach(to: view)
        }

        @MainActor
        func detach() {
            view = nil
        }

        // MARK: Dropped files

        /// Types the dropped paths into the agent, the way a terminal does.
        ///
        /// Paths are backslash-escaped even though the receiver is a TUI input
        /// box rather than a shell. That is deliberate: it is byte-for-byte
        /// what these CLIs receive when someone drags a file into iTerm2 or
        /// Terminal.app, so it is the form they are all written against. A path
        /// with nothing special in it comes through untouched either way.
        @MainActor
        func insertDroppedFiles(_ urls: [URL]) {
            guard !urls.isEmpty else { return }

            // Trailing space so the next word you type is a new one.
            let paths = urls.map { Self.escaped($0.path) }.joined(separator: " ") + " "

            // Wrapped as a paste when the agent asked for bracketed paste, so a
            // path is delivered as one pasted unit instead of a burst of
            // keystrokes its input handler has to interpret one at a time.
            let payload: String
            if view?.getTerminal().bracketedPasteMode == true {
                payload = "\u{1b}[200~" + paths + "\u{1b}[201~"
            } else {
                payload = paths
            }

            try? pty.write(payload)
        }

        /// Characters a shell would otherwise act on. Spelled out one per
        /// entry rather than as a string literal, because a literal is exactly
        /// where a stray `\t` stops meaning tab and starts meaning "escape
        /// every letter t in the path".
        private static let escapees: Set<Character> = [
            " ", "\t", "\n", "\"", "'", "`", "\\", "$", "&", "|", ";",
            "<", ">", "(", ")", "[", "]", "{", "}", "*", "?", "!", "#", "~", "^",
        ]

        private static func escaped(_ path: String) -> String {
            var out = ""
            out.reserveCapacity(path.count)
            for character in path {
                if escapees.contains(character) { out.append("\\") }
                out.append(character)
            }
            return out
        }

        // MARK: TerminalViewDelegate

        // The view always calls its delegate on the main thread, but the
        // protocol is not annotated, hence the explicit assumption.

        /// Keystrokes from the view go into the pty.
        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            guard let text = String(bytes: data, encoding: .utf8) else { return }
            MainActor.assumeIsolated { try? pty.write(text) }
        }

        /// The child needs to know the new geometry or it will not re-wrap.
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            MainActor.assumeIsolated {
                pty.resize(columns: UInt16(newCols), rows: UInt16(newRows))
            }
        }

        func setTerminalTitle(source: TerminalView, title: String) {}

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func scrolled(source: TerminalView, position: Double) {}

        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            guard let url = URL(string: link) else { return }
            NSWorkspace.shared.open(url)
        }

        func bell(source: TerminalView) {}

        func clipboardCopy(source: TerminalView, content: Data) {
            guard let text = String(data: content, encoding: .utf8) else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }

        func clipboardRead(source: TerminalView) -> Data? {
            NSPasteboard.general.string(forType: .string).map { Data($0.utf8) }
        }

        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    }
}
