import SwiftUI

// A clear glass panel. No dark fill, no tint, no neon — the terminal reads as
// near-white monospace over whatever the backdrop is doing behind the glass.

struct TerminalPane: View {
    @Environment(MockStore.self) private var store
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "OUTPUT") {
                if let agent = store.selectedAgent {
                    HStack(spacing: 8) {
                        if agent.isRealSession {
                            // Distinguish a real pty from seeded demo data at a
                            // glance — otherwise they are indistinguishable.
                            HStack(spacing: 5) {
                                BreathingDot(color: DaddyTheme.working, glowRadius: 6, size: 4)
                                Text("LIVE")
                                    .font(.system(size: 8, weight: .bold))
                                    .tracking(0.8)
                                    .foregroundStyle(DaddyTheme.working)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .insetCapsule(tint: DaddyTheme.working, opacity: 0.12)
                        }

                        HeaderCaption(text: "\(agent.agent.rawValue) · \(agent.workUnitID)")
                    }
                }
            }

            if let agent = store.selectedAgent, agent.isRealSession {
                if let pty = store.pty(for: agent) {
                    // Real pty: SwiftTerm renders it, including colour and any
                    // interactive prompts the agent draws.
                    TerminalSurface(pty: pty)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                } else {
                    VStack(spacing: 6) {
                        Text("Session ended")
                            .font(.system(size: 11))
                            .foregroundStyle(DaddyTheme.textSecondary)
                        Text("The process is no longer running")
                            .font(.system(size: 10))
                            .foregroundStyle(DaddyTheme.textMuted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if store.selectedAgent != nil {
                transcript
            } else {
                VStack {
                    Text("Select an agent to view output")
                        .font(.system(size: 11))
                        .foregroundStyle(DaddyTheme.textMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            GlassHairline()

            composer
        }
        .glassPanel()
    }

    // MARK: Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.terminalForSelection) { line in
                        lineView(line)
                            .id(line.id)
                    }

                    HStack(spacing: 6) {
                        Text(">")
                            .foregroundStyle(DaddyTheme.textMuted)
                        BlinkingCursor()
                    }
                    .font(.system(size: 10.5, design: .monospaced))
                    .id("cursor")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }
            .onChange(of: store.terminalForSelection.count) {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("cursor", anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private func lineView(_ line: TerminalLine) -> some View {
        switch line.kind {
        case .rule:
            GlassHairline()
                .padding(.vertical, 4)
        case .command:
            Text(line.text)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(DaddyTheme.textPrimary)
                .textSelection(.enabled)
        case .output:
            Text(line.text)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(DaddyTheme.textSecondary)
                .textSelection(.enabled)
        case .dim:
            Text(line.text)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(DaddyTheme.textMuted)
                .textSelection(.enabled)
        case .error:
            Text(line.text)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(DaddyTheme.failure)
                .textSelection(.enabled)
        }
    }

    // MARK: Composer

    private var composer: some View {
        @Bindable var store = store

        return HStack(spacing: 10) {
            Text("›")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(DaddyTheme.textMuted)

            TextField("type to send into session…", text: $store.composeText)
                .textFieldStyle(.plain)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(DaddyTheme.textPrimary)
                .focused($composerFocused)
                .onSubmit(sendComposer)

            Button("send", action: sendComposer)
                .buttonStyle(.inset)
                .disabled(store.composeText.trimmingCharacters(in: .whitespaces).isEmpty
                          || store.selectedAgent == nil)

            Button("go on") {
                if let agent = store.selectedAgent { store.resume(agent.id) }
            }
            .buttonStyle(.inset(DaddyTheme.working))
            .disabled(store.selectedAgent == nil)

            Button("esc") {
                if let agent = store.selectedAgent { store.interrupt(agent.id) }
            }
            .buttonStyle(.inset(DaddyTheme.failure))
            .disabled(store.selectedAgent == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func sendComposer() {
        guard let agent = store.selectedAgent else { return }
        store.send(store.composeText, to: agent.id)
    }
}

// MARK: - Cursor

struct BlinkingCursor: View {
    @State private var on = true

    var body: some View {
        Text("█")
            .foregroundStyle(DaddyTheme.textSecondary)
            .opacity(on ? 0.9 : 0.1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    on = false
                }
            }
    }
}
