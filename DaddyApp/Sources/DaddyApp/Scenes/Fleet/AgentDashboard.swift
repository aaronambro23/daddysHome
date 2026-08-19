import SwiftUI
import DaddyCore

struct AgentDashboard: View {
    @Environment(MockStore.self) private var store

    @Binding var progressOpen: Bool
    let onOpenProgress: (String) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "AGENTS") {
                    HStack(spacing: 10) {
                        HeaderCaption(text: scopeCaption)

                        if store.selectedProject != nil {
                            Button {
                                store.dismissAllActiveAgentsInSelectedProject()
                            } label: {
                                Label("Dismiss all agents", systemImage: "ladybug.fill")
                                    .font(.system(size: 9.5, weight: .semibold))
                            }
                            .buttonStyle(.inset)
                            .foregroundStyle(DaddyTheme.failure)
                            .disabled(!store.visibleAgents.contains(where: \.isLive))
                            .help("Debug: stop and dismiss every live agent in this project")
                        }

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

                        Spacer()
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

            // One layout, always. Selecting an agent used to swap this whole
            // column for a different arrangement — and filtered the selected
            // agent out of the grid, so nothing was left to click to get back.
            ScrollView {
                if store.visibleAgents.isEmpty {
                    emptyState
                        .padding(16)
                } else {
                    let grouped = Dictionary(grouping: store.visibleAgents) { $0.agent }

                    // Adaptive rather than a fixed two: the middle column is
                    // narrow with the terminal docked beside it and wide once
                    // the terminal moves below, and the tiles should reflow
                    // instead of being squeezed under their minimum.
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 268), spacing: 14)],
                        spacing: 14
                    ) {
                        ForEach([AgentKind.claude, .codex, .cursor, .opencode], id: \.self) { kind in
                            if let agents = grouped[kind], !agents.isEmpty {
                                ProviderTile(
                                    kind: kind,
                                    agents: agents,
                                    onOpenProgress: onOpenProgress
                                )
                            }
                        }
                    }
                    .padding(16)
                }
            }
            }

            launchMenu
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 56)
                .padding(.trailing, 16)
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
        ProviderLaunchMenu(project: store.selectedProject) {
            HStack(spacing: 5) {
                Image(systemName: "play.fill")
                    .font(.system(size: 8))
                Text("Launch")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(DaddyTheme.textSecondary)
        }
    }
}
