import SwiftUI
import DaddyCore

/// The overlay a card lands on when it is dropped into DISPATCHED.
///
/// Dropping does not move the card. This does — picking a provider runs the
/// same `dispatchWorkItem` path as the detail pane's "send to agent" menu,
/// which sets the status, hops to Fleet and pastes the prompt into the
/// composer without submitting it. Dismissing leaves the card where it was,
/// so a dispatched card always has an agent behind it.
///
/// Bubbles rather than a menu because this is the end of a drag: the pointer
/// is already out in the middle of the board with no menu bar under it, and a
/// 96pt target is one flick away from wherever the drop landed.
struct BoardDispatchPicker: View {
    @Environment(MockStore.self) private var store

    /// One item for a normal drag/Cmd+Return dispatch; 2+ for a multi-select
    /// bundle send — see `isBundle`.
    let items: [OrchestratorWorkItem]
    let onDismiss: () -> Void

    private var isBundle: Bool { items.count > 1 }
    private var item: OrchestratorWorkItem { items[0] }

    /// Which provider has been opened into its live sessions. Nil is the
    /// four-bubble row.
    @State private var expanded: AgentKind?

    /// Index into whichever row is on screen — the provider row while
    /// `expanded` is nil, the session row (sessions then "New session") once
    /// it isn't. Arrow keys move it, Enter activates it, so the bubbles are
    /// reachable without the mouse the drop that opened this popup left you
    /// without.
    @State private var selectedIndex = 0
    @State private var keyMonitor: Any?

    private static let providers: [AgentKind] = [.claude, .codex, .cursor, .opencode]

    var body: some View {
        ZStack {
            // Catches the click that dismisses, and knocks the board back so
            // the bubbles are the only thing with any contrast.
            Color.black.opacity(0.55)
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 22) {
                heading

                if resolvedProject == nil {
                    noProject
                } else if let kind = expanded {
                    sessionRow(for: kind)
                } else {
                    providerRow
                }
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
            .glassPanel()
            .fixedSize()
            .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
        }
        .transition(.opacity)
        .onAppear {
            installKeyMonitor()
            selectedIndex = firstEnabledIndex
        }
        .onDisappear { removeKeyMonitor() }
        .onChange(of: expanded) { _, _ in selectedIndex = firstEnabledIndex }
    }

    private var firstEnabledIndex: Int {
        currentTargets.firstIndex { $0.isEnabled } ?? 0
    }

    // MARK: - Keyboard

    /// A local monitor, not `.onKeyPress` — this popup is an overlay over the
    /// board, which never takes keyboard focus itself, so nothing here would
    /// receive key events through the normal responder chain.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
            else { return event }

