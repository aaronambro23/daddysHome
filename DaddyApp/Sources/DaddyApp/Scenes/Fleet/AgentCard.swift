import SwiftUI
import DaddyCore

// Inside a glass panel — so this card is NOT glass. It's an inset surface.

struct AgentCard: View {
    @Environment(MockStore.self) private var store

    let agent: MockAgent
    let isSelected: Bool

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DaddyTheme.textMuted)

                Text(agent.displayName)
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.0)
                    .foregroundStyle(DaddyTheme.textPrimary)

                Spacer(minLength: 8)

                StatusBadge(state: agent.state)
            }

            VStack(alignment: .leading, spacing: 7) {
                MetricRow(label: "project", value: store.project(agent.projectID)?.path ?? agent.projectID)
                MetricRow(label: "model", value: agent.model)
                MetricRow(label: "work", value: agent.workUnitID, accent: DaddyTheme.textPrimary)
                MetricRow(label: "uptime", value: agent.uptime)
            }

            if case .error(let message) = agent.state {
                Text(message)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(DaddyTheme.failure)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(DaddyTheme.failure.opacity(0.10))
                    }
            }

            HStack(spacing: 8) {
                // The control that is useful depends on what the agent is
                // doing: halt it while it works, restart its train of thought
                // once it has stopped, spawn a new process once it is gone.
                if !agent.isLive {
                    Button("Relaunch") { store.relaunch(agent.id) }
                } else if agent.isBusy {
                    Button("Interrupt") { store.interrupt(agent.id) }
                    Button("Stop") { store.stop(agent.id) }
                } else {
                    Button("Continue") { store.resume(agent.id) }
                    Button("Stop") { store.stop(agent.id) }
                }

                GlassDropdown(items: handOffItems, width: 190) {
                    Text("Hand off")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DaddyTheme.textSecondary)
                }

                Spacer(minLength: 6)

                Text(formatTimeAgo(agent.lastOutputAt))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(DaddyTheme.textMuted)
            }
            .buttonStyle(.inset)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .insetSurface(cornerRadius: 18, selected: isSelected, filled: hovering)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onTapGesture {
            withAnimation(.smooth(duration: 0.3)) {
                store.select(agent: agent.id)
            }
        }
    }

    private var handOffItems: [GlassDropdownItem] {
        [AgentKind.claude, .codex, .cursor, .opencode].map { kind in
            GlassDropdownItem(
                id: kind.rawValue,
                title: kind.rawValue.capitalized,
                note: store.isInstalled(kind) ? nil : "not installed",
                isEnabled: store.isInstalled(kind) && kind != agent.agent
            ) {
                store.handOff(agent.id, to: kind)
            }
        }
    }
}
