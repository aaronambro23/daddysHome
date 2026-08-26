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

    @State private var composingColumn: OrchestratorWorkStatus?
    @State private var composeText = ""
    @State private var collapsedGroups: Set<BoardGroupKey> = []
    @State private var dragState: BoardDragState?
    @State private var columnFrames: [OrchestratorWorkStatus: CGRect] = [:]
    @State private var keyboardMonitor: Any?

    @State private var editorTitle = ""
    @State private var editorSummary = ""
    @State private var editorCategory: OrchestratorWorkCategory = .other
    @State private var editorStatus: OrchestratorWorkStatus = .inbox
    @State private var editorPriority: OrchestratorPriority = .medium
    @State private var editorProjectID = ""

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
            .padding(18)
        .onAppear {
            // Cheap, and the alternative is a board that quietly lies about
            // what is on disk after an agent edited a work item.
            store.reloadWorkItems()
            syncScopeFromProject()
            syncEditor()
            installKeyboardMonitor()
        }
        .onDisappear { removeKeyboardMonitor() }
        .onChange(of: store.selectedOrchestratorWorkItemID) { _, _ in syncEditor() }
        .onChange(of: store.selectedProjectID) { _, _ in syncScopeFromProject() }
    }

    // MARK: - Board

    private var boardPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            columnsRow
        }
        .glassPanel()
    }

    // No horizontal `ScrollView` around the columns. A vertical scroll view
    // inside a horizontal one makes a drag ambiguous, and the scroll views win
    // — the cards never lift. The columns share the width instead.
    private var columnsRow: some View {
        HStack(alignment: .top, spacing: 12) {
                let target = dropTarget
                ForEach(columns, id: \.self) { status in
                    BoardColumn(
                        status: status,
                        items: items.filter { $0.status.boardColumn == status },
                        selectedID: store.selectedOrchestratorWorkItemID,
                        groupByCategory: categoryFilter == nil,
                        collapsed: collapsedGroups,
                        projectName: projectName(for:),
                        composeText: $composeText,
                        isComposing: composingColumn == status,
                        onSelect: { select($0) },
                        onArchive: { archive($0) },
                        onDelete: { store.deleteWorkItem($0.id) },
                        onSendToOrchestrator: { sendToOrchestrator($0) },
                        draggingID: dragState?.id,
                        isDropTarget: target == status,
                        onDragChanged: dragChanged,
                        onDragEnded: dragEnded,
                        onToggleGroup: toggleGroup,
                        onStartCompose: { startCompose(in: status) },
                        onCommitCompose: { commitCompose(in: status) },
                        onCancelCompose: cancelCompose
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
        .overlay(alignment: .topLeading) { floatingCard }
    }

    /// The card that follows the cursor. Drawn over the columns rather than
    /// moving the real one, so the column it came from keeps its layout and
    /// nothing reflows underneath the pointer mid-drag.
    @ViewBuilder
    private var floatingCard: some View {
        if let dragState {
            Text(dragState.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DaddyTheme.textPrimary)
                .lineLimit(2)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(width: 190, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.82))
                )
                .overlay(alignment: .leading) {
                    Rectangle().fill(dragState.tint).frame(width: 3)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
                .position(dragState.location)
                .transaction { $0.animation = nil }
                .allowsHitTesting(false)
        }
    }

    /// The column under the pointer right now, if any.
    private var dropTarget: OrchestratorWorkStatus? {
        guard let dragState else { return nil }
        return columnFrames.first { $0.value.contains(dragState.location) }?.key
    }

    private func dragChanged(_ item: OrchestratorWorkItem, to point: CGPoint) {
        // Implicit animation interpolates the floating card toward the cursor
        // and the drop-target fills — that is the clump. Kill it for the drag.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if dragState?.id == item.id {
                // Every location change repaints the board, and the board is glass
                // over an animated backdrop — the most expensive thing to repaint
                // in the app. A pixel of pointer travel does not deserve one.
                guard let current = dragState?.location,
                      hypot(point.x - current.x, point.y - current.y) > 3 else { return }
                dragState?.location = point
            } else {
                dragState = BoardDragState(
                    id: item.id,
                    title: item.title,
                    tint: item.category.tint,
                    location: point
                )
            }
        }
    }

    private func dragEnded(_ item: OrchestratorWorkItem, at point: CGPoint) {
        // Cards must land instantly. Animating a move reflows every column,
        // which fires column-frame preferences every tick, which invalidates
        // the glass, which is how the board drops to a few frames a second.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dragState = nil
            guard let target = columnFrames.first(where: { $0.value.contains(point) })?.key,
                  target != item.status.boardColumn else { return }
            _ = store.moveWorkItem(item.id, to: target)
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
            ] + store.projects.map { project in
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

    // MARK: - Detail

    /// Overlay, not a sibling in the board `HStack`. The pane sits on top of
    /// the columns and the columns keep their width. Animation lives on this
    /// container only — wrapping selection in `withAnimation` also interpolated
    /// every card's selected state, which is what made opening a task hitch.
    @ViewBuilder
    private var detailOverlay: some View {
        ZStack(alignment: .trailing) {
            if store.selectedOrchestratorWorkItemID != nil {
                detailPane
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

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("WORK ITEM")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(DaddyTheme.textSecondary)
                Spacer()
                Button(action: closeDetail) {
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
                        title: $editorTitle,
                        summary: $editorSummary,
                        category: $editorCategory,
                        status: $editorStatus,
                        priority: $editorPriority,
                        projectID: $editorProjectID,
                        projects: store.projects,
                        onSave: saveEditor
                    )

                    GlassHairline()

                    HStack(spacing: 7) {
                        Button("send to orchestrator") {
                            guard let item = selectedItem else { return }
                            sendToOrchestrator(item)
                        }
                        .buttonStyle(.inset)

                        Button("delete") {
                            guard let id = store.selectedOrchestratorWorkItemID else { return }
                            store.deleteWorkItem(id)
                        }
                        .buttonStyle(.inset(DaddyTheme.failure))
                    }

                    if let item = selectedItem, !item.rawCapture.isEmpty, item.rawCapture != item.summary {
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
            let chords = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard event.keyCode == 53, chords.isEmpty else { return event }

            // Typing a new card's title owns Escape first — it cancels the
            // compose rather than closing the whole board out from under you.
            if composingColumn != nil {
                cancelCompose()
                return nil
            }
            if store.selectedOrchestratorWorkItemID != nil {
                closeDetail()
                return nil
            }
            withAnimation(.smooth(duration: 0.24)) {
                store.workspace = store.workspaceBeforeBoard
            }
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
        store.selectedOrchestratorWorkItemID = item.id
    }

    private func closeDetail() {
        store.selectedOrchestratorWorkItemID = nil
    }

    /// The board follows Fleet's current project so cards from one repo do not
    /// keep sitting on another. "All" and "Unassigned" are explicit overrides.
    private func syncScopeFromProject() {
        if let id = store.selectedProjectID {
            applyScope(.project(id))
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

    private func startCompose(in status: OrchestratorWorkStatus) {
        composeText = ""
        composingColumn = status
    }

    private func cancelCompose() {
        composingColumn = nil
        composeText = ""
    }

    private func commitCompose(in status: OrchestratorWorkStatus) {
        let title = composeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return cancelCompose() }

        store.addWorkItem(
            OrchestratorWorkItem(
                title: title,
                summary: "",
                rawCapture: title,
                category: categoryFilter ?? .other,
                status: status,
                projectID: composeProjectID
            )
        )
        cancelCompose()
    }

    /// A card typed into a scoped board belongs to that project. Typed into
    /// the all-projects board it inherits whatever Fleet has selected, and
    /// typed into Unassigned it deliberately stays unassigned.
    private var composeProjectID: String? {
        switch scope {
        case .all: return store.selectedProjectID
        case .unassigned: return nil
        case .project(let id): return id
        }
    }

    private func archive(_ item: OrchestratorWorkItem) {
        store.moveWorkItem(item.id, to: .archived)
    }

    /// Dispatch lives in the Orchestrator — agent picker, session picker and
    /// an approval step. Rather than grow a second copy of all that here, the
    /// board selects the item and hands the window over.
    private func sendToOrchestrator(_ item: OrchestratorWorkItem) {
        store.selectedOrchestratorWorkItemID = item.id
        withAnimation(.smooth(duration: 0.24)) {
            store.workspace = .orchestrator
        }
    }

    private func syncEditor() {
        guard let item = selectedItem else { return }
        editorTitle = item.title
        editorSummary = item.summary
        editorCategory = item.category
        editorStatus = item.status
        editorPriority = item.priority
        editorProjectID = item.projectID ?? ""
    }

    private func saveEditor() {
        guard var item = selectedItem else { return }
        item.title = editorTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        item.summary = editorSummary
        item.category = editorCategory
        item.status = editorStatus
        item.priority = editorPriority
        item.projectID = editorProjectID.isEmpty ? nil : editorProjectID
        item.updatedAt = Date()
        store.replaceWorkItem(item)
    }
}
