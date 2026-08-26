import SwiftUI
import AppKit

/// The editable face of an `OrchestratorWorkItem`.
///
/// Extracted from the Orchestrator's inspector so the board's detail pane and
/// the inspector cannot drift apart — there is one definition of what a work
/// item's fields look like and one definition of what "save" writes.
///
/// Dispatch is deliberately *not* here. Sending an item to a coding agent
/// needs an agent picker, a session picker and an approval step, and all of
/// that belongs to the Orchestrator; the board hands off to it rather than
/// growing a second copy.
struct WorkItemFields: View {
    @Binding var title: String
    @Binding var summary: String
    @Binding var category: OrchestratorWorkCategory
    @Binding var status: OrchestratorWorkStatus
    @Binding var priority: OrchestratorPriority
    @Binding var projectID: String

    let projects: [MockProject]

    /// Focused by the board when it creates a card, so a new item can be named
    /// without reaching for the mouse. The inspector passes nothing.
    var titleFocus: FocusState<Bool>.Binding?

    /// Called on Enter in the title field as well as by the save button, so a
    /// freshly created card commits with one keystroke.
    let onSave: () -> Void

    @State private var copied = false

    init(
        title: Binding<String>,
        summary: Binding<String>,
        category: Binding<OrchestratorWorkCategory>,
        status: Binding<OrchestratorWorkStatus>,
        priority: Binding<OrchestratorPriority>,
        projectID: Binding<String>,
        projects: [MockProject],
        titleFocus: FocusState<Bool>.Binding? = nil,
        onSave: @escaping () -> Void
    ) {
        _title = title
        _summary = summary
        _category = category
        _status = status
        _priority = priority
        _projectID = projectID
        self.projects = projects
        self.titleFocus = titleFocus
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("TITLE")
                    .workItemFieldLabel()
                Spacer(minLength: 0)
                copyButton
            }
            titleField

            Text("SUMMARY")
                .workItemFieldLabel()
            TextEditor(text: $summary)
                .font(.system(size: 11))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 100)
                .padding(7)
                .insetSurface(cornerRadius: 10)

            Picker("Category", selection: $category) {
                ForEach(OrchestratorWorkCategory.allCases) { category in
                    Text(category.title).tag(category)
                }
            }
            Picker("Status", selection: $status) {
                ForEach(OrchestratorWorkStatus.editableStatuses, id: \.self) { status in
                    Text(status.title).tag(status)
                }
            }
            Picker("Priority", selection: $priority) {
                ForEach(OrchestratorPriority.allCases, id: \.self) { priority in
                    Text(priority.rawValue.capitalized).tag(priority)
                }
            }
            Picker("Project", selection: $projectID) {
                Text("No project").tag("")
                ForEach(projects) { project in
                    Text(project.name).tag(project.id)
                }
            }

            Button("save work item", action: onSave)
                .buttonStyle(.inset)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // `focused(_:)` needs a concrete binding, so the two cases are built
    // separately rather than conditionally applying the modifier — a
    // conditional modifier would change the view's identity and drop focus the
    // moment the field was typed into.
    @ViewBuilder
    private var titleField: some View {
        if let titleFocus {
            baseTitleField
                .focused(titleFocus)
        } else {
            baseTitleField
        }
    }

    private var baseTitleField: some View {
        TextField("Title", text: $title)
            .textFieldStyle(.plain)
            .onSubmit(onSave)
            .padding(9)
            .insetSurface(cornerRadius: 10)
    }

    private var copyButton: some View {
        Button(action: copyTitleAndSummary) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(copied ? DaddyTheme.ready : DaddyTheme.textMuted)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Copy title: summary")
    }

    /// What you paste into an agent session: `Title: summary`. Empty summary
    /// drops the colon so you are not left with a trailing separator.
    private func copyTitleAndSummary() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = trimmedSummary.isEmpty
            ? trimmedTitle
            : "\(trimmedTitle): \(trimmedSummary)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            copied = false
        }
    }
}

extension View {
    func workItemFieldLabel(tint: Color = DaddyTheme.textMuted) -> some View {
        font(.system(size: 9, weight: .bold))
            .tracking(0.7)
            .foregroundStyle(tint)
    }
}
