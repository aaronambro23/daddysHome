import SwiftUI
import DaddyCore

/// The control-centre home: every project that has batch documents, what is in
/// flight across all of them, and what needs attention.
///
/// This replaced the Fleet tab, which showed fabricated agents and could spawn
/// ptys — both wrong for a branch where work happens in the user's terminal.
struct OverviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(HandoffViewModel.self) private var handoffs

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "ACTIVE PROJECTS") {
                    HStack(spacing: 10) {
                        HeaderCaption(text: activeCaption)
                        Button("Rescan") {
                            store.reloadProjects()
                            handoffs.scanAll(projects: store.projects)
                        }
                        .buttonStyle(.inset)
                    }
                }

                if handoffs.summaries.isEmpty {
                    emptyState
                } else {
                    projectList
                }
            }
            .glassPanel()

            attentionPanel
                .frame(width: 380)
        }
        .onAppear { handoffs.scanAll(projects: store.projects) }
    }

    // MARK: Left — projects

    private var activeCaption: String {
        let withWork = handoffs.summaries.filter { $0.overview.total > 0 }.count
        return "\(withWork) of \(store.projects.count) tracked"
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("No batch documents anywhere yet")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DaddyTheme.textPrimary)

            Text("""
            Install the working agreement on a project, then agents record each \
            batch in \(WorkflowContract.handoffDirectory)/ as they work.
            """)
                .font(.system(size: 10.5))
                .foregroundStyle(DaddyTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private var projectList: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(handoffs.summaries) { summary in
                    ProjectSummaryCard(summary: summary) {
                        store.openBatches(for: summary.project.id)
                        handoffs.refresh(project: summary.project)
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: Right — needs attention

    private var attentionPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "NEEDS ATTENTION") {
                HeaderCaption(text: "\(handoffs.attentionItems.count)")
            }

            if handoffs.attentionItems.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(DaddyTheme.working.opacity(0.7))
                    Text("Nothing stalled")
                        .font(.system(size: 11))
                        .foregroundStyle(DaddyTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 9) {
                        ForEach(handoffs.attentionItems) { item in
                            AttentionRow(item: item) {
                                store.openBatches(for: item.projectID)
                                if let project = store.project(item.projectID) {
                                    handoffs.refresh(project: project)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .glassPanel()
    }
}

// MARK: - Project card

struct ProjectSummaryCard: View {
    let summary: HandoffViewModel.ProjectSummary
    let onOpen: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)

                Text(summary.project.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(DaddyTheme.textPrimary)

                Spacer(minLength: 8)

                if !summary.isConfigured {
                    Text("no agreement")
                        .font(.system(size: 8.5, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(DaddyTheme.limited)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .insetCapsule(tint: DaddyTheme.limited, opacity: 0.12)
                }

                Text("\(summary.overview.done)/\(summary.overview.total)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DaddyTheme.textSecondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(DaddyTheme.working.opacity(0.7))
                        .frame(width: geo.size.width * completion)
                }
            }
            .frame(height: 4)

            HStack(spacing: 12) {
                if let resume = summary.overview.resumeAt {
                    Label("\(resume.filename)", systemImage: "arrow.right.circle")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(DaddyTheme.accent)
                }

                if summary.overview.outstandingTasks > 0 {
                    Text("\(summary.overview.outstandingTasks) tasks left")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(DaddyTheme.textMuted)
                }

                Spacer(minLength: 6)

                if let touched = summary.lastActivity {
                    Text(formatTimeAgo(touched))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(DaddyTheme.textMuted)
                }
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .insetSurface(cornerRadius: 16, filled: hovering)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture(perform: onOpen)
    }

    private var completion: Double {
        guard summary.overview.total > 0 else { return 0 }
        return Double(summary.overview.done) / Double(summary.overview.total)
    }

    private var dotColor: Color {
        if summary.overview.stalled > 0 { return DaddyTheme.limited }
        if summary.overview.inProgress > 0 { return DaddyTheme.working }
        if summary.overview.total == summary.overview.done { return DaddyTheme.idle }
        return DaddyTheme.accent
    }
}

// MARK: - Attention row

struct AttentionRow: View {
    let item: HandoffViewModel.AttentionItem
    let onOpen: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: item.kind.symbol)
                .font(.system(size: 11))
                .foregroundStyle(item.kind.color)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(DaddyTheme.textPrimary)

                Text(item.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(DaddyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 6)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .insetSurface(cornerRadius: 14, filled: hovering)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture(perform: onOpen)
    }
}
