import SwiftUI
import DaddyCore

/// Fast switching inside terminal focus mode.
///
/// The current agent is already named in the breadcrumb, so repeating its
/// bubble wastes the most valuable toolbar space. Show the three most recently
/// active alternatives instead; larger fleets collapse into a searchable list.
struct FocusAgentSwitcher: View {
    @Environment(MockStore.self) private var store

    let agents: [MockAgent]
    let activeID: String
    /// Where the plus at the end of the deck will launch. Nil disables it with
    /// an explanation rather than launching into a guess.
    let launchTarget: MockProject?
    let onSelect: (String) -> Void

    @State private var hoveredID: String?
    @State private var isOpen = false
    @State private var query = ""

    private var alternatives: [MockAgent] {
        agents
            .filter { $0.id != activeID }
            .sorted { $0.lastOutputAt > $1.lastOutputAt }
    }

    private var quick: [MockAgent] {
        Array(alternatives.prefix(3))
    }

    private var overflowCount: Int {
        max(0, alternatives.count - quick.count)
    }

    /// The plus is not an agent, so it needs a name of its own to take part in
    /// the deck's one-at-a-time hover.
    private static let plusID = "__new__"

    /// The overlap the deck sits at, and the gap it opens to when a bubble is
    /// hovered. Named because the plus has to ride the same two numbers.
    private var deckSpacing: CGFloat { hoveredID == nil ? -9 : 5 }

    private var matches: [MockAgent] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return alternatives }
        return alternatives.filter { agent in
            let project = store.project(agent.projectID)?.name ?? ""
            return agent.displayName.lowercased().contains(needle)
                || agent.workUnitID.lowercased().contains(needle)
                || project.lowercased().contains(needle)
        }
    }

    var body: some View {
        if !alternatives.isEmpty || launchTarget != nil {
            HStack(spacing: deckSpacing) {
                ForEach(Array(quick.enumerated()), id: \.element.id) { index, agent in
                    quickBubble(agent, index: index)
                }

                if overflowCount > 0 {
                    overflowButton
                        .padding(.leading, hoveredID == nil ? 13 : 2)
                }

                // Last in the row, so "one more agent" is the circle after the
                // ones you already have. It is a peer of the bubbles rather
                // than a button beside them: same 34pt, same backdrop rim, same
                // lift — which is only true because it lives inside this HStack
                // and rides its overlap and its hover curve.
                if launchTarget != nil {
                    plusBubble
                        // Overlapped like a bubble, not spaced like the overflow
                        // pill — it is meant to read as the next circle in the
                        // row. The exception is when it *follows* that pill,
                        // which is a capsule and has already stepped out of the
                        // stack to say so.
                        .padding(.leading, overflowCount > 0 ? (hoveredID == nil ? 13 : 2) : 0)
                }
            }
            .frame(height: 44)
            .animation(.smooth(duration: 0.18), value: hoveredID)
        }
    }

    private var plusBubble: some View {
        let hovering = hoveredID == Self.plusID

        return RadialProviderMenu(
            items: launchTarget.map { radialItems(for: $0) } ?? [],
            onDismiss: {}
        ) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(hovering ? DaddyTheme.textPrimary : DaddyTheme.textSecondary)
                .frame(width: 34, height: 34)
                .background {
                    Circle().fill(Color.white.opacity(hovering ? 0.16 : 0.10))
                }
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(hovering ? 0.26 : 0.16), lineWidth: 1)
                }
                .background {
                    Circle()
                        .fill(DaddyTheme.bubbleRim)
                        .frame(width: 39, height: 39)
                }
                .contentShape(Circle())
        }
        .scaleEffect(hovering ? 1.14 : 1)
        .offset(y: hovering ? -3 : 0)
        .zIndex(hovering ? 100 : 0)
        .onHover { isHovering in
            hoveredID = isHovering ? Self.plusID : (hoveredID == Self.plusID ? nil : hoveredID)
        }
        .help(launchName.map { "Launch another agent in \($0)" } ?? "Launch another agent")
    }

    private func radialItems(for project: MockProject) -> [ProviderMenuItem] {
        [AgentKind.claude, .codex, .cursor, .opencode].map { kind in
            let installed = store.isInstalled(kind)
            return ProviderMenuItem(
                kind: kind,
                isEnabled: installed
            ) {
                store.launchReal(kind, in: project)
            }
        }
    }

    private var launchName: String? { launchTarget?.name }

    private func quickBubble(_ agent: MockAgent, index: Int) -> some View {
        let hovering = hoveredID == agent.id

        return CompactAgentIcon(
            agent: agent,
            isSelected: false,
            // 34, not 26. These are the only way to jump between sessions
            // without leaving focus mode, and at 26 the logo inside them was
            // too small to tell one provider from another at a glance.
            size: 34,
            ringsAgainstBackdrop: true,
            onTap: { onSelect(agent.id) }
        )
        .scaleEffect(hovering ? 1.14 : 1)
        .offset(y: hovering ? -3 : 0)
        .zIndex(hovering ? 100 : Double(quick.count - index))
        .onHover { isHovering in
            hoveredID = isHovering ? agent.id : (hoveredID == agent.id ? nil : hoveredID)
        }
    }

    private var overflowButton: some View {
        Button {
            isOpen.toggle()
        } label: {
            Text("+\(overflowCount)")
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(DaddyTheme.textSecondary)
                .frame(minWidth: 32, minHeight: 32)
                .insetCapsule(opacity: isOpen ? 0.16 : 0.08)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Find another agent")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            switcherPopover
        }
        .onChange(of: isOpen) { _, open in
            if !open { query = "" }
        }
    }

    private var switcherPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DaddyTheme.textMuted)

                TextField("Search agents, projects, or work units", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(DaddyTheme.textPrimary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .insetSurface(cornerRadius: 9)

            if matches.isEmpty {
                Text("No matching agents")
                    .font(.system(size: 11))
                    .foregroundStyle(DaddyTheme.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(matches) { agent in
                            agentRow(agent)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .padding(8)
        .frame(width: 330)
        .background(DaddyTheme.popoverBackground)
    }

    private func agentRow(_ agent: MockAgent) -> some View {
        Button {
            isOpen = false
            onSelect(agent.id)
        } label: {
            HStack(spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    ProviderLogo.badge(for: agent.agent, diameter: 28)

                    Circle()
                        .fill(StateColors.accent(for: agent.state))
                        .frame(width: 7, height: 7)
                        .overlay(Circle().strokeBorder(DaddyTheme.bubbleRim, lineWidth: 1))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(agent.displayName) · \(store.project(agent.projectID)?.name ?? "")")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DaddyTheme.textPrimary)
                        .lineLimit(1)

                    Text(agent.workUnitID)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(DaddyTheme.textMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Text(StateColors.name(for: agent.state))
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(StateColors.accent(for: agent.state))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DaddyTheme.insetFill)
        }
    }
}
