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
        if compact {
            HStack(spacing: 6) {
                label(window)
                meter(window)
                percentage(window)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    label(window)
                    meter(window)
                    percentage(window)
                }

                HStack(spacing: 4) {
                    availabilityGlyph
                    Text(resetDescription(window.resetsAt))
                }
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundStyle(availabilityColor)
            }
        }
    }

    private func label(_ window: ProviderUsageWindow) -> some View {
        HStack(spacing: 3) {
            Text(window.label)
                .lineLimit(1)
            if (snapshot?.windows.count ?? 0) > 1 {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 6.5, weight: .bold))
            }
        }
        .font(.system(size: compact ? 8.5 : 9, weight: .medium, design: .monospaced))
        .foregroundStyle(DaddyTheme.textTertiary)
    }

    private func meter(_ window: ProviderUsageWindow) -> some View {
        GeometryReader { geometry in
            let width = max(0, geometry.size.width * window.usedPercent / 100)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.07))

                Capsule()
                    .fill(capacityColor(window.usedPercent))
                    .frame(width: width)
            }
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.75)
            }
            .overlay(alignment: .trailing) {
                Capsule()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 2, height: compact ? 4 : 5)
                    .offset(x: 3)
            }
        }
        .frame(width: compact ? 46 : 62, height: compact ? 8 : 10)
        .opacity(isStale ? 0.65 : 1)
    }

    private func percentage(_ window: ProviderUsageWindow) -> some View {
        Text("\(Int(window.usedPercent.rounded()))%")
            .font(.system(size: compact ? 8.5 : 9.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(capacityColor(window.usedPercent))
            .monospacedDigit()
            .frame(width: compact ? 30 : 34, alignment: .trailing)
    }

    private var unavailable: some View {
        HStack(spacing: 6) {
            Text(statusMessage)
                .font(.system(size: compact ? 8.5 : 9, design: .monospaced))
                .foregroundStyle(DaddyTheme.textMuted)
                .lineLimit(1)

            ZStack {
                Capsule()
                    .fill(Color.white.opacity(0.05))
                Capsule()
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.75)
                Rectangle()
                    .fill(DaddyTheme.textMuted)
                    .frame(width: 1, height: compact ? 10 : 12)
                    .rotationEffect(.degrees(55))
            }
            .frame(width: compact ? 46 : 62, height: compact ? 8 : 10)
        }
        .frame(maxWidth: compact ? .infinity : nil, alignment: .leading)
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
        let seconds = max(0, Int(date.timeIntervalSinceNow))
        if seconds < 60 { return "resets in <1m" }
        if seconds < 3_600 { return "resets in \(seconds / 60)m" }
        if seconds < 86_400 {
            return "resets in \(seconds / 3_600)h \((seconds % 3_600) / 60)m"
        }
        return "resets in \(seconds / 86_400)d \((seconds % 86_400) / 3_600)h"
    }
}
