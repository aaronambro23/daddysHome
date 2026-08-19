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
                ZStack(alignment: .topTrailing) {
                    // Inset in both modes now. Focus used to run the terminal
                    // to the window edges because it *was* the window; with the
                    // rail permanently beside it, the rail would sit flush
                    // against the frame while every other panel floats.
                    FleetView()
                        .padding(.horizontal, 18)

                    if let utilityPanel, !isAgentFocusMode {
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

                    // Settings button in top-right corner, outside the padding
                    Button {
                        toggleUtilityPanel(.settings)
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DaddyTheme.textSecondary)
                            .frame(width: 36, height: 36)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .opacity(0.6)
                    .padding(.top, 18)
                    .padding(.trailing, 18)
                    .help("Settings")
                    .zIndex(1)
                }
            }

        }
        .preferredColorScheme(.dark)
        .onChange(of: store.detailAgentID) { _, detailID in
            if detailID != nil { utilityPanel = nil }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                store.tick()
            }
        }
    }

    private var isAgentFocusMode: Bool {
        store.detailAgent != nil
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
