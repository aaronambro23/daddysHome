import SwiftUI
import DaddyCore

/// One agent, as a bubble.
///
/// Sized by the caller rather than fixed, because it is used both loose and in
/// a stacked deck (`AgentBubbleRow`) where the bubbles overlap. The ring is
/// painted in the panel's own ground so that overlap reads as depth rather than
/// as two circles smeared together.
struct CompactAgentIcon: View {
    let agent: MockAgent
    let isSelected: Bool
    var size: CGFloat = 34
    /// Dims to let an active sibling read first. The deck sets this.
    var isDimmed: Bool = false
    /// Drawn around the bubble so a stacked neighbour reads as *in front*.
    var ringsAgainstBackdrop: Bool = false
    /// 0-based start-order among live same-provider siblings. Nil when this
    /// provider has only one live agent — the logo is enough.
    var siblingIndex: Int? = nil
    let onTap: () -> Void

    @State private var hovering = false

    private var dotSize: CGFloat { max(7, size * 0.28) }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(Self.tint(for: agent.agent).opacity(0.16))
                    .overlay(
                        Circle().strokeBorder(
                            Self.tint(for: agent.agent).opacity(0.4),
                            lineWidth: 1
                        )
                    )
                    .frame(width: size, height: size)
                    .overlay {
                        ZStack {
                            ProviderLogo.mark(for: agent.agent, diameter: size)
                            if let siblingIndex {
                                Text(MockAgent.romanNumeral(forZeroBased: siblingIndex))
                                    .font(.custom("Didot", size: size * 0.38))
                                    .fontWeight(.bold)
                                    .tracking(0.8)
                                    .foregroundStyle(DaddyTheme.textPrimary.opacity(0.9))
                                    .shadow(color: .black.opacity(0.7), radius: 1, y: 0.5)
                            }
                        }
                    }

                // Trailing-bottom on purpose: in a stacked deck that is the one
                // edge the next bubble never covers. It sits *just inside* the
                // circle rather than hanging off it — pushed outside, a row of
                // overlapping bubbles grows a row of loose crumbs underneath.
                if agent.state == .ready {
                    BouncingBadge(color: StateColors.accent(for: agent.state), glowRadius: 5, size: dotSize)
                        .offset(x: -0.5, y: -0.5)
                } else {
                    Circle()
                        .fill(StateColors.accent(for: agent.state))
                        .frame(width: dotSize, height: dotSize)
                        .overlay(Circle().strokeBorder(DaddyTheme.bubbleRim, lineWidth: 1.5))
                        .offset(x: -0.5, y: -0.5)
                }
            }
        }
        .buttonStyle(.plain)
        .background {
            // Separates overlapping bubbles. Painted behind, slightly larger
            // than the bubble, so it reads as a rim rather than a border.
            if ringsAgainstBackdrop {
                Circle()
                    .fill(DaddyTheme.bubbleRim)
                    .frame(width: size + 5, height: size + 5)
            }
        }
        .opacity(isDimmed && !hovering ? 0.55 : 1)
        .onHover { hovering = $0 }
        .help("\(agent.displayName) · \(agent.label) · \(StateColors.name(for: agent.state))")
        .overlay {
            if isSelected {
                Circle()
                    .strokeBorder(DaddyTheme.textPrimary.opacity(0.5), lineWidth: 1.5)
                    .frame(width: size + 4, height: size + 4)
            }
        }
    }

    /// The fallback mark. Bubbles show `ProviderLogo` now; this is what they
    /// fall back to when the resource bundle is missing.
    nonisolated static func monogram(for kind: AgentKind) -> String {
        switch kind {
        case .claude: return "C"
        case .codex: return "X"
        case .cursor: return "U"
        case .opencode: return "O"
        }
    }

    nonisolated static func tint(for kind: AgentKind) -> Color {
        switch kind {
        case .claude: return DaddyTheme.providerClaude
        case .codex: return DaddyTheme.providerCodex
        case .cursor: return DaddyTheme.providerCursor
        case .opencode: return DaddyTheme.providerOpenCode
        }
    }
}
