import SwiftUI

struct RootView: View {
    @Environment(MockStore.self) private var store
    @State private var utilityPanel: UtilityPanel?

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 0) {
                header
                    .frame(height: isAgentFocusMode ? 0 : nil)
                    .opacity(isAgentFocusMode ? 0 : 1)
                    .clipped()
                    .allowsHitTesting(!isAgentFocusMode)

                ZStack(alignment: .trailing) {
                    FleetView()
                        .padding(.horizontal, isAgentFocusMode ? 0 : 18)
                        .padding(.bottom, isAgentFocusMode ? 0 : 18)

                    if let utilityPanel, !isAgentFocusMode {
                        Color.black.opacity(0.22)
                            .contentShape(Rectangle())
                            .onTapGesture { closeUtilityPanel() }
                            .transition(.opacity)

                        UtilityDrawer(panel: utilityPanel, onClose: closeUtilityPanel)
                            .frame(width: 420)
                            .frame(maxHeight: .infinity)
                            .padding(.trailing, 18)
                            .padding(.bottom, 18)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
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

    // MARK: Header
    //
    // Fleet is the product, not one destination among four. The only controls
    // here open contextual utilities over the workspace without navigating away.

    private var header: some View {
        HStack(spacing: 18) {
            HStack(spacing: 12) {
                if let nsImage = NSImage(contentsOfFile: "/Users/aaronambrosi/Documents/daddy/DH-Logo.png") {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DaddyTheme.accent)
                        .frame(width: 36, height: 36)
                }

                Text("DADDY'S HOME")
                    .font(.system(size: 15, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(DaddyTheme.textPrimary)
            }

            Spacer(minLength: 12)

            GlassEffectContainer(spacing: 16) {
                HStack(spacing: 8) {
                    Button {
                        toggleUtilityPanel(.hex)
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "waveform")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(DaddyTheme.textSecondary)

                            Text("HEX")
                                .font(.system(size: 10))
                                .foregroundStyle(DaddyTheme.textSecondary)
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassPill(
                        tint: utilityPanel == .hex ? DaddyTheme.accent.opacity(0.14) : nil,
                        interactive: true
                    )

                    HStack(spacing: 6) {
                        Text("\(store.liveAgentCount)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(DaddyTheme.textPrimary)

                        Text("sessions")
                            .font(.system(size: 10))
                            .foregroundStyle(DaddyTheme.textSecondary)
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .glassPill()

                    Button {
                        toggleUtilityPanel(.settings)
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DaddyTheme.textSecondary)
                            .frame(width: 30, height: 30)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassPill(
                        tint: utilityPanel == .settings ? DaddyTheme.accent.opacity(0.14) : nil,
                        interactive: true
                    )
                    .help("Settings")
                }
            }
        }
        .padding(.horizontal, 18)
        // Hidden-titlebar traffic lights occupy the first ~22pt vertically.
        // Put the brand below them so it can share the sidebar's true left edge.
        .padding(.top, 26)
        .padding(.bottom, 10)
    }

    private func toggleUtilityPanel(_ panel: UtilityPanel) {
        withAnimation(.smooth(duration: 0.24)) {
            utilityPanel = utilityPanel == panel ? nil : panel
        }
    }

    private func closeUtilityPanel() {
        withAnimation(.smooth(duration: 0.22)) { utilityPanel = nil }
    }
}
