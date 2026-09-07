import SwiftUI

/// A brief confirmation for a voice-triggered action, with an Undo button
/// when the action is reversible. Auto-dismisses (`MockStore.showVoiceToast`
/// schedules that) — this view is purely presentational.
///
/// Sized to be read from across the desk rather than squinted at. It arrives
/// after you have stopped talking and looked away, so it has about four
/// seconds to say what happened and offer the way out; a 11pt label on a
/// translucent panel over a moving aurora lost that race.
struct VoiceActionToast: View {
    @Environment(MockStore.self) private var store

    let toast: VoiceToast

    var body: some View {
        HStack(spacing: 13) {
            if let icon = toast.icon {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DaddyTheme.accent)
            }

            Text(toast.label)
                .font(.system(size: 15.5, weight: .semibold))
                .foregroundStyle(DaddyTheme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460, alignment: .leading)

            if toast.undoAction != nil {
                // A capsule, not bare text. As an accent-coloured word beside
                // an accent-coloured icon it read as part of the message
                // rather than the one thing here you can click.
                Button {
                    store.undoVoiceToast()
                } label: {
                    Text("Undo")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DaddyTheme.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .insetCapsule(tint: DaddyTheme.accent, opacity: 0.18)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        // Opaque ground before the glass. `insetSurface` alone is a 5% white
        // wash — over the aurora and a lit panel there was not enough contrast
        // behind the text to read it.
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DaddyTheme.focusSurface.opacity(0.96))
        }
        .insetSurface(cornerRadius: 16)
        .shadow(color: .black.opacity(0.45), radius: 22, y: 8)
        .shadow(color: DaddyTheme.accent.opacity(0.18), radius: 14, y: 2)
        .fixedSize(horizontal: true, vertical: false)
    }
}
