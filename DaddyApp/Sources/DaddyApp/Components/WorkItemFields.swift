import SwiftUI
import AppKit

/// The editable face of an `OrchestratorWorkItem`.
///
/// Extracted from the Orchestrator's inspector so the board's detail pane and
/// the inspector cannot drift apart — there is one definition of what a work
/// item's fields look like and one definition of what "save" writes.
///
/// Dispatch is deliberately *not* here. Sending an item to a coding agent
/// lives on the board's detail pane (and the Orchestrator's own DISPATCH
/// block), so this stays a form.
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
    /// freshly created card commits with one keystroke. Dropdowns call it on
    /// pick too — a status change should not wait on a separate save.
    let onSave: () -> Void

    @State private var copied = false

    /// Tab order through the form: title → summary → category → status →
    /// priority → project → save → back to title. Each field hands Tab to the
    /// next explicitly (`.handled`) rather than trusting the key loop, because
    /// the loop's order through popover triggers is not the visual order.
    @FocusState private var summaryFocused: Bool
    @FocusState private var categoryFocused: Bool
    @FocusState private var statusFocused: Bool
    @FocusState private var priorityFocused: Bool
    @FocusState private var projectFocused: Bool
    @FocusState private var saveFocused: Bool

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
                .focused($summaryFocused)
                .onKeyPress { press in
                    guard press.key == .tab else { return .ignored }
                    if press.modifiers.contains(.shift) {
                        titleFocus?.wrappedValue = true
                    } else {
                        categoryFocused = true
                    }
                    return .handled
                }

            FieldRow(
                label: "CATEGORY",
                items: OrchestratorWorkCategory.allCases.map { option in
                    GlassDropdownItem(
                        id: option.rawValue,
                        title: option.title,
                        isSelected: option == category,
                        leading: AnyView(
                            Circle().fill(option.tint).frame(width: 7, height: 7)
                        )
                    ) {
                        guard category != option else { return }
                        pick { category = option }
                    }
                },
                selectedIndex: OrchestratorWorkCategory.allCases.firstIndex(of: category),
                focus: $categoryFocused,
                onTabForward: { statusFocused = true },
                onTabBackward: { summaryFocused = true }
            ) {
                fieldTrigger(
                    title: category.title,
                    tint: category.tint,
                    leading: AnyView(
                        Circle().fill(category.tint).frame(width: 7, height: 7)
                    )
                )
            }

            FieldRow(
                label: "STATUS",
                items: OrchestratorWorkStatus.editableStatuses.map { option in
                    GlassDropdownItem(
                        id: option.rawValue,
                        title: option.title,
                        isSelected: option == status,
                        leading: AnyView(
                            Circle().fill(option.boardTint).frame(width: 7, height: 7)
                        )
                    ) {
                        guard status != option else { return }
                        pick { status = option }
                    }
                },
                selectedIndex: OrchestratorWorkStatus.editableStatuses.firstIndex(of: status),
                focus: $statusFocused,
                onTabForward: { priorityFocused = true },
                onTabBackward: { categoryFocused = true }
            ) {
                fieldTrigger(
                    title: status.title,
                    tint: status.boardTint,
                    leading: AnyView(
                        Circle().fill(status.boardTint).frame(width: 7, height: 7)
                    )
                )
            }

            FieldRow(
                label: "PRIORITY",
                items: OrchestratorPriority.allCases.map { option in
                    GlassDropdownItem(
                        id: option.rawValue,
                        title: option.title,
                        isSelected: option == priority,
                        leading: AnyView(
                            Circle().fill(option.tint).frame(width: 7, height: 7)
                        )
                    ) {
                        guard priority != option else { return }
                        pick { priority = option }
                    }
                },
                selectedIndex: OrchestratorPriority.allCases.firstIndex(of: priority),
                focus: $priorityFocused,
                onTabForward: { projectFocused = true },
                onTabBackward: { statusFocused = true }
            ) {
                fieldTrigger(
                    title: priority.title,
                    tint: priority.tint,
                    leading: AnyView(
                        Circle().fill(priority.tint).frame(width: 7, height: 7)
                    )
                )
            }

            FieldRow(
                label: "PROJECT",
                items: [GlassDropdownItem(
                    id: "",
                    title: "No project",
                    isSelected: projectID.isEmpty
                ) {
                    guard !projectID.isEmpty else { return }
                    pick { projectID = "" }
                }] + projects.map { project in
                    GlassDropdownItem(
                        id: project.id,
                        title: project.name,
                        isSelected: project.id == projectID
                    ) {
                        guard projectID != project.id else { return }
                        pick { projectID = project.id }
                    }
                },
                selectedIndex: projectID.isEmpty
                    ? 0
                    : projects.firstIndex(where: { $0.id == projectID }).map { $0 + 1 },
                focus: $projectFocused,
                onTabForward: { saveFocused = true },
                onTabBackward: { priorityFocused = true }
            ) {
                fieldTrigger(
                    title: projects.first { $0.id == projectID }?.name ?? "No project",
                    tint: DaddyTheme.textPrimary
                )
            }

            Button("save work item", action: onSave)
                .buttonStyle(.inset)
                .focused($saveFocused)
                .onKeyPress { press in
                    guard press.key == .tab else { return .ignored }
                    if press.modifiers.contains(.shift) {
                        projectFocused = true
                    } else {
                        titleFocus?.wrappedValue = true
                    }
                    return .handled
                }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func pick(_ apply: () -> Void) {
        apply()
        onSave()
    }

    private struct FieldRow<Trigger: View>: View {
        let label: String
        let items: [GlassDropdownItem]
        var selectedIndex: Int?
        var focus: FocusState<Bool>.Binding
        var onTabForward: () -> Void
        var onTabBackward: () -> Void
        @ViewBuilder let trigger: () -> Trigger

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .workItemFieldLabel()
                GlassDropdown(
                    items: items,
                    width: 268,
                    chromelessLabel: true,
                    selectedIndex: selectedIndex,
                    onTabForward: onTabForward,
                    onTabBackward: onTabBackward,
                    triggerFocus: focus,
                    label: trigger
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func fieldTrigger(title: String, tint: Color, leading: AnyView? = nil) -> some View {
        HStack(spacing: 8) {
            if let leading { leading }
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(DaddyTheme.textMuted)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .insetSurface(cornerRadius: 10)
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
            .onKeyPress { press in
                guard press.key == .tab else { return .ignored }
                // The external focus binding is level-triggered: leaving it
                // true while focus moves on means setting it again later is a
                // no-op, so clear it on the way out.
                titleFocus?.wrappedValue = false
                if press.modifiers.contains(.shift) {
                    saveFocused = true
                } else {
                    summaryFocused = true
                }
                return .handled
            }
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
