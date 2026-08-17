import SwiftUI

/// The agents of one provider, as a stacked deck of bubbles.
///
/// Stacked rather than spaced for two reasons. It reads as a group at a glance
/// — a crew, not a list — and its width is bounded, which the old plain `HStack`
/// was not: that row grew by ~46pt per agent and at ten agents ran clean off the
/// panel. Here the overlap plus a hard cap of `maxVisible` means the deck is the
/// same width at three agents or thirty.
///
/// Clicking a bubble selects that agent. It never changes the layout.
struct AgentBubbleRow: View {
    let agents: [MockAgent]
    let activeID: String?
    var bubbleSize: CGFloat = 30
    let onSelect: (String) -> Void

    /// Past this the deck stops growing and the rest collapse into a `+N` pill.
    private let maxVisible = 7

    @State private var hoveredID: String?

    /// Bubbles sit on top of each other, and fan apart while the cursor is in
    /// the deck so you can pick one out.
    private var overlap: CGFloat {
        let stacked = -bubbleSize * 0.4
        let fanned = -bubbleSize * 0.18
        return hoveredID == nil ? stacked : fanned
    }

    private var visible: [MockAgent] { Array(agents.prefix(maxVisible)) }
    private var overflow: [MockAgent] { Array(agents.dropFirst(maxVisible)) }

    var body: some View {
        HStack(spacing: overlap) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, agent in
                bubble(agent, index: index)
            }

            if !overflow.isEmpty {
                overflowPill
                    .padding(.leading, -overlap + 6)
                    .zIndex(-1)
            }
        }
        // Hover lift and the fan both ride this one curve.
        .animation(.smooth(duration: 0.2), value: hoveredID)
        .animation(.smooth(duration: 0.24), value: agents.count)
        // The lifted bubble and its shadow need room to leave the deck without
        // being clipped, and without changing the tile's height.
        .padding(.top, 8)
        .padding(.trailing, 4)
        .frame(height: bubbleSize + 14, alignment: .leading)
    }

    private func bubble(_ agent: MockAgent, index: Int) -> some View {
        let isHovered = hoveredID == agent.id
        let isActive = activeID == agent.id

        return CompactAgentIcon(
            agent: agent,
            isSelected: isActive,
            size: bubbleSize,
            isDimmed: !isActive,
            ringsAgainstBackdrop: true,
            onTap: { onSelect(agent.id) }
        )
        .scaleEffect(isHovered ? 1.18 : 1)
        .offset(y: isHovered ? -6 : 0)
        .shadow(
            color: Color.black.opacity(isHovered ? 0.45 : 0),
            radius: isHovered ? 8 : 0,
            y: isHovered ? 3 : 0
        )
        // Earlier bubbles overlap later ones; whatever is hovered or active
        // comes to the very front so it is never half-covered.
        .zIndex(isHovered ? 1000 : (isActive ? 900 : Double(visible.count - index)))
        .onHover { hovering in
            hoveredID = hovering ? agent.id : (hoveredID == agent.id ? nil : hoveredID)
        }
    }

    private var overflowPill: some View {
        GlassDropdown(
            items: overflow.map { agent in
                GlassDropdownItem(
                    id: agent.id,
                    title: "\(agent.displayName) · \(agent.workUnitID)",
                    note: StateColors.name(for: agent.state).lowercased()
                ) {
                    onSelect(agent.id)
                }
            },
            width: 230
        ) {
            Text("+\(overflow.count)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(DaddyTheme.textSecondary)
        }
    }
}
