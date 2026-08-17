import SwiftUI

struct FileTreeView: View {
    let project: MockProject?
    @State private var inProgressTasks: [String] = []
    @State private var completedTasks: [String] = []
    @State private var isDoneExists = false
    @State private var lastRefresh = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "PROGRESS") {
                HeaderCaption(text: "handoffs")
            }

            ScrollView {
                if project != nil {
                    VStack(alignment: .leading, spacing: 16) {
                        // DONE status
                        doneStatusSection

                        Divider()
                            .opacity(0.3)

                        // In progress
                        if !inProgressTasks.isEmpty {
                            tasksSection(
                                title: "IN PROGRESS",
                                tasks: inProgressTasks,
                                isDone: false
                            )
                        }

                        // Completed
                        if !completedTasks.isEmpty {
                            tasksSection(
                                title: "COMPLETED",
                                tasks: completedTasks,
                                isDone: true
                            )
                        }

                        if inProgressTasks.isEmpty && completedTasks.isEmpty {
                            Text("No handoff documents yet")
                                .font(.system(size: 11))
                                .foregroundStyle(DaddyTheme.textMuted)
                                .padding(.vertical, 20)
                        }
                    }
                    .padding(16)
                } else {
                    VStack(spacing: 8) {
                        Text("No project selected")
                            .font(.system(size: 11))
                            .foregroundStyle(DaddyTheme.textSecondary)

                        Text("Pick a project or open documents from an agent card.")
                            .font(.system(size: 10))
                            .foregroundStyle(DaddyTheme.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                }
            }
        }
        .glassPanel()
        .onAppear { refreshFileTree() }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            refreshFileTree()
        }
    }

    @ViewBuilder
    private var doneStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PROJECT STATUS")
                .font(.system(size: 9, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(DaddyTheme.textMuted)

            HStack(spacing: 8) {
                Image(systemName: isDoneExists ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isDoneExists ? DaddyTheme.working : DaddyTheme.textMuted)

                Text(isDoneExists ? "All tasks complete" : "Work in progress")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isDoneExists ? DaddyTheme.working : DaddyTheme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .insetSurface(cornerRadius: 10, filled: isDoneExists)
        }
    }

    private func tasksSection(title: String, tasks: [String], isDone: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(isDone ? Color(hex: "#8fe9bb") : Color(hex: "#ecca8f"))

                Spacer()

                Text("\(tasks.count)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isDone ? Color(hex: "#8fe9bb") : Color(hex: "#ecca8f"))
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(tasks, id: \.self) { task in
                    taskRow(task, isDone: isDone)
                }
            }
        }
    }

    private func taskRow(_ task: String, isDone: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isDone ? Color(hex: "#8fe9bb") : Color(hex: "#ecca8f"))

            Text(task)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(isDone ? DaddyTheme.textMuted : DaddyTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .insetSurface(cornerRadius: 8)
    }

    /// Where the handoff documents actually are.
    ///
    /// `WorkflowContract` tells every agent to write to `docs/handoffs`, and
    /// they do — but `SessionManager` creates its own stubs under
    /// `documents/handoffs`, and this panel only ever read the latter. So it
    /// showed a list of empty generated files while the real, agent-authored
    /// documents sat unread in the other directory. Prefer the contract's path
    /// and fall back to the stubs for projects that only have those.
    static func handoffsPath(for project: MockProject) -> String {
        let contractPath = project.path + "/docs/handoffs"
        if FileManager.default.fileExists(atPath: contractPath) {
            return contractPath
        }
        return project.path + "/documents/handoffs"
    }

    private func refreshFileTree() {
        guard let project = project else { return }

        let handoffsPath = Self.handoffsPath(for: project)
        let fm = FileManager.default

        var inProgress: [String] = []
        var completed: [String] = []
        var doneExists = false

        if let contents = try? fm.contentsOfDirectory(atPath: handoffsPath) {
            for item in contents.sorted() {
                if item == "DONE.md" {
                    doneExists = true
                } else if item == "done" {
                    // Read completed tasks from done/ subdirectory
                    let donePath = handoffsPath + "/done"
                    if let doneContents = try? fm.contentsOfDirectory(atPath: donePath) {
                        completed = doneContents.filter { $0.hasSuffix(".md") }.map {
                            $0.replacingOccurrences(of: ".md", with: "")
                        }
                    }
                } else if item.hasSuffix(".md") {
                    inProgress.append(item.replacingOccurrences(of: ".md", with: ""))
                }
            }
        }

        self.inProgressTasks = inProgress
        self.completedTasks = completed
        self.isDoneExists = doneExists
        self.lastRefresh = Date()
    }
}
