import SwiftUI
import DaddyCore

// MARK: - State Colours

enum StateColors {
    static func accent(for state: AgentState) -> Color {
        switch state {
        case .working: return DaddyTheme.working
        case .rateLimited: return DaddyTheme.limited
        case .ready: return DaddyTheme.ready
        case .error: return DaddyTheme.failure
        case .launching: return DaddyTheme.launching
        case .exited: return DaddyTheme.idle
        case .unknown: return DaddyTheme.idle
        }
    }

    static func name(for state: AgentState) -> String {
        switch state {
        case .working: return "WORKING"
        case .rateLimited: return "RATE-LIMITED"
        case .ready: return "READY"
        case .error: return "ERROR"
        case .launching: return "LAUNCHING"
        case .exited: return "EXITED"
        case .unknown: return "UNCLEAR"
        }
    }

    static func glyph(for state: AgentState) -> String? {
        switch state {
        case .working: return nil          // uses the breathing dot instead
        case .rateLimited: return "pause.fill"
        case .ready: return "checkmark"
        case .error: return "xmark"
        case .launching: return "arrow.up.circle"
        case .exited: return "stop.fill"
        case .unknown: return "questionmark"
        }
    }
}

// MARK: - Badge
//
// Lives inside a glass panel, so it is NOT glass. Colour appears only on the
// glyph and the label — never as a filled surface.

struct StatusBadge: View {
    let state: AgentState
    var compact: Bool = false

    var body: some View {
        let accent = StateColors.accent(for: state)

        HStack(spacing: 6) {
            if let glyph = StateColors.glyph(for: state) {
                Image(systemName: glyph)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(accent)
            } else {
                BreathingDot(color: accent, glowRadius: 7, size: 5)
            }

            if !compact {
                Text(StateColors.name(for: state))
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(accent)
            }
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, 5)
        .insetCapsule(tint: accent, opacity: 0.10)
    }
}
