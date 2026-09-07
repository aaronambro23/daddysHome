import SwiftUI
import DaddyCore

struct ProviderUsageBattery: View {
    let snapshot: ProviderUsageSnapshot?
    var compact = false

    @State private var selectedWindowID: String?

    var body: some View {
        Button(action: selectNextWindow) {
            if let window {
                battery(window)
            } else {
                unavailable
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help(helpText)
        .onAppear(perform: repairSelection)
        .onChange(of: snapshot?.windows) { _, _ in repairSelection() }
    }

    @ViewBuilder
    private func battery(_ window: ProviderUsageWindow) -> some View {
        HStack(spacing: 8) {
            verticalBattery(window.usedPercent)

            VStack(alignment: .leading, spacing: 1) {
                percentage(window)
                HStack(spacing: 3) {
                    availabilityGlyph
                    Text(bareResetDescription(window.resetsAt))
                        // Fixed slot: "2h 55m" vs "<1m" must never change the
                        // block's width, or the battery slides on every switch.
                        .frame(width: 48, alignment: .leading)
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(availabilityColor)
            }

            // The window switcher: its own readable glyph at the edge, not a
            // tiny mark wedged into the number. The whole block still clicks.
            if (snapshot?.windows.count ?? 0) > 1 {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DaddyTheme.textMuted)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }

    /// Upright cell, filled from the bottom. No label row, no truncation:
    /// the window name lives in the tooltip, the number beside it.
    private func verticalBattery(_ used: Double) -> some View {
        let width: CGFloat = compact ? 11 : 14
        let height: CGFloat = compact ? 20 : 26
        return VStack(spacing: 1.5) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.white.opacity(0.25))
                .frame(width: width * 0.45, height: 2)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(capacityColor(used))
                    .frame(height: max(0, height * min(used, 100) / 100))
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.75)
            }
        }
        .opacity(isStale ? 0.65 : 1)
    }

    private func percentage(_ window: ProviderUsageWindow) -> some View {
        Text("\(Int(window.usedPercent.rounded()))%")
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(capacityColor(window.usedPercent))
            .monospacedDigit()
            .frame(width: 42, alignment: .leading)
    }

    private var unavailable: some View {
        Text(statusMessage)
            .font(.system(size: compact ? 8.5 : 9, design: .monospaced))
            .foregroundStyle(DaddyTheme.textMuted)
            .lineLimit(1)
    }

    @ViewBuilder
    private var availabilityGlyph: some View {
        switch snapshot?.availability {
        case .stale:
            Image(systemName: "clock.arrow.circlepath")
        case .failed:
            Image(systemName: "exclamationmark.triangle")
        case .unavailable:
            Image(systemName: "slash.circle")
        default:
            Image(systemName: "arrow.clockwise")
        }
    }

    private var window: ProviderUsageWindow? {
        guard let windows = snapshot?.windows, !windows.isEmpty else { return nil }
        return windows.first { $0.id == selectedWindowID } ?? windows.first
    }

    private var isStale: Bool {
        if case .stale = snapshot?.availability { return true }
        return false
    }

    private var availabilityColor: Color {
        switch snapshot?.availability {
        case .stale: return DaddyTheme.limited
        case .failed: return DaddyTheme.failure
        case .unavailable: return DaddyTheme.textMuted
        default: return DaddyTheme.textMuted
        }
    }

    private var statusMessage: String {
        guard let snapshot else { return "Loading usage…" }
        switch snapshot.availability {
        case .available: return "Usage unavailable"
        case .stale(let message), .unavailable(let message), .failed(let message):
            return message
        }
    }

    private var helpText: String {
        guard let window else { return statusMessage }
        let state: String
        switch snapshot?.availability {
        case .stale(let reason): state = " · stale: \(reason)"
        case .failed(let reason): state = " · \(reason)"
        case .unavailable(let reason): state = " · \(reason)"
        default: state = ""
        }
        return "\(window.label): \(Int(window.usedPercent.rounded()))% used · \(resetDescription(window.resetsAt))\(state). Click to switch window."
    }

    private func selectNextWindow() {
        guard let windows = snapshot?.windows, windows.count > 1 else { return }
        let current = windows.firstIndex { $0.id == window?.id } ?? 0
        selectedWindowID = windows[(current + 1) % windows.count].id
    }

    private func repairSelection() {
        guard let windows = snapshot?.windows, !windows.isEmpty else {
            selectedWindowID = nil
            return
        }
        if !windows.contains(where: { $0.id == selectedWindowID }) {
            selectedWindowID = windows[0].id
        }
    }

    /// Keyed to usage, not headroom, because that is what the number says.
    ///
    /// Every provider dashboard reports *used*, so this used to force you to do
    /// the subtraction in your head before you could tell whether Daddy and the
    /// dashboard agreed. They agree now.
    private func capacityColor(_ used: Double) -> Color {
        if used >= 80 { return DaddyTheme.failure }
        if used >= 55 { return DaddyTheme.limited }
        return DaddyTheme.ready
    }

    private func resetDescription(_ date: Date?) -> String {
        guard let date else { return "reset time unavailable" }
        return "resets in " + bareResetDescription(date)
    }

    /// The bare number for the header ("2h 55m"). The words live in the
    /// tooltip; the bar has no room for sentences.
    private func bareResetDescription(_ date: Date?) -> String {
        guard let date else { return "—" }
        let seconds = max(0, Int(date.timeIntervalSinceNow))
        if seconds < 60 { return "<1m" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        if seconds < 86_400 {
            return "\(seconds / 3_600)h \((seconds % 3_600) / 60)m"
        }
        return "\(seconds / 86_400)d \((seconds % 86_400) / 3_600)h"
    }
}
