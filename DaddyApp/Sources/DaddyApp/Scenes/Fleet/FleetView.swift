import SwiftUI

/// The fleet: projects on the left, agents in the middle, the agent's terminal
/// on the right — until you drill into one agent, at which point the terminal
/// becomes a focused workspace underneath one compact toolbar.
///
/// ## Why this is a ZStack over a GeometryReader rather than an HStack
///
/// The terminal has to *move* between two places. Expressed as two branches of
/// an `if`, SwiftUI would tear down one `TerminalPane` and build another — and
/// `TerminalSurface` wraps a SwiftTerm `NSView`. On rebuild it replays
/// `PTYProcess.recentOutput`, but that buffer is capped at 200 lines, so a long
/// session would silently lose its scrollback every time you opened or closed
/// the detail view.
///
/// So there is exactly one `TerminalPane` in the hierarchy, always, and what
/// changes is the rectangle it is given. Same view, same NSView, no teardown —
/// and because it is a frame change rather than a branch, it genuinely slides.
struct FleetView: View {
    @Environment(MockStore.self) private var store

    @State private var sidebarExpanded = false
    @State private var progressPanelOpen = false
    @State private var progressPanelProjectID: String?
    @State private var keyboardMonitor: Any?
    @State private var sidebarHoverEnabled = true
    @State private var hoverRestoreTask: Task<Void, Never>?

    private let gap: CGFloat = 16
    private let sidebarWide: CGFloat = 264
    private let sidebarNarrow: CGFloat = 50
    private let terminalDockedWidth: CGFloat = 496
    private let detailToolbarHeight: CGFloat = 58

    private var isDetail: Bool { store.detailAgent != nil }

    var body: some View {
        GeometryReader { geo in
            let sidebarWidth = sidebarExpanded ? sidebarWide : sidebarNarrow
            let contentX = isDetail ? 0 : sidebarWidth + gap
            let contentWidth = max(0, geo.size.width - contentX)
            let terminal = terminalFrame(in: geo.size, contentX: contentX, contentWidth: contentWidth)

            ZStack(alignment: .topLeading) {
                ProjectsSidebar(
                    expanded: $sidebarExpanded,
                    hoverExpansionEnabled: sidebarHoverEnabled
                )
                    .frame(width: sidebarWidth, height: geo.size.height)
                    .opacity(isDetail ? 0 : 1)
                    .allowsHitTesting(!isDetail)

                middleColumn(
                    width: isDetail ? contentWidth : max(0, contentWidth - terminalDockedWidth - gap),
                    height: isDetail ? detailToolbarHeight : geo.size.height
                )
                .offset(x: contentX, y: 0)

                // The one and only terminal. Only its rectangle changes.
                TerminalPane(isFocused: isDetail)
                    .frame(width: terminal.width, height: terminal.height)
                    .offset(x: terminal.minX, y: terminal.minY)
            }
            .animation(.smooth(duration: 0.3), value: sidebarExpanded)
            .animation(.smooth(duration: 0.3), value: progressPanelOpen)
        }
        .onAppear { installKeyboardMonitor() }
        .onDisappear { removeKeyboardMonitor() }
        .onChange(of: store.detailAgentID) { _, detailID in
            if detailID == nil { suppressSidebarHover() }
        }
    }

    /// Docked on the right, or parked across the bottom of the content area.
    private func terminalFrame(
        in size: CGSize,
        contentX: CGFloat,
        contentWidth: CGFloat
    ) -> CGRect {
        if isDetail {
            let top = detailToolbarHeight
            return CGRect(
                x: contentX,
                y: top,
                width: contentWidth,
                height: max(0, size.height - top)
            )
        }

        return CGRect(
            x: size.width - terminalDockedWidth,
            y: 0,
            width: terminalDockedWidth,
            height: size.height
        )
    }

    @ViewBuilder
    private func middleColumn(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            if let agent = store.detailAgent {
                AgentDetailHeader(
                    agent: agent,
                    onOpenProgress: openProgress,
                    onBack: closeDetail
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                AgentDashboard(
                    progressOpen: $progressPanelOpen,
                    onOpenProgress: openProgress
                )
                .transition(.move(edge: .leading).combined(with: .opacity))

                if progressPanelOpen {
                    Divider()
                    let panelProject = store.project(progressPanelProjectID ?? "") ?? store.selectedProject
                    FileTreeView(project: panelProject)
                        .frame(height: 280)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .frame(width: width, height: height, alignment: .top)
        .clipped()
    }

    private func openProgress(_ projectID: String) {
        progressPanelProjectID = projectID
        if isDetail { closeDetail() }
        withAnimation(.smooth(duration: 0.3)) { progressPanelOpen = true }
    }

    private func closeDetail() {
        // Returning is navigation, not a showcase animation. Animating this
        // transition forces SwiftTerm's native view through a full-screen-to-
        // docked resize and makes a simple back action feel unresponsive.
        suppressSidebarHover()
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { store.closeDetail() }
    }

    /// Layout changes under a stationary pointer can synthesize hover
    /// transitions. Ignore that brief teardown window, then restore normal
    /// sidebar hover behavior.
    ///
    /// Called on the way out of the detail view *and* from `onChange`, because
    /// the store closes the detail view itself when the focused agent stops —
    /// that route never passes through `closeDetail`.
    private func suppressSidebarHover() {
        sidebarHoverEnabled = false
        hoverRestoreTask?.cancel()
        hoverRestoreTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            sidebarHoverEnabled = true
        }
    }

    /// Escape and Command-[ back out of whatever is open, innermost first.
    private func installKeyboardMonitor() {
        guard keyboardMonitor == nil else { return }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let isEscape = event.keyCode == 53
            let isCommandLeftBracket = event.modifierFlags.contains(.command)
                && event.charactersIgnoringModifiers == "["
            guard isEscape || isCommandLeftBracket else { return event }

            if progressPanelOpen {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { progressPanelOpen = false }
                return nil
            }
            if store.detailAgent != nil {
                closeDetail()
                return nil
            }
            return event
        }
    }

    private func removeKeyboardMonitor() {
        hoverRestoreTask?.cancel()
        hoverRestoreTask = nil
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
            self.keyboardMonitor = nil
        }
    }
}
