import SwiftUI

struct AgentDashboard: View {
    @Environment(MockStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "AGENTS") {
                HeaderCaption(text: scopeCaption)
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

    private var scopeCaption: String {
        if let project = store.selectedProject {
            return "\(project.name) · \(store.visibleAgents.count)"
        }
        return "all projects · \(store.agents.count)"
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No agents on this project")
                .font(.system(size: 11))
                .foregroundStyle(DaddyTheme.textSecondary)

            Text("Pick another project, or speak to Daddy to launch one")
                .font(.system(size: 10))
                .foregroundStyle(DaddyTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}
