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

    func makeCoordinator() -> Coordinator {
        Coordinator(pty: pty)
    }

    func makeNSView(context: Context) -> TerminalView {
        let view = TerminalView(
            frame: CGRect(x: 0, y: 0, width: 640, height: 480),
            font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        )

        view.terminalDelegate = context.coordinator

        // Let the panel's Liquid Glass show through. SwiftTerm otherwise paints
        // an opaque background, which would punch a solid rectangle through the
        // glass — the exact mistake that flattened the original design.
        view.nativeBackgroundColor = .clear
        view.nativeForegroundColor = NSColor.white.withAlphaComponent(0.92)
        view.caretColor = NSColor.white.withAlphaComponent(0.75)
        view.allowMouseReporting = true
        view.optionAsMetaKey = true

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
            view.setNeedsDisplay(view.bounds)
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
            view.getTerminal().resetToInitialState()
            attach(to: view)
        }

        @MainActor
        func detach() {
            view = nil
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
