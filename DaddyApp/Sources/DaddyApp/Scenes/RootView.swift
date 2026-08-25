import SwiftUI

struct RootView: View {
    @Environment(MockStore.self) private var store
    @State private var utilityPanel: UtilityPanel?

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
                    FleetView()
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
            // In the titlebar, not over the content.
            //
            // As a `.topTrailing` overlay it landed on the top-right corner of
            // whatever panel was below it — in focus that is the toolbar, so it
            // sat on the kill button. The window's top strip is the only place
            // in the app that belongs to no panel, and reaching it means
            // `TitlebarAccessory`; content drawn under a transparent titlebar
            // does not receive clicks.
            TitlebarAccessory(size: CGSize(width: 90, height: 28)) {
                HStack(spacing: 4) {
                    Spacer()
                    companionButton
                    settingsButton
                }
            }
            .frame(width: 0, height: 0)
        }
        .preferredColorScheme(.dark)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                store.tick()
            }
        }
    }

    private var companionButton: some View {
        Button {
            toggleUtilityPanel(.companion)
        } label: {
            Image(systemName: "star.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DaddyTheme.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(utilityPanel == .companion ? 1 : 0.6)
        .help("Pokémon Companion")
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
