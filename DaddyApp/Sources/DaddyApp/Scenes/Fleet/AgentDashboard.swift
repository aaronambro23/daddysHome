import SwiftUI
import DaddyCore

struct AgentDashboard: View {
    @Environment(MockStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "AGENTS") {
                HStack(spacing: 10) {
                    HeaderCaption(text: scopeCaption)

                    if store.agents.contains(where: { !$0.isLive }) {
                        Button("clear finished") { store.dismissAllExited() }
                            .buttonStyle(.inset)
                    }

                    launchMenu
                }
            }

            if let error = store.launchError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text(error)
                        .font(.system(size: 10, design: .monospaced))
                    Spacer(minLength: 6)
                    Button("dismiss") { store.launchError = nil }
                        .buttonStyle(.inset)
                }
                .foregroundStyle(DaddyTheme.failure)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            ScrollView {
                VStack(spacing: 10) {
                    if store.visibleAgents.isEmpty {
                        emptyState
                    } else {
                        let grouped = Dictionary(grouping: store.visibleAgents) { $0.agent }
                        ForEach([AgentKind.claude, .codex, .cursor, .opencode], id: \.self) { kind in
                            if let agents = grouped[kind], !agents.isEmpty {
                                AgentGroupSection(
                                    kind: kind,
                                    agents: agents,
                                    selectedAgentID: store.selectedAgentID
                                )
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .glassPanel()
    }

    /// Launches a real CLI in the selected project. Kinds whose binary is not
    /// on PATH are disabled rather than allowed to fail silently — a missing
    /// agent should be visible, not a mystery.
    private var launchMenu: some View {
        GlassDropdown(
            items: launchItems,
            emptyMessage: "Select a project first"
        ) {
            HStack(spacing: 5) {
                Image(systemName: "play.fill")
                    .font(.system(size: 8))
                Text("Launch")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(DaddyTheme.textSecondary)
        }
    }

    private var launchItems: [GlassDropdownItem] {
        guard let project = store.selectedProject else { return [] }

        return [AgentKind.claude, .codex, .cursor, .opencode].map { kind in
            let installed = store.isInstalled(kind)
            return GlassDropdownItem(
                id: kind.rawValue,
                title: kind.rawValue.capitalized,
                note: installed ? nil : "not installed",
                isEnabled: installed
            ) {
                store.launchReal(kind, in: project)
            }
        }
    }

    private var scopeCaption: String {
        if let project = store.selectedProject {
            return "\(project.name) · \(store.visibleAgents.count)"
        }
        return "all projects · \(store.agents.count)"
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(store.selectedProject == nil
                 ? "No agents running"
                 : "No agents on this project")
                .font(.system(size: 11))
                .foregroundStyle(DaddyTheme.textSecondary)

            // This used to say "or speak to Daddy to launch one", which is not
            // true: voice steers agents that already exist, it cannot start one.
            Text(store.selectedProject == nil
                 ? "Pick a project on the left, then use Launch above."
                 : "Use Launch above to start one here.")
                .font(.system(size: 10))
                .foregroundStyle(DaddyTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

// MARK: - Group Section

struct AgentGroupSection: View {
    @Environment(MockStore.self) private var store

    let kind: AgentKind
    let agents: [MockAgent]
    let selectedAgentID: String?

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.smooth(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DaddyTheme.textMuted)

                    Text(kind.rawValue.capitalized)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DaddyTheme.textPrimary)

                    Text("(\(agents.count))")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(DaddyTheme.textSecondary)

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .opacity(0.2)
                    .padding(.horizontal, 12)

                VStack(spacing: 10) {
                    ForEach(agents) { agent in
                        AgentCard(
                            agent: agent,
                            isSelected: selectedAgentID == agent.id
                        )
                    }
                }
                .padding(12)
            }
        }
        .insetSurface(cornerRadius: 14)
    }
}
