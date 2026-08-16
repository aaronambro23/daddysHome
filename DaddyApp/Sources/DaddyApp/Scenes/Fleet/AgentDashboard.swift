import SwiftUI
import DaddyCore

struct AgentDashboard: View {
    @Environment(MockStore.self) private var store

    @Binding var progressOpen: Bool
    let onOpenProgress: (String) -> Void

    @State private var expandedAgentID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "AGENTS") {
                HStack(spacing: 10) {
                    HeaderCaption(text: scopeCaption)

                    if store.agents.contains(where: { !$0.isLive }) {
                        Button("clear finished") { store.dismissAllExited() }
                            .buttonStyle(.inset)
                    }

                    Button(action: { withAnimation(.smooth(duration: 0.3)) { progressOpen.toggle() } }) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(progressOpen ? DaddyTheme.textPrimary : DaddyTheme.textSecondary)
                    }
                    .buttonStyle(.inset)

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
                if store.visibleAgents.isEmpty {
                    emptyState
                        .padding(16)
                } else if let expandedAgent = store.visibleAgents.first(where: { $0.id == expandedAgentID }) {
                    VStack(spacing: 16) {
                        AgentCard(
                            agent: expandedAgent,
                            isSelected: true,
                            onOpenProgress: onOpenProgress
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))

                        let otherAgents = store.visibleAgents.filter { $0.id != expandedAgentID }
                        if !otherAgents.isEmpty {
                            let columns = [
                                GridItem(.adaptive(minimum: 100), spacing: 12)
                            ]
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(otherAgents) { agent in
                                    VStack(spacing: 8) {
                                        CompactAgentIcon(
                                            agent: agent,
                                            isSelected: false,
                                            onTap: {
                                                withAnimation(.smooth(duration: 0.2)) {
                                                    expandedAgentID = agent.id
                                                    store.select(agent: agent.id)
                                                }
                                            }
                                        )
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .aspectRatio(1, contentMode: .fit)
                                    .contentShape(Rectangle())
                                }
                            }
                            .padding(12)
                            .insetSurface(cornerRadius: 14)
                        }
                    }
                    .padding(16)
                } else {
                    let grouped = Dictionary(grouping: store.visibleAgents) { $0.agent }
                    let columns = [GridItem(.flexible(minimum: 300), spacing: 16), GridItem(.flexible(minimum: 300), spacing: 16)]

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach([AgentKind.claude, .codex, .cursor, .opencode], id: \.self) { kind in
                            if let agents = grouped[kind], !agents.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(spacing: 8) {
                                        Text(kind.rawValue.capitalized)
                                            .font(.system(size: 11, weight: .semibold))
                                            .tracking(0.7)
                                            .foregroundStyle(DaddyTheme.textPrimary)

                                        Text("(\(agents.count))")
                                            .font(.system(size: 10, weight: .regular))
                                            .foregroundStyle(DaddyTheme.textSecondary)

                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)

                                    HStack(spacing: 12) {
                                        ForEach(agents) { agent in
                                            VStack(spacing: 8) {
                                                CompactAgentIcon(
                                                    agent: agent,
                                                    isSelected: store.selectedAgentID == agent.id,
                                                    onTap: {
                                                        withAnimation(.smooth(duration: 0.2)) {
                                                            expandedAgentID = agent.id
                                                            store.select(agent: agent.id)
                                                        }
                                                    }
                                                )
                                            }
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                            .aspectRatio(1, contentMode: .fit)
                                            .contentShape(Rectangle())
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 120)
                                }
                                .padding(12)
                                .insetSurface(cornerRadius: 14)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .glassPanel()
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

            Text(store.selectedProject == nil
                 ? "Pick a project on the left, then use Launch above."
                 : "Use Launch above to start one here.")
                .font(.system(size: 10))
                .foregroundStyle(DaddyTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

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
}
