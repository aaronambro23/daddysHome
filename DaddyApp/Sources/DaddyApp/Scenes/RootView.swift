import SwiftUI

struct RootView: View {
    @Environment(MockStore.self) private var store
    @FocusState private var hiddenFieldFocused: Bool
    @State private var hiddenVoiceInput = ""
    @State private var isProcessingVoice = false

    var body: some View {
        @Bindable var store = store

        ZStack {
            AuroraBackground()

            VStack(spacing: 0) {
                header

                Group {
                    switch store.tab {
                    case .fleet: FleetView()
                    case .workUnits: WorkUnitsView()
                    case .voice: VoiceView()
                    case .settings: SettingsView()
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
                .transition(.opacity)
            }

            // Hidden text field that always has focus so HEX dictation is captured
            // from any tab, not just the Voice tab. HEX just pastes; it doesn't
            // send Return, so we auto-submit when text appears.
            TextField("", text: $hiddenVoiceInput)
                .focused($hiddenFieldFocused)
                .onChange(of: hiddenVoiceInput) { oldValue, newValue in
                    if !isProcessingVoice && !newValue.isEmpty && oldValue.isEmpty {
                        isProcessingVoice = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            store.submitVoice(hiddenVoiceInput)
                            hiddenVoiceInput = ""
                            isProcessingVoice = false
                            hiddenFieldFocused = true
                        }
                    }
                }
                .frame(width: 0, height: 0)
                .opacity(0)
        }
        .preferredColorScheme(.dark)
        .onAppear { hiddenFieldFocused = true }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                store.tick()
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
            HStack(spacing: 12) {
                if let nsImage = NSImage(contentsOfFile: "/Users/aaronambrosi/Documents/daddy/DH-Logo.png") {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DaddyTheme.accent)
                }

                Text("DADDY'S HOME")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.0)
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
                }
            }
            .padding(.trailing, 22)
        }
        .padding(.vertical, 18)
    }
}
