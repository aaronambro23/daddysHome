import SwiftUI

/// A badge that bounces once when it appears, then breathes steadily.
///
/// Used for the `.ready` state indicator — a circle that starts with an
/// attention-grabbing bounce, then settles into a subtle pulse to keep it
/// noticeable without being annoying.
struct BouncingBadge: View {
    let color: Color
    var glowRadius: CGFloat = 8
    var size: CGFloat = 6

    @State private var isBouncing = false
    @State private var isBreathing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.85), radius: isBouncing ? glowRadius * 1.2 : (isBreathing ? glowRadius : 0))
            .offset(y: isBouncing ? -3 : 0)
            .scaleEffect(isBouncing ? 1.1 : 1)
            .task {
                // Drive both halves of each bounce explicitly. A repeated
                // animation targeting `true` leaves the model value true, so
                // the old badge could remain lifted and its later breathing
                // state never affected the shadow.
                for _ in 0..<3 {
                    withAnimation(.easeOut(duration: 0.14)) {
                        isBouncing = true
                    }
                    try? await Task.sleep(for: .milliseconds(140))
                    guard !Task.isCancelled else { return }

                    withAnimation(.easeIn(duration: 0.14)) {
                        isBouncing = false
                    }
                    try? await Task.sleep(for: .milliseconds(140))
                    guard !Task.isCancelled else { return }
                }

                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    isBreathing = true
                }
            }
    }
}
