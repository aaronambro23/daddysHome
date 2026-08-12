import SwiftUI

// MARK: - Backdrop
//
// Glass needs LIGHT behind it, not COLOR — and specifically it needs *local
// contrast*. A lens only visibly bends something when there is a boundary to
// bend: a bright region hard against a dark one, passing under a panel edge.
//
// The previous pass was too uniform to show any of that: near-white pools at
// 0.30 alpha, then blurred another 26pt on top of an already-soft radial
// falloff. Everything averaged out to flat charcoal, so the panels had
// nothing to refract and read as dark grey cards.
//
// This version keeps the palette neutral but pushes the luminance range hard:
// bright, tight, near-white pools and thin sharp streaks over a mid-dark
// base. Big range, almost no hue.
//
// Every number worth touching lives in `Tuning`.

struct AuroraBackground: View {
    private enum Tuning {
        // Base gradient — lifted off near-black so the bright pools have
        // something to sit against without the darks crushing.
        static let baseTop = Color(hex: "#20242c")
        static let baseMid = Color(hex: "#2b313b")
        static let baseBottom = Color(hex: "#1b1e24")

        // Light pools. Bright and comparatively tight: a defined core with a
        // fast falloff, not a wash.
        static let poolBlur: CGFloat = 10
        static let poolOpacities: [Double] = [0.85, 0.62, 0.48]

        // Streaks. Thin and sharp — these are what actually reveal the lens
        // as they pass under a panel edge.
        static let streakBlur: CGFloat = 4
        static let streakOpacity: Double = 0.55
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let m = min(w, h)

            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate

                ZStack {
                    LinearGradient(
                        stops: [
                            .init(color: Tuning.baseTop, location: 0.0),
                            .init(color: Tuning.baseMid, location: 0.5),
                            .init(color: Tuning.baseBottom, location: 1.0),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    // Bright pools. Faint hue differences read as light
                    // temperature rather than as colour.
                    pool(
                        color: Color(hex: "#e8f0ff"), size: m * 1.05,
                        opacity: Tuning.poolOpacities[0],
                        x: w * 0.26 + drift(t, 21, w * 0.05),
                        y: h * 0.20 + drift(t, 26, h * 0.06, phase: 1.1)
                    )
                    pool(
                        color: Color(hex: "#fff4e6"), size: m * 0.92,
                        opacity: Tuning.poolOpacities[1],
                        x: w * 0.84 + drift(t, 29, w * 0.06, phase: 2.2),
                        y: h * 0.80 + drift(t, 33, h * 0.06)
                    )
                    pool(
                        color: Color(hex: "#eaf2ff"), size: m * 0.80,
                        opacity: Tuning.poolOpacities[2],
                        x: w * 0.62 + drift(t, 37, w * 0.07, phase: 0.6),
                        y: h * 0.44 + drift(t, 31, h * 0.08, phase: 1.8)
                    )
                    // Upper-right — lights the top of the OUTPUT panel, which
                    // was the last dead zone.
                    pool(
                        color: Color(hex: "#f0f6ff"), size: m * 0.72,
                        opacity: 0.52,
                        x: w * 0.88 + drift(t, 43, w * 0.05, phase: 1.4),
                        y: h * 0.16 + drift(t, 39, h * 0.05, phase: 2.6)
                    )

                    // Broad soft band for gentle gradation across the panels.
                    band(w: w, h: h, t: t, period: 47, angle: -22,
                         thickness: h * 0.20, opacity: 0.20, blur: 18)

                    // Thin sharp streaks — the ones that show the refraction.
                    band(w: w, h: h, t: t, period: 34, angle: -22,
                         thickness: h * 0.018, opacity: Tuning.streakOpacity,
                         blur: Tuning.streakBlur, phase: 0.15)
                    band(w: w, h: h, t: t, period: 41, angle: -22,
                         thickness: h * 0.010, opacity: Tuning.streakOpacity * 0.8,
                         blur: Tuning.streakBlur * 0.7, phase: 0.55)
                    band(w: w, h: h, t: t, period: 58, angle: -16,
                         thickness: h * 0.035, opacity: 0.30,
                         blur: 8, phase: 0.82)
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: Pieces

    private func pool(
        color: Color, size: CGFloat, opacity: Double, x: CGFloat, y: CGFloat
    ) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    stops: [
                        .init(color: color.opacity(opacity), location: 0.0),
                        .init(color: color.opacity(opacity * 0.70), location: 0.28),
                        .init(color: color.opacity(opacity * 0.20), location: 0.60),
                        .init(color: color.opacity(0), location: 1.0),
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.5
                )
            )
            .frame(width: size, height: size)
            .blur(radius: Tuning.poolBlur)
            .position(x: x, y: y)
            .blendMode(.plusLighter)
    }

    private func band(
        w: CGFloat, h: CGFloat, t: TimeInterval,
        period: Double, angle: Double,
        thickness: CGFloat, opacity: Double, blur: CGFloat,
        phase: Double = 0
    ) -> some View {
        let travel = h + w * 0.75
        let p = wrap(t / period + phase)

        return Rectangle()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0), location: 0.0),
                        .init(color: .white.opacity(opacity * 0.65), location: 0.30),
                        .init(color: .white.opacity(opacity), location: 0.5),
                        .init(color: .white.opacity(opacity * 0.65), location: 0.70),
                        .init(color: .white.opacity(0), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: w * 2.4, height: thickness)
            .blur(radius: blur)
            .rotationEffect(.degrees(angle))
            .position(x: w / 2, y: -travel * 0.2 + travel * CGFloat(p))
            .blendMode(.plusLighter)
    }

    // MARK: Math

    private func drift(
        _ t: TimeInterval, _ period: Double, _ amplitude: CGFloat, phase: Double = 0
    ) -> CGFloat {
        amplitude * CGFloat(sin(t / period * 2 * .pi + phase))
    }

    private func wrap(_ x: Double) -> Double {
        let r = x.truncatingRemainder(dividingBy: 1.0)
        return r < 0 ? r + 1 : r
    }
}
