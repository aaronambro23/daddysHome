import SwiftUI
import DaddyCore

/// The fleet: the rail on the left, agents in the middle, the agent's terminal
/// on the right — until you drill into one agent, at which point the terminal
/// takes the whole middle underneath one compact toolbar.
///
/// ## Focus is not a mode
///
/// It used to be: drilling into an agent hid the rail outright, so the project
/// tree and every other agent's state disappeared exactly when you started
/// working. Now the rail is permanent and focusing an agent only changes what
/// occupies the space to the right of it. `store.detailAgentID` still means
/// "which agent the middle column is showing" — it just no longer takes the
/// window hostage.
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
    @State private var providerLaunchOpen = false
    @State private var plusLaunchFrame: CGRect = .zero
    /// Frozen left-to-right agent ids for a Ctrl+Tab burst. Empty when idle.
    @State private var focusCycleIDs: [String] = []
    /// Index into `focusCycleIDs`, or `focusCycleIDs.count` when the plus is the stop.
    @State private var focusCycleIndex = 0
    @State private var focusCycleHasPlus = false
    @State private var focusCycleCommitTask: Task<Void, Never>?
    @State private var compassArmedKind: AgentKind?
    /// Live agents in header order: identity, then bubbles left-to-right.
    @State private var focusStripIDs: [String] = []

    private var focusHighlightID: String? {
        guard !focusCycleIDs.isEmpty else { return nil }
        if focusCycleIndex < focusCycleIDs.count {
            return focusCycleIDs[focusCycleIndex]
        }
        return FocusAgentSwitcher.plusID
    }

    private let gap: CGFloat = 16
    /// Shared with `WorkspaceRail`, which lays its content out at these widths
    /// whatever the animating frame currently proposes.
    private let sidebarWide = DaddyTheme.railWideWidth
    private let sidebarNarrow = DaddyTheme.railNarrowWidth
    private let terminalDockedWidth: CGFloat = 496
    private let detailToolbarHeight: CGFloat = 58

    /// The shell takes 30% and the agent keeps 70%, because the agent's
    /// transcript is what you are reading and the shell is what you are
    /// occasionally typing into. Floored so it stays usable on a narrow window
    /// and capped so it does not become the main event on a wide one.
    private let shellFraction: CGFloat = 0.30
    private let shellMinWidth: CGFloat = 280
    private let shellMaxWidth: CGFloat = 620

    private func shellWidth(for contentWidth: CGFloat) -> CGFloat {
        min(shellMaxWidth, max(shellMinWidth, contentWidth * shellFraction))
    }

    private var isDetail: Bool { store.detailAgent != nil }

    /// Consistent gap at the top.
    private var topInset: CGFloat { gap }

    var body: some View {
        GeometryReader { geo in
            let sidebarWidth = sidebarExpanded ? sidebarWide : sidebarNarrow

            // With an agent focused the rail *floats* over the content instead
            // of pushing it.
            //
            // Pushing would mean the terminal resizes every time the pointer
            // brushes the left edge — and a terminal resize is a TIOCSWINSZ, a
            // SIGWINCH, and a full TUI reflow at the far end. Hovering a
            // sidebar must not make the agent redraw itself. On the dashboard
            // it still pushes, because tiles reflowing is free.
            let contentX = (isDetail ? sidebarNarrow : sidebarWidth) + gap
            let contentWidth = max(0, geo.size.width - contentX)
            let terminal = terminalFrame(in: geo.size, contentX: contentX, contentWidth: contentWidth)

            ZStack(alignment: .topLeading) {
                middleColumn(
                    width: isDetail ? contentWidth : max(0, contentWidth - terminalDockedWidth - gap),
                    height: isDetail ? detailToolbarHeight : geo.size.height
                )
                // Dashboard: same rect as the rail and docked OUTPUT — RootView
                // already insets the fleet 18pt. The extra `topInset` offset was
                // 023 leaving a 16pt shift on a full-height column, which ran
                // the AGENTS panel off both edges. Focus toolbar still sits on
                // `topInset` so the gap above it matches the gap below it.
                .offset(x: contentX, y: isDetail ? topInset : 0)

                // The one and only agent terminal. Only its rectangle changes.
                TerminalPane(isFocused: isDetail)
                    .frame(width: terminal.width, height: terminal.height)
                    .offset(x: terminal.minX, y: terminal.minY)

                // Your own shell, to the right of the agent's.
                //
                // Mounted permanently and moved *offscreen* when there is no
                // agent focused, rather than being branched away or given a
                // zero width. Same rule as the agent pane — rebuilding it would
                // tear down SwiftTerm's NSView and truncate scrollback to the
                // 200 lines `recentOutput` retains — and a zero-width frame
                // would hand the child a 0-column TIOCSWINSZ, which is not a
                // terminal size any shell should be asked to lay out for.
                ShellPane(project: store.selectedProject)
                    .frame(width: shellWidth(for: contentWidth), height: terminal.height)
                    .offset(
                        x: isDetail ? terminal.maxX + gap : geo.size.width,
                        y: terminal.minY
                    )
                    // Keep the native terminal alive at a real size for
                    // scrollback, but do not let its border or renderer bleed
                    // past the Fleet's right edge while it is parked offscreen.
                    .opacity(isDetail ? 1 : 0)
                    .allowsHitTesting(isDetail)
                    .accessibilityHidden(!isDetail)

                // Last, so an expanded rail draws over the focused terminal
                // rather than shoving it sideways.
                WorkspaceRail(
                    expanded: $sidebarExpanded,
                    hoverExpansionEnabled: sidebarHoverEnabled
                )
                .frame(width: sidebarWidth, height: geo.size.height)
                // The rail's content is laid out at its final width, so growing
                // this frame reveals it. Without the clip it would spill out of
                // the collapsed strip for the length of the animation and take
                // its hover region with it.
                .clipped()

                if let project = launchProject {
                    RadialProviderMenuOverlay(
                        project: project,
                        plusFrame: plusLaunchFrame,
                        isOpen: providerLaunchOpen,
                        armedKind: compassArmedKind,
                        onDismiss: closeProviderLaunch
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(providerLaunchOpen)
                }
            }
            .coordinateSpace(name: FleetCoordinateSpace.name)
            .onPreferenceChange(PlusLaunchFrameKey.self) { plusLaunchFrame = $0 }
            .frame(height: geo.size.height)
            // No implicit animation on `sidebarExpanded`: the rail already wraps
            // every change to it in a `withAnimation`, and `expanded` is a
            // binding to this state, so one toggle used to run two nested
            // transactions on one property.
            .animation(.smooth(duration: 0.3), value: progressPanelOpen)
            .animation(.smooth(duration: 0.3), value: isDetail)
        }
        .onAppear { installKeyboardMonitor() }
        .onDisappear { removeKeyboardMonitor() }
        .onChange(of: store.detailAgentID) { _, detailID in
            if let detailID {
                syncFocusStrip(current: detailID)
            } else {
                focusStripIDs = []
                providerLaunchOpen = false
                suppressSidebarHover()
            }
            // A click, launch, or commit restacked identity — drop the burst.
            clearFocusCycle()
        }
    }

    /// Docked on the right, or — with an agent focused — sharing the content
    /// area with your own shell: 70% agent, 30% shell.
    private func terminalFrame(
        in size: CGSize,
        contentX: CGFloat,
        contentWidth: CGFloat
    ) -> CGRect {
        if isDetail {
            // Below the toolbar, with the same gap under it that separates the
            // two terminals from each other.
            let top = topInset + detailToolbarHeight + gap
            return CGRect(
                x: contentX,
                y: top,
                width: max(0, contentWidth - shellWidth(for: contentWidth) - gap),
                height: max(0, size.height - top)
            )
        }

        // Docked: pinned to the right edge, but never wider than the content
        // area — a narrow window with the rail pinned open must not put the
        // terminal underneath it.
        let width = min(terminalDockedWidth, contentWidth)
        return CGRect(
            x: size.width - width,
            y: 0,
            width: width,
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
                    onBack: closeDetail,
                    launchMenuOpen: $providerLaunchOpen,
                    highlightID: focusHighlightID,
                    stripIDs: focusStripIDs
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

    /// Where the plus launches: the focused agent's project, same as the header.
    private var launchProject: MockProject? {
        guard let agent = store.detailAgent else { return nil }
        return store.project(agent.projectID) ?? store.selectedProject
    }

    private func closeProviderLaunch() {
        providerLaunchOpen = false
        compassArmedKind = nil
        if !focusCycleIDs.isEmpty {
            scheduleFocusCycleCommit()
        }
    }

    private func openProgress(_ projectID: String) {
        progressPanelProjectID = projectID
        if isDetail { closeDetail() }
        withAnimation(.smooth(duration: 0.3)) { progressPanelOpen = true }
    }

    private func closeDetail() {
        providerLaunchOpen = false
        clearFocusCycle()
        suppressSidebarHover()
        withAnimation(.smooth(duration: 0.3)) {
            store.closeDetail()
        }
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
            // Stay suppressed through the 300ms detail-to-Fleet transition.
            try? await Task.sleep(for: .milliseconds(360))
            guard !Task.isCancelled else { return }
            sidebarHoverEnabled = true
        }
    }

    /// Escape and Command-[ back out of whatever is open, innermost first.
    /// Ctrl+Tab walks focus sessions; arrows pick a compass slot while it is open.
    private func installKeyboardMonitor() {
        guard keyboardMonitor == nil else { return }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if handleFocusShortcut(event) { return nil }

            let isEscape = event.keyCode == 53
            let isCommandLeftBracket = event.modifierFlags.contains(.command)
                && event.charactersIgnoringModifiers == "["
            guard isEscape || isCommandLeftBracket else { return event }

            if providerLaunchOpen {
                closeProviderLaunch()
                return nil
            }
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

    private func handleFocusShortcut(_ event: NSEvent) -> Bool {
        let chords = event.modifierFlags.intersection([.command, .option, .control, .shift])

        if store.detailAgent != nil,
           chords.contains(.control),
           !chords.contains(.command),
           !chords.contains(.option),
           !chords.contains(.shift),
           event.charactersIgnoringModifiers?.lowercased() == "q" {
            dismissFocusedSession()
            return true
        }

        if providerLaunchOpen,
           chords.isEmpty,
           let kind = RadialProviderMenuOverlay.kind(for: event) {
            compassArmedKind = kind
            launchCompassKind(kind)
            return true
        }

        let isControlTab = event.keyCode == 48
            && chords.contains(.control)
            && !chords.contains(.command)
            && !chords.contains(.option)
            && !chords.contains(.shift)
        guard isControlTab, store.detailAgent != nil else { return false }

        if providerLaunchOpen {
            providerLaunchOpen = false
            compassArmedKind = nil
            advanceFocusCycle(fromPlus: true)
            return true
        }

        advanceFocusCycle()
        return true
    }

    private func launchCompassKind(_ kind: AgentKind) {
        guard let project = launchProject else { return }
        guard store.isInstalled(kind) else { return }
        clearFocusCycle()
        providerLaunchOpen = false
        compassArmedKind = nil
        store.launchReal(kind, in: project)
    }

    private func beginFocusCycleIfNeeded() {
        guard focusCycleIDs.isEmpty, let current = store.detailAgent else { return }
        syncFocusStrip(current: current.id)
        focusCycleIDs = focusStripIDs
        focusCycleIndex = 0
        focusCycleHasPlus = launchProject != nil
    }

    private func advanceFocusCycle(fromPlus: Bool = false) {
        beginFocusCycleIfNeeded()
        guard !focusCycleIDs.isEmpty else { return }

        if fromPlus, focusCycleHasPlus {
            focusCycleIndex = focusCycleIDs.count
        }

        let plusIndex = focusCycleHasPlus ? focusCycleIDs.count : nil
        let lastIndex = plusIndex ?? (focusCycleIDs.count - 1)
        guard lastIndex >= 0 else { return }

        var next = focusCycleIndex + 1
        if next > lastIndex {
            next = 0
        }
        focusCycleIndex = next

        if let plusIndex, next == plusIndex {
            focusCycleCommitTask?.cancel()
            compassArmedKind = nil
            providerLaunchOpen = true
            return
        }

        store.previewDetail(focusCycleIDs[next])
        scheduleFocusCycleCommit()
    }

    /// Keep identity as strip[0]; bubbles stay in this sequence, not recency.
    private func syncFocusStrip(current: String) {
        let live = store.visibleAgents.filter(\.isLive)
        let liveIDs = Set(live.map(\.id))
        focusStripIDs.removeAll { !liveIDs.contains($0) }

        let newcomers = live
            .filter { !focusStripIDs.contains($0.id) }
            .sorted { $0.lastOutputAt > $1.lastOutputAt }
            .map(\.id)
        focusStripIDs.append(contentsOf: newcomers)

        if focusStripIDs.isEmpty {
            let others = live
                .filter { $0.id != current }
                .sorted { $0.lastOutputAt > $1.lastOutputAt }
            focusStripIDs = [current] + others.map(\.id)
        }

        rotateFocusStrip(to: current)
    }

    private func rotateFocusStrip(to id: String) {
        guard let i = focusStripIDs.firstIndex(of: id) else { return }
        focusStripIDs = Array(focusStripIDs[i...]) + Array(focusStripIDs[..<i])
    }

    private func successorStripID(after id: String) -> String? {
        let remaining = focusStripIDs.filter { $0 != id }
        guard !remaining.isEmpty else { return nil }
        if let i = focusStripIDs.firstIndex(of: id) {
            let right = focusStripIDs[(i + 1)...].first { $0 != id && remaining.contains($0) }
            return right ?? remaining[0]
        }
        return remaining[0]
    }

    private func dismissFocusedSession() {
        let id: String?
        if !focusCycleIDs.isEmpty, focusCycleIndex < focusCycleIDs.count {
            id = focusCycleIDs[focusCycleIndex]
        } else {
            id = store.selectedAgentID ?? store.detailAgentID
        }
        guard let id, let agent = store.agents.first(where: { $0.id == id }) else { return }

        let successor = successorStripID(after: id)
        providerLaunchOpen = false
        compassArmedKind = nil
        clearFocusCycle()
        focusStripIDs.removeAll { $0 == id }

        if agent.isLive {
            store.stop(id)
        } else {
            store.dismiss(id)
        }

        if let successor, store.detailAgentID != nil {
            withAnimation(.smooth(duration: 0.36)) {
                store.openDetail(successor)
            }
        }
    }

    private func scheduleFocusCycleCommit() {
        focusCycleCommitTask?.cancel()
        focusCycleCommitTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            commitFocusCycle()
        }
    }

    private func commitFocusCycle() {
        guard !focusCycleIDs.isEmpty else { return }
        let id: String
        if focusCycleIndex < focusCycleIDs.count {
            id = focusCycleIDs[focusCycleIndex]
        } else {
            id = store.selectedAgentID ?? focusCycleIDs[0]
        }
        focusCycleCommitTask?.cancel()
        focusCycleCommitTask = nil
        withAnimation(.smooth(duration: 0.36)) {
            store.openDetail(id)
            focusCycleIDs = []
            focusCycleIndex = 0
            focusCycleHasPlus = false
        }
    }

    private func clearFocusCycle() {
        focusCycleCommitTask?.cancel()
        focusCycleCommitTask = nil
        focusCycleIDs = []
        focusCycleIndex = 0
        focusCycleHasPlus = false
    }

    private func removeKeyboardMonitor() {
        hoverRestoreTask?.cancel()
        hoverRestoreTask = nil
        clearFocusCycle()
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
            self.keyboardMonitor = nil
        }
    }
}
