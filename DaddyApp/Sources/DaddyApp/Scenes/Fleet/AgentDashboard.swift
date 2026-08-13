import SwiftUI
import DaddyCore

struct AgentDashboard: View {
    @Environment(MockStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "AGENTS") {
                HStack(spacing: 10) {
                    HeaderCaption(text: scopeCaption)
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
                        ForEach(store.visibleAgents) { agent in
                            AgentCard(
                                agent: agent,
                                isSelected: store.selectedAgentID == agent.id
                            )
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
