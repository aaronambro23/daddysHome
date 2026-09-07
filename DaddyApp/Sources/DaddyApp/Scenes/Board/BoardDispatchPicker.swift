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

    let item: OrchestratorWorkItem
    let onDismiss: () -> Void

    /// Which provider has been opened into its live sessions. Nil is the
    /// four-bubble row.
    @State private var expanded: AgentKind?

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
    }

    // MARK: - Heading

    private var heading: some View {
        VStack(spacing: 6) {
            Text(expanded == nil ? "SEND TO AGENT" : "PICK A SESSION")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(DaddyTheme.textSecondary)

            Text(item.title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DaddyTheme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Text("the task is pasted into the composer, not sent")
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
            ForEach(Self.providers, id: \.self) { kind in
                providerBubble(kind)
            }
        }
    }

    private func providerBubble(_ kind: AgentKind) -> some View {
        let installed = store.isInstalled(kind)
        let live = liveSessions(of: kind)

        return DispatchBubble(
            diameter: 96,
            tint: CompactAgentIcon.tint(for: kind),
            isEnabled: installed,
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
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                ForEach(liveSessions(of: kind), id: \.id) { agent in
                    DispatchBubble(
                        diameter: 78,
                        tint: CompactAgentIcon.tint(for: kind),
                        isEnabled: true,
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
            _ = AppActionDispatcher(store: store).perform(.dispatchOntoAgent(workItemID: item.id, agentID: agent.id))
        }
    }

    private func dispatch(launching kind: AgentKind) {
        onDismiss()
        withAnimation(.smooth(duration: 0.24)) {
            _ = AppActionDispatcher(store: store).perform(.dispatchLaunchingAgent(workItemID: item.id, kind: kind))
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
    let title: String
    let note: String?
    let bubble: AnyView
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                bubble
                    .overlay {
                        Circle()
                            .strokeBorder(tint.opacity(hovering ? 0.9 : 0), lineWidth: 2)
                            .frame(width: diameter, height: diameter)
                    }
                    .scaleEffect(hovering ? 1.06 : 1)
                    .shadow(color: tint.opacity(hovering ? 0.35 : 0), radius: 16)

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
        .animation(.easeOut(duration: 0.14), value: hovering)
        .onHover { hovering = isEnabled && $0 }
    }
}
