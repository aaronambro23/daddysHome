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

            if let agent = store.selectedAgent {
                if let pty = store.pty(for: agent) {
                    // Real pty: SwiftTerm renders it, including colour and any
                    // interactive prompts the agent draws.
                    TerminalSurface(pty: pty)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                } else {
                    emptyState(
                        "Session ended",
                        detail: "The process is no longer running. Relaunch starts a new one."
                    )
                }
            } else if store.agents.isEmpty {
                emptyState(
                    "No agents running",
                    detail: "Pick a project in the sidebar and launch one."
                )
            } else {
                emptyState("Select an agent to view its output", detail: nil)
            }

            GlassHairline()

            composer
        }
        .glassPanel()
    }

    @ViewBuilder
    private func emptyState(_ title: String, detail: String?) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(DaddyTheme.textSecondary)
            if let detail {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(DaddyTheme.textMuted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

