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
                if agent.isLive {
                    Button("Interrupt") { store.interrupt(agent.id) }
                    Button("Stop") { store.stop(agent.id) }
                } else {
                    Button("Relaunch") { store.relaunch(agent.id) }
                }

                Menu("Hand off") {
                    ForEach([AgentKind.claude, .codex, .cursor, .opencode], id: \.rawValue) { kind in
                        Button(kind.rawValue.capitalized) {
                            store.handOff(agent.id, to: kind)
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DaddyTheme.textSecondary)
                .fixedSize()

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
}
