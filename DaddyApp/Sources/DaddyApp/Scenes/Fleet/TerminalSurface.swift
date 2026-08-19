import SwiftUI
import SwiftTerm
import QuartzCore
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

    /// Whether this surface is the one on screen. Several can be mounted at
    /// once — the shell pane keeps every tab alive — and only the visible one
    /// should hold the caret.
    var isActive = true

    /// Whether to ask the child to repaint once, after the first real resize.
    /// True only for a plain shell; see `Coordinator.scheduleFirstRedraw`.
    var redrawsOnFirstAttach = false

    /// `DaddyTheme.terminalSurface` as AppKit sees it. Same `#0d111a`, so the
    /// emulator's ground and the SwiftUI pane behind it are one flat colour
    /// with no seam where the padding ends.
    private static let surfaceColor = NSColor(
        srgbRed: 0x0d / 255, green: 0x11 / 255, blue: 0x1a / 255, alpha: 1
    )

    func makeCoordinator() -> Coordinator {
        Coordinator(
            pty: pty,
            // Passed in rather than defaulted, because every tab's surface is
            // built in the same pass: a background tab that started out
            // "active" would grab first responder on creation and only be told
            // otherwise on the next update, by which time the deferred focus
            // has already landed in the wrong shell.
            isActive: isActive,
            redrawsOnFirstAttach: redrawsOnFirstAttach
        )
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

        // Clicking a tab should put the caret in that shell. Only the surface
        // that just became active claims focus — the others are mounted, not
        // shown, and must not fight over first responder every update.
        context.coordinator.setActive(isActive, view: view)
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
        @MainActor private var controlCMonitor: Any?
        @MainActor private var scrollMonitor: Any?

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

        /// The registration this coordinator holds on `pty`, so it can be
        /// taken back. Without it every attach left a live closure behind on a
        /// pty that outlives the view — see `detach`.
        @MainActor private var chunkToken: UUID?

        /// The size last reported to the child, and the work item that will
        /// report the next one. See `sizeChanged`.
        @MainActor private var lastReportedSize: (cols: Int, rows: Int)?
        @MainActor private var pendingResize: DispatchWorkItem?

        private let redrawsOnFirstAttach: Bool

        /// Whether this surface is the one on screen, and therefore the one
        /// entitled to the caret.
        @MainActor private var isActive: Bool

        init(
            pty: PTYProcess,
            isActive: Bool,
            redrawsOnFirstAttach: Bool
        ) {
            self.pty = MainActor.assumeIsolated { pty }
            self.isActive = MainActor.assumeIsolated { isActive }
            self.redrawsOnFirstAttach = redrawsOnFirstAttach
        }

        @MainActor
        func attach(to view: TerminalView) {
            self.view = view
            installControlCMonitor(for: view)
            installScrollMonitor(for: view)
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
            lastReportedSize = (size.cols, size.rows)
            pty.resize(columns: UInt16(size.cols), rows: UInt16(size.rows))

            // Replay what the session already produced, so selecting a session
            // mid-flight does not show an empty pane. Through the *view*, for
            // the reason spelled out in `flushPending`.
            let backlog = pty.recentOutput
            if !backlog.isEmpty {
                view.feed(text: backlog)
            }

            // The chunk callback, not registerOutputCallback — the latter
            // re-sends the entire retained buffer on every write, which would
            // duplicate the whole transcript into the renderer each time.
            chunkToken = pty.registerChunkCallback { [weak self] text in
                self?.handleChunk(text, generation: currentGeneration)
            }

            scheduleFirstRedraw()

            if isActive { takeKeyboardFocus(view) }
        }

        /// One Ctrl-L, once, to a child that has only just started.
        ///
        /// The pty exists before any view does, so it launches at a fixed
        /// 120×30 and the shell prints its prompt at that width — a powerline
        /// prompt in a 55-column pane arrives wrapped across two lines with the
        /// caret stranded below it. The resize above fixes the *geometry*, but
        /// nothing unprints what has already been drawn.
        ///
        /// zsh, bash and fish all bind Ctrl-L to clear-and-redraw, which does
        /// both: the mis-wrapped fragment goes, the prompt comes back at the
        /// right width. `consumeFreshLaunchRedraw` returns true exactly once per
        /// launch, so this can never fire over output worth keeping.
        ///
        /// Delayed, because a login shell is still sourcing `.zprofile` and
        /// `.zshrc` at this point and zle is not yet reading. A quarter of a
        /// second is long past that and still before anyone has typed.
        ///
        /// **Shells only.** To a TUI agent Ctrl-L is not a redraw — they bind it
        /// themselves, and Claude Code treats it as clear-the-conversation — so
        /// `redrawsOnFirstAttach` is false everywhere except the shell pane.
        @MainActor
        private func scheduleFirstRedraw() {
            guard redrawsOnFirstAttach, pty.consumeFreshLaunchRedraw() else { return }
            let target = pty
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                try? target.write("\u{0c}")
            }
        }

        @MainActor
        func setActive(_ active: Bool, view: TerminalView) {
            guard active != isActive else { return }
            isActive = active
            if active { takeKeyboardFocus(view) }
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
        /// Chunks are accumulated and handed over on the **next turn of the
        /// main runloop** — coalesced, but not delayed.
        ///
        /// Batching matters: a TUI redrawing its viewport emits a burst of small
        /// writes, and one `feed` per write is one parse and one repaint request
        /// each. Everything that arrives before the flush runs is merged into a
        /// single feed.
        ///
        /// **The delay is what had to go.** This used to hold chunks for a
        /// sixtieth of a second before feeding them, on the theory that a
        /// terminal should not repaint faster than the screen. But SwiftTerm
        /// already coalesces at exactly 60Hz — `queuePendingDisplay` starts its
        /// countdown when the bytes arrive and refuses to paint inside a
        /// synchronized-output frame — so ours was a second clock running at the
        /// same rate, started from a different instant. Two 60Hz clocks in
        /// arbitrary phase do not halve the work; they beat against each other,
        /// and a paint that lands between two halves of a frame we ourselves
        /// split shows half of the old frame and half of the new. Which is what
        /// tearing is. The only clock now is SwiftTerm's, and it starts counting
        /// the moment the bytes get there.
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

            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.flushPending() }
            }
        }

        @MainActor
        private func flushPending() {
            pendingLock.lock()
            let text = pending
            pending = ""
            flushScheduled = false
            pendingLock.unlock()

            guard !text.isEmpty, let view else { return }

            // Through the **view**, never `view.getTerminal().feed(...)`.
            //
            // `TerminalView.feed(text:)` is `feedPrepare()` → `terminal.feed`
            // → `feedFinish()`, and `feedFinish` is the only output-driven
            // repaint scheduler SwiftTerm has: `displayImmediately()` when the
            // user has just typed — `TerminalView.send(data:)` stamps that
            // window before our delegate ever sees the keystroke — and
            // `queuePendingDisplay()` otherwise, which invalidates only the
            // rows `getUpdateRange()` marked dirty, coalesces at 60Hz, and
            // holds off inside a DECSET 2026 synchronized-output frame.
            //
            // Feeding the emulator directly skips both halves, so output
            // scheduled *no repaint at all*. What used to stand in for it was
            // a hand-rolled `view.setNeedsDisplay(view.bounds)` per flush,
            // latched off for agents that announce 2026 frames — which meant a
            // plain shell, announcing none and opting out of the manual
            // repaint, never painted on its own at all, and Claude, announcing
            // them, was left depending on `synchronizedOutputChanged` alone:
            // that queues a paint 16.67ms out, and `updateDisplay` returns
            // early — clearing `pendingDisplay` without re-queuing — if the
            // next frame opens inside the window. Under sustained output those
            // paints are dropped and rows keep stale pixels.
            //
            // So there is no repaint code here any more. There should not be.
            view.feed(text: text)
        }

        @MainActor
        func rebindIfNeeded(to newPTY: PTYProcess, view: TerminalView) {
            guard newPTY !== pty else { return }

            // Anything buffered belongs to the session being left behind, and
            // so does the registration on it.
            pendingLock.lock()
            pending = ""
            pendingLock.unlock()

            if let chunkToken {
                pty.removeChunkCallback(chunkToken)
                self.chunkToken = nil
            }

            pty = newPTY
            isAttached = false
            lastReportedSize = nil
            view.getTerminal().resetToInitialState()
            attach(to: view)
        }

        @MainActor
        func detach() {
            // The pty outlives the view — an agent keeps running while you look
            // at another one — so a registration left behind here is a closure
            // that appends to a string and schedules a main-queue hop for every
            // chunk, forever, once per time this surface was ever built.
            if let chunkToken {
                pty.removeChunkCallback(chunkToken)
                self.chunkToken = nil
            }

            pendingResize?.cancel()
            pendingResize = nil

            view = nil
            if let controlCMonitor {
                NSEvent.removeMonitor(controlCMonitor)
                self.controlCMonitor = nil
            }
            if let scrollMonitor {
                NSEvent.removeMonitor(scrollMonitor)
                self.scrollMonitor = nil
            }
        }

        /// The wheel scrolls *our* scrollback unless the child owns the screen.
        ///
        /// SwiftTerm's `scrollWheel` asks whether mouse reporting is on before
        /// it asks which buffer is active, so any child that turns mouse
        /// tracking on takes the wheel with it — including ones that print
        /// normally and leave a scrollback behind them. Scrolling back through
        /// what such an agent said did nothing at all, because the events were
        /// going to a program that had not asked to be scrolled.
        ///
        /// In the alternate screen there is no scrollback of ours to move and
        /// the child is drawing the whole viewport itself, so there the wheel is
        /// genuinely its business — Claude Code runs there with full mouse
        /// tracking (`?1049h ?1000h ?1002h ?1003h ?1006h`) and keeps every
        /// event. Everywhere else the terminal scrolls, which is what
        /// Terminal.app, iTerm2 and Ghostty all do.
        ///
        /// Done from a monitor rather than an override because SwiftTerm's
        /// `scrollWheel` is `public`, not `open`. The flag is put back on the
        /// next turn of the runloop, by which time this one event has been
        /// dispatched.
        @MainActor
        private func installScrollMonitor(for view: TerminalView) {
            guard scrollMonitor == nil else { return }
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
                [weak view] event in
                guard let view, event.window === view.window else { return event }

                let point = view.convert(event.locationInWindow, from: nil)
                guard view.bounds.contains(point) else { return event }
                guard view.allowMouseReporting,
                      !view.getTerminal().isCurrentBufferAlternate
                else { return event }

                view.allowMouseReporting = false
                DispatchQueue.main.async { view.allowMouseReporting = true }
                return event
            }
        }

        /// Observe the original AppKit key event while this terminal is first
        /// responder. SwiftTerm's `keyDown` implementation is not open to
        /// subclassing, and inspecting its delegate bytes is too late once a
        /// TUI has enabled Kitty/CSI-u keyboard reporting.
        @MainActor
        private func installControlCMonitor(for view: TerminalView) {
            guard controlCMonitor == nil else { return }
            controlCMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
                [weak self, weak view] event in
                guard view?.window?.firstResponder === view else { return event }

                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let isPlainControl = modifiers.contains(.control)
                    && !modifiers.contains(.command)
                    && !modifiers.contains(.option)
                if isPlainControl,
                   event.charactersIgnoringModifiers?.lowercased() == "c" {
                    self?.noteControlCInput()
                }
                return event
            }
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

        /// Capture intent before SwiftTerm turns the key into legacy, Kitty, or
        /// CSI-u bytes. The PTY still receives SwiftTerm's original encoding;
        /// this only annotates a subsequent process exit for UI cleanup.
        @MainActor
        private func noteControlCInput() {
            pty.noteInterruptInput()
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

        /// The child needs to know the new geometry or it will not re-wrap —
        /// but only once it has stopped changing.
        ///
        /// Every pane in the workspace is positioned by hand and animated, so a
        /// single toggle in or out of focus mode walks both terminals through a
        /// dozen intermediate widths over 300ms. Passed straight through, each
        /// one is a `TIOCSWINSZ`, a `SIGWINCH` and a full reflow at the far end
        /// — of a geometry that is already out of date by the time the TUI has
        /// finished laying out for it. Coalesced, an animation costs exactly one
        /// resize, at the size it settles on.
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            MainActor.assumeIsolated {
                guard lastReportedSize?.cols != newCols
                    || lastReportedSize?.rows != newRows
                else { return }

                pendingResize?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.pendingResize = nil
                        self.lastReportedSize = (newCols, newRows)
                        self.pty.resize(columns: UInt16(newCols), rows: UInt16(newRows))
                    }
                }
                pendingResize = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
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
