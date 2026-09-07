import SwiftUI
import DaddyCore

/// Send this work item to a coding agent from the board's detail pane.
///
/// One click opens the same four providers as the fleet launch menu. A provider
/// with a live session in the item's project offers those sessions (the one you
/// were looking at first) plus "New session". A provider with nothing running
/// launches. The prompt is pasted, not submitted.
struct WorkItemDispatchMenu: View {
    @Environment(MockStore.self) private var store

    let item: OrchestratorWorkItem
    /// Save the editor first so the prompt is what is on screen, not the last
    /// committed file.
    let onWillDispatch: () -> Void

    var body: some View {
        GlassDropdown(
            items: items,
            width: 240,
            emptyMessage: "Assign a project first",
            chromelessLabel: true,
            label: { trigger }
        )
    }

    private var trigger: some View {
        Text("Send to Agent")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DaddyTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background { Capsule().fill(Color.white.opacity(0.09)) }
            .overlay { Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1) }
            .contentShape(Capsule())
    }

    private var resolvedProject: MockProject? {
        if let id = item.projectID { return store.project(id) }
        if let id = store.selectedProjectID { return store.project(id) }
        return nil
    }

    private var currentSessionID: String? {
        store.detailAgentID ?? store.selectedAgentID
    }

    private var items: [GlassDropdownItem] {
        guard resolvedProject != nil else { return [] }

        return [AgentKind.claude, .codex, .cursor, .opencode].map { kind in
            let installed = store.isInstalled(kind)
            let live = liveSessions(of: kind)
            let children: [GlassDropdownItem]
            if live.isEmpty {
                children = []
            } else {
                children = live.map { agent in
                    let isCurrent = agent.id == currentSessionID
                    return GlassDropdownItem(
                        id: agent.id,
                        title: sessionTitle(agent),
                        note: isCurrent ? "this session" : nil,
                        isSelected: isCurrent,
                        leading: AnyView(ProviderLogo.badge(for: kind, diameter: 24))
                    ) {
                        dispatch(onto: agent)
                    }
                } + [
                    GlassDropdownItem(
                        id: "new-\(kind.rawValue)",
                        title: "New session"
                    ) {
                        dispatch(launching: kind)
                    }
                ]
            }

            return GlassDropdownItem(
                id: kind.rawValue,
                title: kind.rawValue.capitalized,
                note: installed ? (live.isEmpty ? nil : "\(live.count)") : "not installed",
                isEnabled: installed,
                leading: AnyView(ProviderLogo.badge(for: kind, diameter: 24)),
                childrenWidth: 280,
                children: children
            ) {
                dispatch(launching: kind)
            }
        }
    }

    /// The session you were in first, then most recently active.
    private func liveSessions(of kind: AgentKind) -> [MockAgent] {
        guard let project = resolvedProject else { return [] }
        let live = store.agents.filter {
            $0.projectID == project.id && $0.agent == kind && $0.isLive
        }
        return live.sorted { a, b in
            let aCurrent = a.id == currentSessionID
            let bCurrent = b.id == currentSessionID
            if aCurrent != bCurrent { return aCurrent }
            return a.lastOutputAt > b.lastOutputAt
        }
    }

    private func dispatch(onto agent: MockAgent) {
        onWillDispatch()
        withAnimation(.smooth(duration: 0.24)) {
            _ = AppActionDispatcher(store: store).perform(.dispatchOntoAgent(workItemID: item.id, agentID: agent.id))
        }
    }

    private func dispatch(launching kind: AgentKind) {
        onWillDispatch()
        withAnimation(.smooth(duration: 0.24)) {
            _ = AppActionDispatcher(store: store).perform(.dispatchLaunchingAgent(workItemID: item.id, kind: kind))
        }
    }

    private func sessionTitle(_ agent: MockAgent) -> String {
        if let index = MockAgent.siblingIndex(for: agent, among: store.agents) {
            return "\(agent.displayName) \(MockAgent.romanNumeral(forZeroBased: index))"
        }
        return agent.displayName
    }
}
