import SwiftUI
import DaddyCore

/// The PM view: every batch document in the selected project, in order, with
/// what is done, what is outstanding, and where a new agent should pick up.
struct WorkUnitsView: View {
    @Environment(AppStore.self) private var store
    @Environment(HandoffViewModel.self) private var handoffs

    var body: some View {
        HStack(spacing: 16) {
            ProjectsSidebar()
                .frame(width: 264)

            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "BATCHES") {
                    HStack(spacing: 10) {
                        HeaderCaption(text: caption)
                        toolbar
                    }
                }

                notices

                if let project = store.selectedProject {
                    if !handoffs.documents.isEmpty {
                        // Documents win. A project can have batch documents
                        // without the contract installed — hiding real work
                        // behind a setup prompt would be absurd.
                        if !handoffs.isConfigured {
                            contractNudge(project)
                        }
                        documentList
                    } else if handoffs.isConfigured {
                        emptyState(project)
                    } else {
                        notConfigured(project)
                    }
                } else {
                    placeholder("Select a project")
                }
            }
            .glassPanel()
        }
        .onAppear { handoffs.refresh(project: store.selectedProject) }
        .onChange(of: store.selectedProjectID) {
            handoffs.refresh(project: store.selectedProject)
        }
    }

    // MARK: Header

    private var caption: String {
        guard let overview = handoffs.overview, overview.total > 0 else {
            return store.selectedProject?.name ?? "no project"
        }
        return "\(overview.done)/\(overview.total) done · \(overview.outstandingTasks) tasks left"
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            Button("Refresh") { handoffs.refresh(project: store.selectedProject) }

            if let project = store.selectedProject {
                // Launch into Terminal.app: Daddy spawns, the work happens in
                // the user's own terminal.
                Menu("New batch") {
                    ForEach(AgentKind.allCases, id: \.rawValue) { kind in
                        Button(store.isInstalled(kind)
                               ? kind.displayName
                               : "\(kind.displayName) — not installed") {
                            handoffs.launchNewBatch(agent: kind, in: project)
                        }
                        .disabled(!store.isInstalled(kind))
                    }
                }
                .menuStyle(.borderlessButton)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DaddyTheme.textSecondary)
                .fixedSize()
            }

            if let project = store.selectedProject, handoffs.isConfigured {
                Button("Copy brief") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        handoffs.handoffBrief(for: project), forType: .string
                    )
                    handoffs.installNotice = "Handoff brief copied — paste it into a new agent"
                }
                .disabled(handoffs.documents.isEmpty)

                Button("Write DONE.md") { handoffs.writeOverview(for: project) }
                    .disabled(handoffs.documents.isEmpty)

                Button("Reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [handoffs.handoffDirectory(for: project)]
                    )
                }
            }
        }
        .buttonStyle(.inset)
    }

    @ViewBuilder
    private var notices: some View {
        if let error = handoffs.installError {
            noticeRow(error, color: DaddyTheme.failure, systemImage: "exclamationmark.triangle.fill") {
                handoffs.installError = nil
            }
        }
        if let notice = handoffs.installNotice {
            noticeRow(notice, color: DaddyTheme.working, systemImage: "checkmark.circle.fill") {
                handoffs.installNotice = nil
            }
        }
    }

    private func noticeRow(
        _ text: String, color: Color, systemImage: String, dismiss: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).font(.system(size: 10))
            Text(text).font(.system(size: 10, design: .monospaced))
            Spacer(minLength: 6)
            Button("dismiss", action: dismiss).buttonStyle(.inset)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: States

    private func placeholder(_ text: String) -> some View {
        VStack {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(DaddyTheme.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Shown when a project has batch documents but no installed contract —
    /// a nudge, not a wall.
    private func contractNudge(_ project: Project) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 10))
            Text("No working agreement installed — agents may not follow the format")
                .font(.system(size: 10))
            Spacer(minLength: 6)
            Button("Install") { handoffs.installContract(into: project) }
                .buttonStyle(.inset)
        }
        .foregroundStyle(DaddyTheme.limited)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func notConfigured(_ project: Project) -> some View {
        VStack(spacing: 14) {
            Text("\(project.name) has no working agreement")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DaddyTheme.textPrimary)

            Text("""
            Installs AGENTS.md — read by Codex, Cursor and opencode — plus a \
            one-line CLAUDE.md that imports it. Every CLI then follows the same \
            workflow and writes its batch documents to \
            \(WorkflowContract.handoffDirectory)/.
            """)
                .font(.system(size: 10.5))
                .foregroundStyle(DaddyTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Button("Install working agreement") {
                handoffs.installContract(into: project)
            }
            .buttonStyle(.inset(DaddyTheme.textPrimary))

            Text("Existing AGENTS.md / CLAUDE.md are copied to .bak first")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(DaddyTheme.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private func emptyState(_ project: Project) -> some View {
        VStack(spacing: 10) {
            Text("No batches yet")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DaddyTheme.textPrimary)

            Text("""
            Agents write them to \(WorkflowContract.handoffDirectory)/ as they work. \
            The next one will be \(String(format: "%03d", handoffs.nextNumber(for: project))).
            """)
                .font(.system(size: 10.5))
                .foregroundStyle(DaddyTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private var documentList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let resume = handoffs.overview?.resumeAt {
                    resumeBanner(resume)
                }

                ForEach(handoffs.documents) { doc in
                    BatchCard(
                        project: store.selectedProject,
                        doc: doc,
                        isResumePoint: handoffs.overview?.resumeAt?.id == doc.id
                    )
                }
            }
            .padding(16)
        }
    }

    private func resumeBanner(_ doc: HandoffDoc) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(DaddyTheme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("A new agent should resume here")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DaddyTheme.textPrimary)
                Text("\(doc.filename) — \(doc.title)")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(DaddyTheme.textSecondary)
            }

            Spacer(minLength: 6)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .insetSurface(cornerRadius: 14, selected: true)
    }
}

