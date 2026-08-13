import SwiftUI
import DaddyCore

/// Reads handoff documents for the selected project and keeps them fresh.
///
/// This is the PM half of Daddy: it never writes to an agent's batch document,
/// it only reads them and derives the overview.
@Observable
final class HandoffViewModel {
    private(set) var documents: [HandoffDoc] = []
    private(set) var overview: HandoffStore.Overview?
    private(set) var isConfigured = false
    private(set) var lastScannedPath: String?

    var installError: String?
    var installNotice: String?

    @ObservationIgnored private let store = HandoffStore()
    @ObservationIgnored private let installer = ContractInstaller()

    // MARK: - Cross-project overview

    /// One project's batch state, for the Overview tab.
    struct ProjectSummary: Identifiable {
        let project: Project
        let overview: HandoffStore.Overview
        let isConfigured: Bool
        let lastActivity: Date?

        var id: String { project.id }
    }

    /// Something a PM would want flagged.
    struct AttentionItem: Identifiable {
        enum Kind {
            /// Every task ticked, but the document was never marked done.
            case stalled
            /// No document touched in a while.
            case idle

            var symbol: String {
                switch self {
                case .stalled: return "exclamationmark.triangle.fill"
                case .idle: return "clock.badge.questionmark"
                }
            }

            var color: Color {
                switch self {
                case .stalled: return DaddyTheme.limited
                case .idle: return DaddyTheme.idle
                }
            }
        }

        let id = UUID()
        let kind: Kind
        let projectID: String
        let title: String
        let detail: String
    }

    private(set) var summaries: [ProjectSummary] = []
    private(set) var attentionItems: [AttentionItem] = []

    /// Unticked tasks across every tracked project.
    var totalOutstandingTasks: Int {
        summaries.reduce(0) { $0 + $1.overview.outstandingTasks }
    }

    /// Unticked tasks for one project, from the last cross-project scan.
    func outstandingTasks(for projectID: String) -> Int {
        summaries.first { $0.project.id == projectID }?.overview.outstandingTasks ?? 0
    }

    /// Days without a document changing before a project is called idle.
    private let idleThresholdDays = 7

    /// Reads every project. Only projects that actually have batch documents
    /// are surfaced — otherwise the Overview would list every directory in
    /// ~/Documents, most of which are not agent work.
    func scanAll(projects: [Project]) {
        var found: [ProjectSummary] = []
        var flags: [AttentionItem] = []

        for project in projects {
            let url = project.expandedURL
            let docs = store.documents(in: url, projectID: project.id)
            guard !docs.isEmpty else { continue }

            let overview = store.overview(of: docs)
            let lastActivity = docs.map(\.modifiedAt).max()

            found.append(
                ProjectSummary(
                    project: project,
                    overview: overview,
                    isConfigured: installer.isInstalled(in: url),
                    lastActivity: lastActivity
                )
            )

            // A batch with everything ticked but no "done" status is the most
            // common real-world failure: the agent finished and forgot to close
            // the document, so the next one cannot tell if it is safe to move on.
            for doc in docs where doc.status == .stalled {
                flags.append(
                    AttentionItem(
                        kind: .stalled,
                        projectID: project.id,
                        title: "\(project.name) · \(doc.filename)",
                        detail: "All \(doc.totalCount) tasks ticked but never marked done"
                    )
                )
            }

            if let lastActivity,
               overview.resumeAt != nil,
               let days = Calendar.current.dateComponents(
                   [.day], from: lastActivity, to: Date()
               ).day,
               days >= idleThresholdDays {
                flags.append(
                    AttentionItem(
                        kind: .idle,
                        projectID: project.id,
                        title: project.name,
                        detail: "Unfinished work, untouched for \(days) days"
                    )
                )
            }
        }

        summaries = found.sorted {
            ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast)
        }
        attentionItems = flags
    }

    /// Re-reads the project from disk. Cheap enough to call on a timer — these
    /// are a handful of small Markdown files.
    func refresh(project: Project?) {
        guard let project else {
            documents = []
            overview = nil
            isConfigured = false
            lastScannedPath = nil
            return
        }

        let url = project.expandedURL
        lastScannedPath = url.path
        isConfigured = installer.isInstalled(in: url)

        let docs = store.documents(in: url, projectID: project.id)
        documents = docs
        overview = store.overview(of: docs)
    }

    func handoffDirectory(for project: Project) -> URL {
        store.handoffDirectory(for: project.expandedURL)
    }

    func nextNumber(for project: Project) -> Int {
        store.nextNumber(in: project.expandedURL, projectID: project.id)
    }

    /// Installs the cross-CLI working agreement into the project.
    func installContract(into project: Project) {
        installError = nil
        installNotice = nil

        do {
            let result = try installer.install(
                into: project.expandedURL,
                projectName: project.name
            )

            var notice = "Installed AGENTS.md + CLAUDE.md in \(project.name)"
            if !result.backedUp.isEmpty {
                let names = result.backedUp.map(\.lastPathComponent).joined(separator: ", ")
                notice += " · backed up \(names)"
            }
            installNotice = notice
            refresh(project: project)
        } catch {
            installError = error.localizedDescription
        }
    }

    /// Writes the derived overview out as `DONE.md` so the state is readable
    /// outside the app. Daddy owns this file; agents are told not to touch it.
    func writeOverview(for project: Project) {
        let markdown = store.renderOverviewMarkdown(
            projectName: project.name,
            documents: documents
        )
        let url = handoffDirectory(for: project).appendingPathComponent("DONE.md")
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            installNotice = "Wrote \(url.lastPathComponent)"
        } catch {
            installError = "Could not write DONE.md: \(error.localizedDescription)"
        }
    }

    /// The brief you hand to a fresh agent so it does not have to be
    /// re-explained the project. This is the whole point of the feature.
    func handoffBrief(for project: Project) -> String {
        guard let overview, !documents.isEmpty else {
            return "No handoff documents yet in \(project.name)."
        }

        var out = """
        Project: \(project.name)
        Path: \(project.expandedURL.path)

        Read \(WorkflowContract.handoffDirectory)/ before doing anything. \
        \(overview.done) of \(overview.total) batches are complete, \
        \(overview.outstandingTasks) tasks outstanding.


        """

        if let resume = overview.resumeAt {
            out += "START HERE: \(resume.filename) — \(resume.title)\n\n"
            if let goal = resume.goal {
                out += "Goal: \(goal)\n\n"
            }
            if !resume.outstandingTasks.isEmpty {
                out += "Still to do:\n"
                for task in resume.outstandingTasks {
                    out += "  - [ ] \(task.title)\n"
                }
                out += "\n"
            }
        }

        let completed = documents.filter { $0.status == .done }
        if !completed.isEmpty {
            out += "Already done:\n"
            for doc in completed {
                out += "  - \(doc.filename) — \(doc.title)\n"
                if let summary = doc.summary {
                    out += "      \(summary.replacingOccurrences(of: "\n", with: " "))\n"
                }
            }
            out += "\n"
        }

        // The previous agent's opinion is the most valuable part to carry over.
        if let latest = completed.last, let next = latest.nextSteps {
            out += "The previous agent suggested next:\n\(next)\n"
        }

        return out
    }
}
