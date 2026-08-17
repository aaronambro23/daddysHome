import SwiftUI
import DaddyCore

/// The focus-mode toolbar. Identity and navigation stay visible; everything
/// secondary moves into the overflow so the terminal owns the screen.
struct AgentDetailHeader: View {
    @Environment(MockStore.self) private var store
    @State private var backHovering = false

    let agent: MockAgent
    let onOpenProgress: (String) -> Void
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 11, weight: .bold))
                    Text("Back to Fleet")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(DaddyTheme.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background {
                    Capsule()
                        .fill(Color.white.opacity(backHovering ? 0.16 : 0.10))
                }
                .overlay {
                    Capsule()
                        .strokeBorder(Color.white.opacity(backHovering ? 0.24 : 0.16))
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { backHovering = $0 }
            .animation(.easeOut(duration: 0.14), value: backHovering)
            .keyboardShortcut("[", modifiers: .command)
            .help("Back to Fleet (⌘[ or Esc)")

            CompactAgentIcon(
                agent: agent,
                isSelected: false,
                size: 24,
                onTap: {}
            )

            HStack(spacing: 6) {
                Text(projectName)
                    .foregroundStyle(DaddyTheme.textSecondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(DaddyTheme.textVeryDim)
                Text(agent.displayName)
                    .fontWeight(.bold)
                    .foregroundStyle(DaddyTheme.textPrimary)
            }
            .font(.system(size: 11, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.middle)

            Spacer(minLength: 10)

            FocusAgentSwitcher(
                agents: store.visibleAgents,
                activeID: agent.id,
                onSelect: { id in store.openDetail(id) }
            )

            StatusBadge(state: agent.state)

            Text(agent.uptime)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(DaddyTheme.textMuted)

            GlassDropdown(items: menuItems, width: 250) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DaddyTheme.textSecondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .help("Session details and actions")
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, minHeight: 58, maxHeight: 58)
        .background(DaddyTheme.focusSurface)
        .overlay(alignment: .bottom) { GlassHairline() }
    }

    private var projectName: String {
        store.project(agent.projectID)?.name ?? agent.projectID
    }

    private var menuItems: [GlassDropdownItem] {
        var items = [
            GlassDropdownItem(id: "model", title: "Model", note: agent.model, isEnabled: false) {},
            GlassDropdownItem(id: "work", title: "Work unit", note: agent.workUnitID, isEnabled: false) {},
            processItem,
            GlassDropdownItem(id: "docs", title: "View project docs") {
                onOpenProgress(agent.projectID)
            },
        ]

        if agent.isLive {
            items.append(GlassDropdownItem(id: "stop", title: "Stop agent") {
                store.stop(agent.id)
            })

            for kind in [AgentKind.claude, .codex, .cursor, .opencode]
            where kind != agent.agent {
                items.append(
                    GlassDropdownItem(
                        id: "handoff-\(kind.rawValue)",
                        title: "Hand off to \(kind.rawValue.capitalized)",
                        note: store.isInstalled(kind) ? nil : "not installed",
                        isEnabled: store.isInstalled(kind)
                    ) {
                        store.handOff(agent.id, to: kind)
                    }
                )
            }
        } else {
            if store.canResumeChat(agent.agent) {
                items.append(GlassDropdownItem(id: "resume", title: "Resume chat") {
                    store.relaunch(agent.id, continuingConversation: true)
                })
                items.append(GlassDropdownItem(id: "fresh", title: "Fresh start") {
                    store.relaunch(agent.id)
                })
            } else {
                items.append(GlassDropdownItem(id: "relaunch", title: "Relaunch") {
                    store.relaunch(agent.id)
                })
            }
            items.append(GlassDropdownItem(id: "dismiss", title: "Dismiss agent") {
                store.dismiss(agent.id)
            })
        }

        return items
    }

    private var processItem: GlassDropdownItem {
        if let pty = store.pty(for: agent) {
            if pty.isProcessRunning {
                return GlassDropdownItem(
                    id: "process",
                    title: "Process",
                    note: "pid \(pty.pid)",
                    isEnabled: false
                ) {}
            }
            if let code = pty.exitCode {
                return GlassDropdownItem(
                    id: "process",
                    title: "Process",
                    note: "exit \(code)",
                    isEnabled: false
                ) {}
            }
        }
        return GlassDropdownItem(
            id: "process",
            title: "Process",
            note: "unavailable",
            isEnabled: false
        ) {}
    }
}