// MARK: - Batch card

struct BatchCard: View {
    @Environment(AppStore.self) private var store
    @Environment(HandoffViewModel.self) private var handoffs

    let project: Project?
    let doc: HandoffDoc
    let isResumePoint: Bool

    @State private var expanded = false
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(String(format: "%03d", doc.number))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(DaddyTheme.textMuted)

                Text(doc.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(
                        doc.status == .done ? DaddyTheme.textSecondary : DaddyTheme.textPrimary
                    )

                Spacer(minLength: 8)

                if let agent = doc.agent {
                    Text(agent.rawValue)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(DaddyTheme.textMuted)
                }

                statusPill
            }

            if doc.totalCount > 0 {
                progressBar
            }

            if expanded {
                detail
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .insetSurface(cornerRadius: 16, selected: isResumePoint, filled: hovering)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture { withAnimation(.smooth(duration: 0.25)) { expanded.toggle() } }
    }

    private var statusColor: Color {
        switch doc.status {
        case .done: return DaddyTheme.working
        case .inProgress: return DaddyTheme.accent
        case .planned: return DaddyTheme.idle
        case .stalled: return DaddyTheme.limited
        }
    }

    private var statusLabel: String {
        switch doc.status {
        case .done: return "DONE"
        case .inProgress: return "IN PROGRESS"
        case .planned: return "PLANNED"
        case .stalled: return "NEEDS CLOSING"
        }
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            Circle().fill(statusColor).frame(width: 5, height: 5)
            Text(statusLabel)
                .font(.system(size: 8.5, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .insetCapsule(tint: statusColor, opacity: 0.12)
    }

    private var progressBar: some View {
        HStack(spacing: 9) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(statusColor.opacity(0.75))
                        .frame(width: geo.size.width * doc.progress)
                }
            }
            .frame(height: 4)

            Text("\(doc.completedCount)/\(doc.totalCount)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(DaddyTheme.textMuted)
        }
    }

    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassHairline()

            if let goal = doc.goal {
                labelled("GOAL", goal)
            }

            if !doc.outstandingTasks.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("OUTSTANDING")
                        .font(.system(size: 8.5, weight: .semibold))
                        .tracking(0.7)
                        .foregroundStyle(DaddyTheme.textMuted)

                    ForEach(Array(doc.outstandingTasks.enumerated()), id: \.offset) { _, task in
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: "square")
                                .font(.system(size: 8))
                                .foregroundStyle(DaddyTheme.textMuted)
                                .padding(.top, 2)
                            Text(task.title)
                                .font(.system(size: 10.5))
                                .foregroundStyle(DaddyTheme.textSecondary)
                        }
                    }
                }
            }

            if let summary = doc.summary { labelled("SUMMARY", summary) }
            if let changes = doc.changes { labelled("CHANGES", changes) }

            // The reason this whole feature exists.
            if let next = doc.nextSteps { labelled("NEXT POSSIBLE STEPS", next) }

            HStack(spacing: 8) {
                if let project, doc.status != .done {
                    // Hand this batch to an agent, already told what is left.
                    Menu("Continue with…") {
                        ForEach(AgentKind.allCases, id: \.rawValue) { kind in
                            Button(store.isInstalled(kind)
                                   ? kind.displayName
                                   : "\(kind.displayName) — not installed") {
                                handoffs.launchContinuing(doc, agent: kind, in: project)
                            }
                            .disabled(!store.isInstalled(kind))
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DaddyTheme.accent)
                    .fixedSize()
                }

                Button("Open") { NSWorkspace.shared.open(doc.url) }
                Button("Reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting([doc.url])
                }
                Spacer(minLength: 6)
                Text(doc.filename)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(DaddyTheme.textMuted)
            }
            .buttonStyle(.inset)
        }
    }

    private func labelled(_ label: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8.5, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(DaddyTheme.textMuted)
            Text(body)
                .font(.system(size: 10.5))
                .foregroundStyle(DaddyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
