import SwiftUI

/// Floating voice-capture indicator, bottom-center.
///
/// A glass capsule with a decorative waveform: energetic travelling waves
/// while recording, a slow low shimmer while transcribing. Purely
/// presentational — the caller shows it whenever the capture controller
/// isn't idle.
struct VoiceCapturePill: View {
    let state: VoiceCaptureState

    private var isRecording: Bool { state == .recording }

    var body: some View {
        HStack(spacing: 13) {
            WaveformBars(energetic: isRecording)

            VStack(alignment: .leading, spacing: 3) {
                Text(isRecording ? "Listening…" : "Transcribing…")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(DaddyTheme.textPrimary)
                    .contentTransition(.opacity)
                Text(isRecording ? "tap ⌥ to stop · esc to cancel" : "turning speech into actions")
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(DaddyTheme.textTertiary)
                    .contentTransition(.opacity)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .insetSurface(cornerRadius: 20)
        .shadow(color: DaddyTheme.accent.opacity(isRecording ? 0.22 : 0.08), radius: 18, y: 6)
        .animation(.easeInOut(duration: 0.3), value: isRecording)
    }
}

/// Decorative travelling-wave bars. Driven by wall-clock time through
/// `TimelineView`, so there's no state to start or stop — mounting the view
/// starts the motion, removing it stops it.
private struct WaveformBars: View {
    let energetic: Bool

    private static let barCount = 17
    private static let maxHeight: CGFloat = 24

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            HStack(spacing: 3) {
                ForEach(0..<Self.barCount, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(barColor(index: i))
                        .frame(width: 3, height: barHeight(at: context.date, index: i))
                        // The timeline already steps every frame; animating the
                        // frame change would lag a step behind and smear it.
                        .transaction { $0.animation = nil }
                }
            }
            .shadow(
                color: DaddyTheme.accent.opacity(energetic ? 0.55 : 0.15),
                radius: energetic ? 6 : 3
            )
        }
        .frame(height: Self.maxHeight, alignment: .center)
    }

    private func barColor(index i: Int) -> Color {
        let center = Double(Self.barCount - 1) / 2
        let falloff = 1 - abs(Double(i) - center) / (center + 1)
        if energetic {
            return DaddyTheme.accent.opacity(0.45 + 0.5 * falloff)
        } else {
            return Color.white.opacity(0.28 + 0.3 * falloff)
        }
    }

    private func barHeight(at date: Date, index i: Int) -> CGFloat {
        let t = date.timeIntervalSinceReferenceDate
        let center = Double(Self.barCount - 1) / 2
        let envelope = 1 - (abs(Double(i) - center) / (center + 1)) * 0.65
        if energetic {
            let wave = abs(sin(t * 5.2 + Double(i) * 0.62)) * 0.7
                + abs(sin(t * 9.1 + Double(i) * 1.31 + 1.7)) * 0.3
            return (3 + 19 * wave) * envelope
        } else {
            let shimmer = 0.45 + 0.15 * sin(t * 1.8 + Double(i) * 0.5)
            return (3 + 10 * shimmer) * envelope
        }
    }
}
