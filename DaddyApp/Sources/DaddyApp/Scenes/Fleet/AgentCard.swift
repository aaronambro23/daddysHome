import SwiftUI
import DaddyCore

// Inside a glass panel — so this card is NOT glass. It's an inset surface.

struct AgentCard: View {
    @Environment(MockStore.self) private var store

    let agent: MockAgent
    let isSelected: Bool
    let onOpenProgress: (String) -> Void

    @State private var hovering = false
    @State private var showingDocuments = false
    @State private var inProgressDocs: [String] = []
    @State private var doneDocs: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button(action: {
                    withAnimation(.smooth(duration: 0.2)) {
                        showingDocuments.toggle()
                        if showingDocuments {
                            loadDocuments()
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: showingDocuments ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(DaddyTheme.textMuted)

                        Text(agent.displayName)
                            .font(.system(size: 12, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(DaddyTheme.textPrimary)
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 6)

                StatusBadge(state: agent.state, compact: true)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    let liveState = store.readAgentStateFromFile(agentID: agent.id, projectPath: store.selectedProject?.path ?? "")
                    MetricRow(label: "model", value: liveState.model ?? "-")
                    MetricRow(label: "work", value: liveState.workUnitID ?? "-", accent: DaddyTheme.textPrimary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    MetricRow(label: "project", value: store.project(agent.projectID)?.name ?? agent.projectID)
                    MetricRow(label: "uptime", value: agent.uptime)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showingDocuments {
                Divider()
                    .opacity(0.3)

                VStack(alignment: .leading, spacing: 8) {
                    if !inProgressDocs.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("IN PROGRESS")
                                .font(.system(size: 8, weight: .medium))
                                .tracking(0.6)
                                .foregroundStyle(Color(hex: "#ecca8f"))

                            ForEach(inProgressDocs, id: \.self) { doc in
                                HStack(spacing: 6) {
                                    Image(systemName: "circle")
                                        .font(.system(size: 8, weight: .semibold))
                                        .foregroundStyle(Color(hex: "#ecca8f"))
                                    Text(doc)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(DaddyTheme.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }

                    if !doneDocs.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("COMPLETED")
                                .font(.system(size: 8, weight: .medium))
                                .tracking(0.6)
                                .foregroundStyle(Color(hex: "#8fe9bb"))

                            ForEach(doneDocs, id: \.self) { doc in
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 8, weight: .semibold))
                                        .foregroundStyle(Color(hex: "#8fe9bb"))
                                    Text(doc)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(DaddyTheme.textMuted)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }

                    if inProgressDocs.isEmpty && doneDocs.isEmpty {
                        Text("No documents yet")
                            .font(.system(size: 10))
                            .foregroundStyle(DaddyTheme.textMuted)
                    }
                }
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

            // Actions sit below a rule rather than floating at the bottom of the
            // card. They were easy to miss, and identical to each other, so the
            // primary one now carries colour and an icon and the rest recede.
            GlassHairline()
                .padding(.top, 2)

            HStack(spacing: 7) {
                // The control that is useful depends on what the agent is
                // doing: halt it while it works, restart its train of thought
                // once it has stopped, spawn a new process once it is gone.
                if !agent.isLive {
                    if store.canResumeChat(agent.agent) {
                        action("Resume chat", "arrow.uturn.left", DaddyTheme.working) {
                            store.relaunch(agent.id, continuingConversation: true)
                        }
                        action("Fresh start", "arrow.clockwise", DaddyTheme.textSecondary) {
                            store.relaunch(agent.id)
                        }
                    } else {
                        action("Relaunch", "arrow.clockwise", DaddyTheme.working) {
                            store.relaunch(agent.id)
                        }
                    }
                    action("Dismiss", "xmark", DaddyTheme.textMuted) {
                        store.dismiss(agent.id)
                    }
                } else if agent.isBusy {
                    action("Interrupt", "hand.raised.fill", DaddyTheme.limited) {
                        store.interrupt(agent.id)
                    }
                    action("Stop", "stop.fill", DaddyTheme.failure) {
                        store.stop(agent.id)
                    }
                } else {
                    action("Continue", "play.fill", DaddyTheme.working) {
                        store.resume(agent.id)
                    }
                    action("Stop", "stop.fill", DaddyTheme.failure) {
                        store.stop(agent.id)
                    }
                }

                action("View docs", "doc.text.magnifyingglass", DaddyTheme.textSecondary) {
                    onOpenProgress(agent.projectID)
                }

                if agent.isLive {
                    GlassDropdown(items: handOffItems, width: 190) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrowshape.turn.up.right")
                                .font(.system(size: 8))
                            Text("Hand off")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(DaddyTheme.textSecondary)
                    }
                }

                Spacer(minLength: 6)

                Text(formatTimeAgo(agent.lastOutputAt))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(DaddyTheme.textMuted)
            }
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

    /// One shape for every action, so they read as a row of controls rather
    /// than a row of identical pills. Colour marks what the button does; the
    /// icon makes it recognisable before the label is read.
    private func action(
        _ title: String,
        _ symbol: String,
        _ accent: Color,
        _ perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 8, weight: .bold))
                Text(title)
            }
        }
        .buttonStyle(.inset(accent))
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

    private func loadDocuments() {
        guard let project = store.project(agent.projectID) else { return }

        let projectPath = project.path
        let handoffsDir = projectPath + "/documents/handoffs"
        let fm = FileManager.default

        var inProgress: [String] = []
        var done: [String] = []

        if let contents = try? fm.contentsOfDirectory(atPath: handoffsDir) {
            for item in contents.sorted() {
                if item == "DONE.md" || item == "done" {
                    continue
                } else if item.hasSuffix(".md") {
                    inProgress.append(item.replacingOccurrences(of: ".md", with: ""))
                }
            }

            // Check done folder
            let donePath = handoffsDir + "/done"
            if let doneContents = try? fm.contentsOfDirectory(atPath: donePath) {
                done = doneContents.filter { $0.hasSuffix(".md") }.map {
                    $0.replacingOccurrences(of: ".md", with: "")
                }
            }
        }

        self.inProgressDocs = inProgress
        self.doneDocs = done
    }
}
