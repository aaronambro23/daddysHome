import SwiftUI
import DaddyCore

struct CompactAgentIcon: View {
    @Environment(MockStore.self) private var store

    let agent: MockAgent
    let isSelected: Bool
    let onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(Self.tint(for: agent.agent).opacity(0.16))
                    .overlay(Circle().strokeBorder(Self.tint(for: agent.agent).opacity(0.4), lineWidth: 1))
                    .frame(width: 34, height: 34)
                    .overlay {
                        Text(Self.monogram(for: agent.agent))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Self.tint(for: agent.agent))
                    }

                Circle()
                    .fill(StateColors.accent(for: agent.state))
                    .frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.4), lineWidth: 1))
                    .offset(x: 2, y: 2)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.06 : 1.0)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
        .help("\(agent.displayName) · \(agent.workUnitID) · \(StateColors.name(for: agent.state))")
        .overlay {
            if isSelected {
                Circle()
                    .strokeBorder(DaddyTheme.textPrimary.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 38, height: 38)
            }
        }
    }

    static func monogram(for kind: AgentKind) -> String {
        switch kind {
        case .claude: return "C"
        case .codex: return "X"
        case .cursor: return "U"
        case .opencode: return "O"
        }
    }

    static func tint(for kind: AgentKind) -> Color {
        switch kind {
        case .claude: return DaddyTheme.providerClaude
        case .codex: return DaddyTheme.providerCodex
        case .cursor: return DaddyTheme.providerCursor
        case .opencode: return DaddyTheme.providerOpenCode
        }
    }
}