            switch event.keyCode {
            case 123: // Left
                moveSelection(by: -1)
                return nil
            case 124: // Right
                moveSelection(by: 1)
                return nil
            case 36, 76: // Return, keypad Enter
                activateSelection()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func moveSelection(by delta: Int) {
        let targets = currentTargets
        guard !targets.isEmpty else { return }
        var next = selectedIndex
        repeat {
            next += delta
        } while targets.indices.contains(next) && !targets[next].isEnabled
        guard targets.indices.contains(next) else { return }
        selectedIndex = next
    }

    private func activateSelection() {
        let targets = currentTargets
        guard targets.indices.contains(selectedIndex), targets[selectedIndex].isEnabled else { return }
        targets[selectedIndex].action()
    }

    /// The bubbles on screen right now, left to right, paired with whether
    /// they can be activated and what pressing Enter on each one does — the
    /// same action its tap gesture runs. Disabled (not-installed) providers
    /// stay in the list so the index lines up with what is drawn, but arrow
    /// navigation steps over them and Enter on one is a no-op.
    private var currentTargets: [(id: String, isEnabled: Bool, action: () -> Void)] {
        guard resolvedProject != nil else { return [] }
        if let kind = expanded {
            let sessions = liveSessions(of: kind).map { agent in
                (id: agent.id, isEnabled: true, action: { dispatch(onto: agent) })
            }
            return sessions + [
                (id: "new-\(kind.rawValue)", isEnabled: true, action: { dispatch(launching: kind) })
            ]
        }
        return Self.providers.map { kind in
            (id: kind.rawValue, isEnabled: store.isInstalled(kind), action: {
                let live = liveSessions(of: kind)
                if live.isEmpty {
                    dispatch(launching: kind)
                } else {
                    expanded = kind
                }
            })
        }
    }

    // MARK: - Heading

    private var heading: some View {
        VStack(spacing: 6) {
            Text(expanded == nil ? (isBundle ? "SEND \(items.count) TASKS TOGETHER" : "SEND TO AGENT") : "PICK A SESSION")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(DaddyTheme.textSecondary)

            if isBundle {
                Text(items.map(\.title).joined(separator: " · "))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DaddyTheme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            } else {
                Text(item.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DaddyTheme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            Text(isBundle ? "one prompt, pasted into the composer, not sent" : "the task is pasted into the composer, not sent")
                .font(.system(size: 9.5))
                .foregroundStyle(DaddyTheme.textVeryDim)
        }
    }

    private var noProject: some View {
        VStack(spacing: 10) {
            Text("This card has no project, and neither does the fleet.")
                .font(.system(size: 11))
                .foregroundStyle(DaddyTheme.textMuted)
            Button("close") { onDismiss() }
                .buttonStyle(.inset(DaddyTheme.accent))
        }
    }

    // MARK: - Providers

    private var providerRow: some View {
        HStack(spacing: 16) {
            ForEach(Array(Self.providers.enumerated()), id: \.element) { index, kind in
                providerBubble(kind, isSelected: index == selectedIndex)
            }
        }
    }

    private func providerBubble(_ kind: AgentKind, isSelected: Bool) -> some View {
        let installed = store.isInstalled(kind)
        let live = liveSessions(of: kind)

        return DispatchBubble(
            diameter: 96,
            tint: CompactAgentIcon.tint(for: kind),
            isEnabled: installed,
            isSelected: isSelected,
            title: kind.rawValue.capitalized,
            note: installed
                ? (live.isEmpty ? "new session" : "\(live.count) live")
                : "not installed",
            bubble: AnyView(ProviderLogo.badge(for: kind, diameter: 96))
        ) {
            // A provider with nothing running has only one thing it can do, so
            // the extra step is skipped rather than shown with one option.
            if live.isEmpty {
                dispatch(launching: kind)
            } else {
                expanded = kind
            }
        }
    }

    // MARK: - Sessions

    private func sessionRow(for kind: AgentKind) -> some View {
        let sessions = liveSessions(of: kind)
        return VStack(spacing: 16) {
            HStack(spacing: 14) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, agent in
                    DispatchBubble(
                        diameter: 78,
                        tint: CompactAgentIcon.tint(for: kind),
                        isEnabled: true,
                        isSelected: index == selectedIndex,
                        title: sessionTitle(agent),
                        note: agent.id == currentSessionID ? "this session" : nil,
                        bubble: AnyView(ProviderLogo.badge(for: kind, diameter: 78))
                    ) {
                        dispatch(onto: agent)
                    }
                }

                DispatchBubble(
                    diameter: 78,
                    tint: DaddyTheme.textMuted,
                    isEnabled: true,
                    isSelected: sessions.count == selectedIndex,
                    title: "New session",
                    note: nil,
                    bubble: AnyView(
                        Circle()
                            .fill(Color.white.opacity(0.06))
                            .overlay {
                                Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                            }
                            .frame(width: 78, height: 78)
                            .overlay {
                                Image(systemName: "plus")
                                    .font(.system(size: 24, weight: .light))
                                    .foregroundStyle(DaddyTheme.textSecondary)
                            }
                    )
                ) {
                    dispatch(launching: kind)
                }
            }

            Button("back") { expanded = nil }
                .buttonStyle(.inset(DaddyTheme.textMuted))
        }
    }

    // MARK: - Data

    private var resolvedProject: MockProject? {
        if let id = item.projectID { return store.project(id) }
        if let id = store.selectedProjectID { return store.project(id) }
        return nil
    }

    private var currentSessionID: String? {
        store.detailAgentID ?? store.selectedAgentID
    }

    /// The session you were in first, then most recently active.
    private func liveSessions(of kind: AgentKind) -> [MockAgent] {
        guard let project = resolvedProject else { return [] }
        return store.agents
            .filter { $0.projectID == project.id && $0.agent == kind && $0.isLive }
            .sorted { a, b in
                let aCurrent = a.id == currentSessionID
                let bCurrent = b.id == currentSessionID
                if aCurrent != bCurrent { return aCurrent }
                return a.lastOutputAt > b.lastOutputAt
            }
    }

    private func sessionTitle(_ agent: MockAgent) -> String {
        if let index = MockAgent.siblingIndex(for: agent, among: store.agents) {
            return "\(agent.displayName) \(MockAgent.romanNumeral(forZeroBased: index))"
        }
        return agent.displayName
    }

    // MARK: - Actions

    private func dispatch(onto agent: MockAgent) {
        onDismiss()
        withAnimation(.smooth(duration: 0.24)) {
            let action: AppAction = isBundle
                ? .dispatchBundleOntoAgent(workItemIDs: items.map(\.id), agentID: agent.id)
                : .dispatchOntoAgent(workItemID: item.id, agentID: agent.id)
            _ = AppActionDispatcher(store: store).perform(action)
        }
    }

    private func dispatch(launching kind: AgentKind) {
        onDismiss()
        withAnimation(.smooth(duration: 0.24)) {
            let action: AppAction = isBundle
                ? .dispatchBundleLaunchingAgent(workItemIDs: items.map(\.id), kind: kind)
                : .dispatchLaunchingAgent(workItemID: item.id, kind: kind)
            _ = AppActionDispatcher(store: store).perform(action)
        }
    }
}

/// One bubble: a big circular target with a caption under it.
///
/// The circle itself comes in as `bubble` — `ProviderLogo.badge` already draws
/// a tinted, rimmed circle at any diameter, and drawing a second one behind it
/// only muddied the tint. This adds the hover state on top of it.
private struct DispatchBubble: View {
    let diameter: CGFloat
    let tint: Color
    let isEnabled: Bool
    /// Driven by the popup's keyboard selection, not by this view's own
    /// state — arrow keys move it, so it has to be visible without hovering.
    var isSelected: Bool = false
    let title: String
    let note: String?
    let bubble: AnyView
    let action: () -> Void

    @State private var hovering = false

    private var highlighted: Bool { hovering || isSelected }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                bubble
                    .overlay {
                        Circle()
                            .strokeBorder(tint.opacity(highlighted ? 0.9 : 0), lineWidth: 2)
                            .frame(width: diameter, height: diameter)
                    }
                    .scaleEffect(highlighted ? 1.06 : 1)
                    .shadow(color: tint.opacity(highlighted ? 0.35 : 0), radius: 16)

                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DaddyTheme.textPrimary)
                        .lineLimit(1)
                    if let note {
                        Text(note)
                            .font(.system(size: 9))
                            .foregroundStyle(DaddyTheme.textVeryDim)
                            .lineLimit(1)
                    }
                }
                .frame(width: diameter + 24)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .animation(.easeOut(duration: 0.14), value: highlighted)
        .onHover { hovering = isEnabled && $0 }
    }
}
