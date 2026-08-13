import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(HandoffViewModel.self) private var handoffs

    var body: some View {
        @Bindable var store = store

        ZStack {
            AuroraBackground()

            VStack(spacing: 0) {
                header

                Group {
                    switch store.tab {
                    case .overview: OverviewView()
                    case .batches: WorkUnitsView()
                    case .voice: VoiceView()
                    case .settings: SettingsView()
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
                .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            // Periodic rescan until the file watcher lands (step 3). Reading a
            // handful of small Markdown files is cheap.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                handoffs.scanAll(projects: store.projects)
                if store.tab == .batches {
                    handoffs.refresh(project: store.selectedProject)
                }
            }
        }
    }

    // MARK: Header
    //
    // The tab bar and the status pills are the only glass in the chrome, and
    // they sit over the backdrop — never over another glass surface.

    private var header: some View {
        @Bindable var store = store

        return HStack(spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DaddyTheme.textSecondary)

                Text("DADDY")
                    .font(.system(size: 14, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(DaddyTheme.textPrimary)
            }
            .padding(.leading, 78)   // clears the traffic lights

            Spacer(minLength: 12)

            GlassTabBar(selection: $store.tab)

            Spacer(minLength: 12)

            GlassEffectContainer(spacing: 16) {
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.smooth(duration: 0.35)) {
                            store.tab = .voice
                            store.toggleListening()
                        }
                    } label: {
                        HStack(spacing: 7) {
                            BreathingDot(color: DaddyTheme.working, glowRadius: 7, size: 5)

                            Text(store.isListening ? "HEX Listening" : "HEX Ready")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(DaddyTheme.textSecondary)
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassPill(interactive: true)

                    // Outstanding work across every tracked project — the one
                    // number worth carrying in the chrome.
                    HStack(spacing: 6) {
                        Text("\(handoffs.totalOutstandingTasks)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(DaddyTheme.textPrimary)

                        Text("tasks open")
                            .font(.system(size: 10))
                            .foregroundStyle(DaddyTheme.textSecondary)
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .glassPill()
                }
            }
            .padding(.trailing, 22)
        }
        .padding(.vertical, 18)
    }
}
