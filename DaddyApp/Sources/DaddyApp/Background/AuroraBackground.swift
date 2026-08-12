import SwiftUI

// MARK: - Backdrop
//
// Glass needs LIGHT behind it, not COLOR. The previous version pumped
// saturated blue/purple/teal back there, which the glass then blurred and
// reflected until every panel looked like flat dark paint.
//
// So: a cool charcoal base with large, soft, near-white light pools and a
// couple of pale bands drifting across. Big luminance range, almost no hue.
// The panels sit over the bright pools and their edges catch the light, which
// is what actually makes glass legible.

struct AuroraBackground: View {
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
                            .init(color: Color(hex: "#141619"), location: 0.0),
                            .init(color: Color(hex: "#1d2027"), location: 0.5),
                            .init(color: Color(hex: "#15171c"), location: 1.0),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    // Light pools. Near-white — the faint hue differences read
                    // as light temperature, not as colour.
                    pool(
                        color: Color(hex: "#dce6f5"), size: m * 1.15, opacity: 0.30,
                        x: w * 0.26 + drift(t, 21, w * 0.05),
                        y: h * 0.24 + drift(t, 26, h * 0.06, phase: 1.1)
                    )
                    pool(
                        color: Color(hex: "#f2ece2"), size: m * 1.0, opacity: 0.22,
                        x: w * 0.80 + drift(t, 29, w * 0.06, phase: 2.2),
                        y: h * 0.74 + drift(t, 33, h * 0.06)
                    )
                    pool(
                        color: Color(hex: "#e3e9f2"), size: m * 0.9, opacity: 0.16,
                        x: w * 0.56 + drift(t, 37, w * 0.07, phase: 0.6),
                        y: h * 0.48 + drift(t, 31, h * 0.08, phase: 1.8)
                    )

                    // Pale bands sweeping across where the panels sit, so the
                    // glass edges have moving structure to refract.
                    band(w: w, h: h, t: t, period: 44, angle: -22,
                         thickness: h * 0.13, opacity: 0.20, blur: 14)
                    band(w: w, h: h, t: t, period: 61, angle: -22,
                         thickness: h * 0.05, opacity: 0.16, blur: 8, phase: 0.45)
                    band(w: w, h: h, t: t, period: 79, angle: -15,
                         thickness: h * 0.22, opacity: 0.10, blur: 24, phase: 0.8)
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
                    colors: [color.opacity(opacity), color.opacity(0)],
                    center: .center,
                    startRadius: size * 0.03,
                    endRadius: size * 0.5
                )
            )
            .frame(width: size, height: size)
            .blur(radius: 26)
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
                        .init(color: .white.opacity(opacity * 0.5), location: 0.35),
                        .init(color: .white.opacity(opacity), location: 0.5),
                        .init(color: .white.opacity(opacity * 0.5), location: 0.65),
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
