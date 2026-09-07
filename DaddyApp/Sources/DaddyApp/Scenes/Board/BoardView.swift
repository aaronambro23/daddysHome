import SwiftUI
import AppKit

/// The project management workspace: work items as a Kanban board.
///
/// It is a *view* over the same `OrchestratorWorkItem`s the Orchestrator
/// captures and dispatches, read from and written to the same Markdown store.
/// There is no second database and no second copy of the truth — a card moved
/// here is the same item the Orchestrator can hand to a coding agent, and an
/// item an agent updates on disk shows up here on the next visit.
struct BoardView: View {
    @Environment(MockStore.self) private var store

    @State private var scope: BoardProjectScope = .all
    @State private var categoryFilter: OrchestratorWorkCategory?
    @State private var showArchived = false

    /// The card dropped into DISPATCHED, waiting on an agent. The move is not
    /// committed until one is picked — see `BoardDispatchPicker`.
    @State private var pendingDispatch: OrchestratorWorkItem?
    @State private var collapsedGroups: Set<BoardGroupKey> = []
    @State private var draggingID: UUID?
    /// The column under the pointer, updated only when it actually changes.
    /// The cursor location moves every few pixels and the columns must not
    /// rebuild for each one — only the floating card follows the pointer.
    @State private var dropTarget: OrchestratorWorkStatus?
    @State private var columnFrames: [OrchestratorWorkStatus: CGRect] = [:]
    @State private var keyboardMonitor: Any?
    /// The column Cmd+T adds into. Set by clicking a column or a card in it.
    @State private var selectedColumn: OrchestratorWorkStatus?

    @FocusState private var editorTitleFocused: Bool
    @FocusState private var editorSummaryFocused: Bool
    /// The item the last plus-button press created. Closed with an empty title
    /// means the add was abandoned, so it is deleted rather than left behind.
    @State private var justCreatedID: UUID?

    private var selectedItem: OrchestratorWorkItem? {
        guard let id = store.selectedOrchestratorWorkItemID else { return nil }
        return store.workItem(id)
    }

    private var items: [OrchestratorWorkItem] {
        store.boardWorkItems(scope: scope, category: categoryFilter, includeArchived: showArchived)
    }

    private var columns: [OrchestratorWorkStatus] {
        showArchived
            ? OrchestratorWorkStatus.boardColumns + [.archived]
            : OrchestratorWorkStatus.boardColumns
    }

