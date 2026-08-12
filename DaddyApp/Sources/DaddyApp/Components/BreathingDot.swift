import SwiftUI

struct BreathingDot: View {
    let color: Color
    var glowRadius: CGFloat = 8
    var size: CGFloat = 6

    @State private var isBreathing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.85), radius: isBreathing ? glowRadius : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    isBreathing = true
                }
            }
    }
}
