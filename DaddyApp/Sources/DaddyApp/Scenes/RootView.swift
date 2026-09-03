import SwiftUI
import AppKit

struct RootView: View {
    @Environment(MockStore.self) private var store
    @State private var utilityPanel: UtilityPanel?
    @State private var keyboardMonitor: Any?

    var body: some View {
        ZStack {
            // A ground colour under everything, so nothing shows through in the
            // frame between the aurora leaving and the terminal arriving.
            DaddyTheme.focusSurface
                .ignoresSafeArea()

            // Rendered again in focus mode, and that reverses a decision from
            // batch 009 on purpose.
            //
            // Suppressing it there was justified by one fact: the focused
            // terminal covered the window completely, so the aurora was
            // animating where nobody could see it. The permanent rail ends
            // that — it is glass, it is always on screen, and glass with a flat
            // colour behind it is just a grey box. The backdrop is the design.
            //
            // The performance work that actually mattered survives untouched:
            // the terminal no longer forces a full-window repaint per chunk,
            // and it is opaque, so its repaints do not drag the aurora and the
            // glass through a recomposite.
            AuroraBackground()

            VStack(spacing: 0) {
                ZStack(alignment: .trailing) {
                    // Inset in both modes now. Focus used to run the terminal
                    // to the window edges because it *was* the window; with the
                    // rail permanently beside it, the rail would sit flush
                    // against the frame while every other panel floats.
                    ZStack {
                        // Always mounted, always at a real size, always hit-testable.
                        // Covering this with an `if` plus animation left a ghost
                        // overlay, and `makeFirstResponder(nil)` plus Cursor's
                        // mouse-reporting (clicks never focus) is how typing died.
                        FleetView()

                        if store.workspace == .board {
                            workspaceCover { BoardView() }
                        } else if store.workspace == .orchestrator {
                            workspaceCover { OrchestratorView() }
                        }
                    }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)

                    // Focus is not a mode: the drawer opens over the terminal
                    // the same way it opens over the grid. It used to be
                    // suppressed here, which meant the settings button in focus
                    // set the state and rendered nothing at all.
                    if let utilityPanel {
                        Color.black.opacity(0.22)
                            .contentShape(Rectangle())
                            .onTapGesture { closeUtilityPanel() }
                            .transition(.opacity)

                        UtilityDrawer(
                            panel: utilityPanel,
                            onClose: closeUtilityPanel,
                            onSwitchPanel: switchUtilityPanel
                        )
                        .frame(width: 420)
                        .frame(maxHeight: .infinity)
                        .padding(.trailing, 18)
                        .padding(.bottom, 18)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
            // Over every workspace, because a session filling up is not a
            // Fleet event — it happens while you are on the board, and it is
            // the one thing worth interrupting whatever you are looking at.
            if let pending = store.pendingContextHandoff {
                HandoffApprovalOverlay(pending: pending)
                    .zIndex(2)
            }

            // In the titlebar, not over the content.
            //
            // As a `.topTrailing` overlay it landed on the top-right corner of
            // whatever panel was below it — in focus that is the toolbar, so it
            // sat on the kill button. The window's top strip is the only place
            // in the app that belongs to no panel, and reaching it means
            // `TitlebarAccessory`; content drawn under a transparent titlebar
            // does not receive clicks.
            TitlebarAccessory(size: CGSize(width: 146, height: 28)) {
                HStack(spacing: 6) {
                    boardButton
                    orchestratorButton
                    settingsButton
                }
            }
            .frame(width: 0, height: 0)
        }
        .preferredColorScheme(.dark)
        .onAppear { installKeyboardMonitor() }
        .onDisappear { removeKeyboardMonitor() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                store.tick()
            }
        }
    }

    private var settingsButton: some View {
        Button {
            toggleUtilityPanel(.settings)
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DaddyTheme.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(utilityPanel == .settings ? 1 : 0.6)
        .padding(.trailing, 12)
        .help("Settings")
    }

    private var boardButton: some View {
        Button(action: toggleBoard) {
            Image(systemName: "rectangle.split.3x1")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(
                    store.workspace == .board
                        ? DaddyTheme.accent : DaddyTheme.textSecondary
                )
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(store.workspace == .board ? 1 : 0.6)
        .help("Board")
    }

    private var orchestratorButton: some View {
        Button {
            store.workspace = store.workspace == .orchestrator ? .fleet : .orchestrator
        } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(
                    store.workspace == .orchestrator
                        ? DaddyTheme.accent : DaddyTheme.textSecondary
                )
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(store.workspace == .orchestrator ? 1 : 0.6)
        .help("Orchestrator")
        .keyboardShortcut("o", modifiers: .control)
    }

    private func toggleBoard() {
        store.workspace = store.workspace == .board ? .fleet : .board
    }

    /// Opaque cover so the live terminals stay laid out underneath at a real
    /// size. Instant, no transition — a fading `if` left an invisible view
    /// eating clicks after you came back.
    private func workspaceCover<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            DaddyTheme.focusSurface
            AuroraBackground()
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .transaction { $0.animation = nil }
    }

    /// ⌘K has to live here, not on the titlebar button and not in `FleetView`.
    ///
    /// `.keyboardShortcut` on a control inside `TitlebarAccessory` is a
    /// SwiftUI view that is not in the window's key-view loop, so the chord
    /// never fires once the terminal has first responder — the same reason
    /// ⌘B is an `NSEvent` monitor. `FleetView`'s monitor dies with the fleet
    /// when the board opens, so close would have no listener. Root owns both.
    private func installKeyboardMonitor() {
        guard keyboardMonitor == nil else { return }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let chords = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard chords == [.command],
                  event.charactersIgnoringModifiers?.lowercased() == "k" else {
                return event
            }
            toggleBoard()
            return nil
        }
    }

    private func removeKeyboardMonitor() {
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
            self.keyboardMonitor = nil
        }
    }

    private func toggleUtilityPanel(_ panel: UtilityPanel) {
        withAnimation(.smooth(duration: 0.24)) {
            utilityPanel = utilityPanel == panel ? nil : panel
        }
    }

    private func switchUtilityPanel(_ panel: UtilityPanel) {
        withAnimation(.smooth(duration: 0.24)) {
            utilityPanel = panel
        }
    }

    private func closeUtilityPanel() {
        withAnimation(.smooth(duration: 0.22)) { utilityPanel = nil }
    }
}