    var body: some View {
        boardPane
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .trailing) { detailOverlay }
            .overlay { dispatchOverlay }
            .padding(18)
        .onAppear {
            syncScopeFromProject()
            installKeyboardMonitor()
        }
        .onDisappear { removeKeyboardMonitor() }
        .onChange(of: store.selectedProjectID) { _, _ in syncScopeFromProject() }
    }

    // MARK: - Board

    private var boardPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            columnsRow
        }
    }

    // No horizontal `ScrollView` around the columns. A vertical scroll view
    // inside a horizontal one makes a drag ambiguous, and the scroll views win
    // — the cards never lift. The columns share the width instead.
    private var columnsRow: some View {
        HStack(alignment: .top, spacing: 12) {
                let target = dropTarget
                let selectedID = store.selectedOrchestratorWorkItemID
                let visibleItems = items
                ForEach(columns, id: \.self) { status in
                    let columnItems = visibleItems.filter { $0.status.boardColumn == status }
                    BoardColumn(
                        status: status,
                        items: columnItems,
                        selectedID: columnItems.contains { $0.id == selectedID } ? selectedID : nil,
                        groupByCategory: categoryFilter == nil,
                        collapsed: collapsedGroups,
                        projectName: projectName(for:),
                        onSelect: { select($0) },
                        onArchive: { archive($0) },
                        onDelete: { AppActionDispatcher(store: store).perform(.deleteWorkItem(id: $0.id)) },
                        onSendToOrchestrator: { sendToOrchestrator($0) },
                        draggingID: draggingID,
                        isDropTarget: target == status,
                        onDragChanged: dragChanged,
                        onDragEnded: dragEnded,
                        onToggleGroup: toggleGroup,
                        onAdd: { addItem(in: status) },
                        onAddInCategory: { addItem(in: status, category: $0) },
                        isSelected: selectedColumn == status,
                        onSelectColumn: { selectedColumn = status }
                    )
                }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: BoardSpace.name)
        .onPreferenceChange(BoardColumnFrameKey.self) { new in
            // Preference writes during layout. Assigning every time invalidates
            // the board, and the board is glass over aurora — skip no-ops.
            if new != columnFrames { columnFrames = new }
        }
    }

    private func dragChanged(_ item: OrchestratorWorkItem, to point: CGPoint) {
        // Implicit animation interpolates the floating card toward the cursor
        // and the drop-target fills — that is the clump. Kill it for the drag.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if draggingID != item.id {
                draggingID = item.id
            }
            let target = columnFrames.first { $0.value.contains(point) }?.key
            if target != dropTarget { dropTarget = target }
        }
    }

    private func dragEnded(_ item: OrchestratorWorkItem, at point: CGPoint) {
        // Cards must land instantly. Animating a move reflows every column,
        // which fires column-frame preferences every tick, which invalidates
        // the glass, which is how the board drops to a few frames a second.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            draggingID = nil
            dropTarget = nil
            guard let target = columnFrames.first(where: { $0.value.contains(point) })?.key,
                  target != item.status.boardColumn else { return }

            // DISPATCHED means an agent has it. Rather than move the card and
            // leave you to go find one, the drop asks which agent — and only
            // commits once you have said. Dismissing leaves the card put.
            if target == .dispatched {
                pendingDispatch = item
                return
            }
            AppActionDispatcher(store: store).perform(.moveWorkItem(id: item.id, status: target, category: nil))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("BOARD")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(DaddyTheme.textPrimary)
                Text(scopeSubtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(DaddyTheme.textMuted)
            }

            Spacer(minLength: 0)

            scopePicker
            categoryPicker

            if !store.pendingSyncBuckets.isEmpty {
                Button {
                    store.syncPendingNow()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "icloud.slash")
                        Text("\(store.pendingSyncBuckets.count)")
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(DaddyTheme.textPrimary)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .insetSurface(cornerRadius: 8)
                }
                .buttonStyle(.plain)
                .help("Not backed up to Drive — click to sync now")
            }

            Button {
                showArchived.toggle()
            } label: {
                Image(systemName: showArchived ? "archivebox.fill" : "archivebox")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(showArchived ? DaddyTheme.accent : DaddyTheme.textMuted)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(showArchived ? "Hide archived" : "Show archived")

            Text("\(items.count)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(DaddyTheme.textMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { GlassHairline() }
    }

    private var scopePicker: some View {
        GlassDropdown(
            items: [
                GlassDropdownItem(id: "all", title: "All projects") { applyScope(.all) },
                GlassDropdownItem(id: "unassigned", title: "Unassigned") { applyScope(.unassigned) }
            ] + store.rootProjects.map { project in
                GlassDropdownItem(id: project.id, title: project.name) {
                    applyScope(.project(project.id))
                    // The rail and the board share one idea of "the project
                    // you are in", so picking here follows you back to Fleet.
                    store.select(project: project.id)
                }
            },
            width: 240
        ) {
            HStack(spacing: 5) {
                Image(systemName: "folder")
                    .font(.system(size: 9, weight: .semibold))
                Text(scopeTitle)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(DaddyTheme.textSecondary)
        }
    }

    private var categoryPicker: some View {
        GlassDropdown(
            items: [GlassDropdownItem(id: "all", title: "All categories") { categoryFilter = nil }]
                + OrchestratorWorkCategory.allCases.map { category in
                    GlassDropdownItem(
                        id: category.rawValue,
                        title: category.title,
                        // Doubles as the colour legend: the only place that
                        // pairs every category name with its swatch.
                        leading: AnyView(
                            Circle().fill(category.tint).frame(width: 7, height: 7)
                        )
                    ) {
                        categoryFilter = category
                    }
                },
            width: 210
        ) {
            HStack(spacing: 5) {
                if let categoryFilter {
                    Circle()
                        .fill(categoryFilter.tint)
                        .frame(width: 6, height: 6)
                } else {
                    categorySwatches
                }
                Text(categoryFilter?.title ?? "ALL")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(categoryFilter?.tint ?? DaddyTheme.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    /// All five swatches in a row when nothing is filtered — a legend small
    /// enough to live in the header, so the card stripes mean something the
    /// first time you look at the board.
    private var categorySwatches: some View {
        HStack(spacing: 2) {
            ForEach(OrchestratorWorkCategory.allCases) { category in
                Circle()
                    .fill(category.tint)
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var scopeTitle: String {
        switch scope {
        case .all: return "All projects"
        case .unassigned: return "Unassigned"
        case .project(let id): return store.project(id)?.name ?? "Unknown project"
        }
    }

    private var scopeSubtitle: String {
        switch scope {
        case .all: return "Every project, plus what has none"
        case .unassigned: return "Captures with no project yet"
        case .project: return "Drag a card to move it"
        }
    }

    // MARK: - Dispatch

    @ViewBuilder
    private var dispatchOverlay: some View {
        if let pendingDispatch {
            BoardDispatchPicker(item: pendingDispatch) {
                self.pendingDispatch = nil
            }
        }
    }

    // MARK: - Detail

    /// Overlay, not a sibling in the board `HStack`. The pane sits on top of
    /// the columns and the columns keep their width. Animation lives on this
    /// container only — wrapping selection in `withAnimation` also interpolated
    /// every card's selected state, which is what made opening a task hitch.
    @ViewBuilder
    private var detailOverlay: some View {
        ZStack(alignment: .trailing) {
            if let item = selectedItem {
                BoardDetailPane(
                    item: item,
                    titleFocus: $editorTitleFocused,
                    summaryFocus: $editorSummaryFocused,
                    onClose: closeDetail,
                    onSendToAgent: { pendingDispatch = item }
                )
                .frame(width: 340)
                .frame(maxHeight: .infinity)
                .padding(.vertical, 10)
                .padding(.trailing, 10)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxHeight: .infinity)
        .animation(.easeOut(duration: 0.2), value: store.selectedOrchestratorWorkItemID != nil)
    }

    // MARK: - Actions

    /// Escape, through a local `NSEvent` monitor rather than `.onKeyPress`.
    ///
    /// `.onKeyPress` only fires while the view holds keyboard focus, and the
    /// board never takes it — which is why the first attempt did nothing at
    /// all. This is the same mechanism `FleetView` uses for its shortcuts.
    private func installKeyboardMonitor() {
        guard keyboardMonitor == nil else { return }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard store.workspace == .board else { return event }

            let chords = event.modifierFlags.intersection([.command, .option, .control, .shift])

            // Cmd+T creates a new card in the selected column, or BACKLOG if
            // no column is selected.
            if event.keyCode == 17, chords == .command {
                addItem(in: selectedColumn ?? .inbox)
                return nil
            }

            guard event.keyCode == 53, chords.isEmpty else { return event }

            // The dispatch picker is modal over the whole board, so it owns
            // Escape ahead of everything under it.
            if pendingDispatch != nil {
                pendingDispatch = nil
                return nil
            }

            if store.selectedOrchestratorWorkItemID != nil {
                closeDetail()
                return nil
            }
            store.workspace = store.workspaceBeforeBoard
            return nil
        }
    }

    private func removeKeyboardMonitor() {
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
            self.keyboardMonitor = nil
        }
    }

    private func select(_ item: OrchestratorWorkItem) {
        justCreatedID = nil
        selectedColumn = item.status.boardColumn
        store.selectedOrchestratorWorkItemID = item.id
        // The pane animates in; focusing on the next runloop lands once it
        // exists rather than racing its appearance — same reasoning as
        // `addItem`'s title focus below.
        DispatchQueue.main.async { editorSummaryFocused = true }
    }

    private func closeDetail() {
        // An add abandoned before anything was typed leaves no card behind.
        if let id = justCreatedID,
           let item = store.workItem(id),
           item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            AppActionDispatcher(store: store).perform(.deleteWorkItem(id: id))
        }
        justCreatedID = nil
        editorTitleFocused = false
        editorSummaryFocused = false
        store.selectedOrchestratorWorkItemID = nil
    }

    /// The board follows Fleet's current project so cards from one repo do not
    /// keep sitting on another. "All" and "Unassigned" are explicit overrides.
    /// Subdirectories are not projects on this picker — fold them into the
    /// Documents-level folder they sit in.
    private func syncScopeFromProject() {
        if let id = store.selectedProjectID {
            let rootID = store.project(id)?.parentID ?? id
            applyScope(.project(rootID))
        } else {
            applyScope(.all)
        }
    }

    private func applyScope(_ new: BoardProjectScope) {
        scope = new
        guard let item = selectedItem else { return }
        switch new {
        case .all:
            break
        case .unassigned:
            if item.projectID != nil { closeDetail() }
        case .project(let id):
            if item.projectID != id { closeDetail() }
        }
    }

    private func projectName(for item: OrchestratorWorkItem) -> String? {
        guard case .all = scope else { return nil }
        guard let id = item.projectID else { return nil }
        return store.project(id)?.name
    }

    private func toggleGroup(_ key: BoardGroupKey) {
        if collapsedGroups.contains(key) {
            collapsedGroups.remove(key)
        } else {
            collapsedGroups.insert(key)
        }
    }

    /// The plus button creates the item straight away and opens it in the
    /// detail pane with the title focused, so naming it is one keystroke. The
    /// title starts empty — closing before typing anything deletes the item.
    private func addItem(in status: OrchestratorWorkStatus, category: OrchestratorWorkCategory? = nil) {
        let item = OrchestratorWorkItem(
            title: "",
            summary: "",
            rawCapture: "",
            category: category ?? categoryFilter ?? .other,
            status: status,
            projectID: addProjectID
        )
        AppActionDispatcher(store: store).perform(.createWorkItem(item))
        justCreatedID = item.id
        selectedColumn = status
        store.selectedOrchestratorWorkItemID = item.id
        // The pane animates in; focusing on the next runloop lands once it
        // exists rather than racing its appearance.
        DispatchQueue.main.async { editorTitleFocused = true }
    }

    private var addProjectID: String? {
        switch scope {
        case .all: return store.selectedProjectID
        case .unassigned: return nil
        case .project(let id): return id
        }
    }

    private func archive(_ item: OrchestratorWorkItem) {
        AppActionDispatcher(store: store).perform(.moveWorkItem(id: item.id, status: .archived, category: nil))
    }

    /// Dispatch lives in the Orchestrator — agent picker, session picker and
    /// an approval step. Rather than grow a second copy of all that here, the
    /// board selects the item and hands the window over.
    private func sendToOrchestrator(_ item: OrchestratorWorkItem) {
        store.selectedOrchestratorWorkItemID = item.id
        store.workspace = .orchestrator
    }
}

/// The detail pane as its own view, so typing in it does not rebuild the
/// board. The editor state used to live in `BoardView`, which meant every
/// keystroke re-evaluated the columns, the cards and the header — and
/// repainted the glass over the animating aurora. Now keystrokes invalidate
/// only this pane. Selection switches re-seed via `item.id`; saves keep the
/// state (seeded from the saved values, which is what is on screen).
private struct BoardDetailPane: View {
    @Environment(MockStore.self) private var store

    let item: OrchestratorWorkItem
    let titleFocus: FocusState<Bool>.Binding?
    let summaryFocus: FocusState<Bool>.Binding?
    let onClose: () -> Void
    /// Cmd+Return, from anywhere in the popup — see `installDeleteMonitor`,
    /// which now carries both chords despite the name.
    let onSendToAgent: () -> Void

    @State private var title: String
    @State private var summary: String
    @State private var category: OrchestratorWorkCategory
    @State private var status: OrchestratorWorkStatus
    @State private var priority: OrchestratorPriority
    @State private var projectID: String
    @State private var deleteKeyMonitor: Any?

    init(
        item: OrchestratorWorkItem,
        titleFocus: FocusState<Bool>.Binding? = nil,
        summaryFocus: FocusState<Bool>.Binding? = nil,
        onClose: @escaping () -> Void,
        onSendToAgent: @escaping () -> Void
    ) {
        self.item = item
        self.titleFocus = titleFocus
        self.summaryFocus = summaryFocus
        self.onClose = onClose
        self.onSendToAgent = onSendToAgent
        _title = State(initialValue: item.title)
        _summary = State(initialValue: item.summary)
        _category = State(initialValue: item.category)
        _status = State(initialValue: item.status.boardColumn)
        _priority = State(initialValue: item.priority)
        _projectID = State(initialValue: item.projectID ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("WORK ITEM")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(DaddyTheme.textSecondary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DaddyTheme.textMuted)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .overlay(alignment: .bottom) { GlassHairline() }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    WorkItemFields(
                        title: $title,
                        summary: $summary,
                        category: $category,
                        status: $status,
                        priority: $priority,
                        projectID: $projectID,
                        projects: store.rootProjects,
                        titleFocus: titleFocus,
                        summaryFocus: summaryFocus,
                        onSave: save,
                        onSaveAndClose: { save(); onClose() }
                    )

                    GlassHairline()

                    HStack(spacing: 10) {
                        WorkItemDispatchMenu(item: item, onWillDispatch: save)
                            .frame(maxWidth: .infinity)

                        Button("Delete") {
                            AppActionDispatcher(store: store).perform(.deleteWorkItem(id: item.id))
                        }
                        .buttonStyle(.insetLarge(DaddyTheme.failure))
                    }

                    if !item.rawCapture.isEmpty, item.rawCapture != item.summary {
                        Text("ORIGINAL CAPTURE")
                            .workItemFieldLabel()
                        Text(item.rawCapture)
                            .font(.system(size: 10))
                            .foregroundStyle(DaddyTheme.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
        }
        .glassPanel()
        .onChange(of: item.id) { _, _ in seed(from: item) }
        .onAppear { installDeleteMonitor() }
        .onDisappear { removeDeleteMonitor() }
    }

    /// Cmd+Backspace (delete) and Cmd+Return (send to agent), alongside the
    /// existing buttons. A local monitor rather than `.onKeyPress` for the
    /// same reason the board's Escape handling is one — the pane never holds
    /// keyboard focus itself while a text field inside it does. Escape's own
    /// handling lives entirely in `BoardView` and is untouched by this.
    private func installDeleteMonitor() {
        guard deleteKeyMonitor == nil else { return }
        deleteKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let chords = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard chords == .command else { return event }
            // 51 is Delete — the backspace key, which is what ⌘⌫ means on a Mac.
            if event.keyCode == 51 {
                deleteWithUndo()
                return nil
            }
            // 36 is Return.
            if event.keyCode == 36 {
                save()
                onSendToAgent()
                return nil
            }
            return event
        }
    }

    private func removeDeleteMonitor() {
        if let deleteKeyMonitor {
            NSEvent.removeMonitor(deleteKeyMonitor)
            self.deleteKeyMonitor = nil
        }
    }

    /// Deletes the item and closes the pane, leaving a 5s toast with an Undo
    /// that recreates it — the same toast/undo mechanism voice actions use.
    private func deleteWithUndo() {
        guard let current = store.workItem(item.id) else { return }
        AppActionDispatcher(store: store).perform(.deleteWorkItem(id: item.id))
        onClose()
        let label = current.title.trimmingCharacters(in: .whitespacesAndNewlines)
        store.showVoiceToast(VoiceToast(
            label: "Deleted \"\(label.isEmpty ? "Untitled" : label)\"",
            undoAction: .createWorkItem(current),
            icon: nil
        ))
    }

    private func seed(from item: OrchestratorWorkItem) {
        title = item.title
        summary = item.summary
        category = item.category
        status = item.status.boardColumn
        priority = item.priority
        projectID = item.projectID ?? ""
    }

    private func save() {
        guard var fresh = store.workItem(item.id) else { return }
        fresh.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        fresh.summary = summary
        fresh.category = category
        fresh.status = status
        fresh.priority = priority
        fresh.projectID = projectID.isEmpty ? nil : projectID
        fresh.updatedAt = Date()
        AppActionDispatcher(store: store).perform(.replaceWorkItem(fresh))
    }
}
