import Foundation

/// Reads handoff documents out of projects and derives the overview.
///
/// Daddy is the PM: agents own their individual batch documents, Daddy owns the
/// aggregate view. Nothing here writes to an agent's document — the overview is
/// always derived, so it can never go stale or conflict the way a shared
/// `DONE.md` maintained by four different CLIs would.
public struct HandoffStore: Sendable {

    public init() {}

    /// Absolute path to a project's handoff directory.
    public func handoffDirectory(for projectPath: URL) -> URL {
        projectPath.appendingPathComponent(WorkflowContract.handoffDirectory)
    }

    /// True when the project has been set up for the workflow.
    public func isConfigured(projectPath: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: projectPath.appendingPathComponent("AGENTS.md").path
        )
    }

    /// Every batch document in a project, ordered by number.
    public func documents(in projectPath: URL, projectID: String) -> [HandoffDoc] {
        let directory = handoffDirectory(for: projectPath)

        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries
            .filter { $0.pathExtension.lowercased() == "md" }
            .compactMap { HandoffParser.parse(contentsOf: $0, projectID: projectID) }
            .sorted { $0.number < $1.number }
    }

    /// The next unused batch number, for suggesting a filename.
    public func nextNumber(in projectPath: URL, projectID: String) -> Int {
        (documents(in: projectPath, projectID: projectID).map(\.number).max() ?? 0) + 1
    }

    // MARK: - Derived overview

    public struct Overview: Sendable {
        public let total: Int
        public let done: Int
        public let inProgress: Int
        public let planned: Int
        public let stalled: Int
        public let outstandingTasks: Int

        /// The document a new agent should read first: the earliest one that is
        /// not finished. Nil when everything is done.
        public let resumeAt: HandoffDoc?
    }

    public func overview(of documents: [HandoffDoc]) -> Overview {
        Overview(
            total: documents.count,
            done: documents.filter { $0.status == .done }.count,
            inProgress: documents.filter { $0.status == .inProgress }.count,
            planned: documents.filter { $0.status == .planned }.count,
            stalled: documents.filter { $0.status == .stalled }.count,
            outstandingTasks: documents.reduce(0) { $0 + $1.outstandingTasks.count },
            resumeAt: documents.first { $0.status != .done }
        )
    }

    /// Renders the derived overview as Markdown, for writing out as `DONE.md`
    /// so the state is readable outside the app too.
    public func renderOverviewMarkdown(
        projectName: String,
        documents: [HandoffDoc]
    ) -> String {
        let summary = overview(of: documents)
        var out = """
        # \(projectName) — batch overview

        _Derived by Daddy from `\(WorkflowContract.handoffDirectory)/`. Do not edit;
        this file is regenerated. Edit the individual batch documents instead._

        \(summary.done)/\(summary.total) batches complete · \
        \(summary.outstandingTasks) tasks outstanding

        """

        for doc in documents {
            let mark: String
            switch doc.status {
            case .done: mark = "x"
            case .stalled, .inProgress, .planned: mark = " "
            }

            let counts = doc.totalCount > 0
                ? " (\(doc.completedCount)/\(doc.totalCount))"
                : ""
            let flag = doc.status == .stalled ? "  ⚠️ all tasks ticked, not marked done" : ""

            out += "- [\(mark)] `\(doc.filename)` — \(doc.title)\(counts)\(flag)\n"
        }

        if let resume = summary.resumeAt {
            out += "\n**Resume at:** `\(resume.filename)` — \(resume.title)\n"
        }

        return out
    }
}
