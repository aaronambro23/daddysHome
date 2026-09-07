import SwiftUI

// MARK: - Glass
//
// Straight from "Applying Liquid Glass to custom views":
//
//   • "Assign a tint color to suggest prominence."
//     Tint is for rare emphasis, not a default surface treatment. Every
//     surface here is CLEAR glass. There is exactly one tinted element in the
//     whole app (the selected tab), and that is the point of a tint.
//
//   • "Limit the use of Liquid Glass effects onscreen at the same time."
//     Glass is applied at ONE level only — the floating panels, the tab bar
//     and the header capsules. Nothing inside a glass panel is glass. Glass
//     blurs what is behind it, so glass-inside-glass compounds the blur and
//     everything turns to mud.
//
//   • "blurs content behind it, reflects color and light of surrounding
//     content." The glass supplies the color. We supply light, not paint.

extension View {
    /// The one glass primitive. Clear by default.
    func glassSurface(
        _ shape: some Shape = Capsule(),
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glassEffect(glass, in: shape)
    }

    /// A floating panel. Clear glass — no tint, no fill, no border, no shadow.
    func glassPanel(cornerRadius: CGFloat = 26) -> some View {
        glassSurface(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// A floating pill in the chrome (tab bar, header status). Clear unless
    /// something genuinely needs prominence.
    func glassPill(tint: Color? = nil, interactive: Bool = false) -> some View {
        glassSurface(Capsule(), tint: tint, interactive: interactive)
    }
}

// MARK: - Inset surfaces
//
// For anything INSIDE a glass panel: rows, cards, badges, buttons. Plain white
// alpha over the panel's own glass, applied as a `.background` so it sits
// behind the content instead of painting over it.

extension View {
    func insetSurface(
        cornerRadius: CGFloat = 14,
        selected: Bool = false,
        filled: Bool = true
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background {
            shape.fill(
                selected ? DaddyTheme.insetFillSelected
                    : (filled ? DaddyTheme.insetFill : Color.clear)
            )
        }
        .overlay {
            shape.strokeBorder(
                selected ? DaddyTheme.insetStrokeSelected : DaddyTheme.insetStroke,
                lineWidth: 1
            )
        }
    }

    func insetCapsule(tint: Color = .white, opacity: Double = 0.12) -> some View {
        background { Capsule().fill(tint.opacity(opacity)) }
            .overlay { Capsule().strokeBorder(tint.opacity(opacity * 1.8), lineWidth: 1) }
    }
}

// MARK: - Buttons
//
// Plain buttons with an inset surface, so pressing something inside a panel
// doesn't introduce another glass layer.

struct InsetButtonStyle: ButtonStyle {
    var accent: Color = DaddyTheme.textPrimary
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(accent.opacity(configuration.isPressed ? 0.7 : 1))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background {
                Capsule().fill(
                    Color.white.opacity(configuration.isPressed ? 0.22 : (hovering ? 0.14 : 0.07))
                )
            }
            .overlay { Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1) }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.14), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension ButtonStyle where Self == InsetButtonStyle {
    static var inset: InsetButtonStyle { InsetButtonStyle() }
    static func inset(_ accent: Color) -> InsetButtonStyle { InsetButtonStyle(accent: accent) }
}

/// `InsetButtonStyle`'s bigger sibling — for a form's primary/destructive
/// actions (the work item popup's save/delete), where the 10pt pill reads as
/// a label rather than a button worth pressing.
struct LargeInsetButtonStyle: ButtonStyle {
    var accent: Color = DaddyTheme.textPrimary
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(accent.opacity(configuration.isPressed ? 0.7 : 1))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background {
                Capsule().fill(
                    Color.white.opacity(configuration.isPressed ? 0.24 : (hovering ? 0.16 : 0.09))
                )
            }
            .overlay { Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1) }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.14), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension ButtonStyle where Self == LargeInsetButtonStyle {
    static var insetLarge: LargeInsetButtonStyle { LargeInsetButtonStyle() }
    static func insetLarge(_ accent: Color) -> LargeInsetButtonStyle { LargeInsetButtonStyle(accent: accent) }
}

// MARK: - Hairline

struct GlassHairline: View {
    /// Which way the line runs. Vertical is for separating things that sit
    /// beside each other in a row — it fades at both ends the same way, so it
    /// reads as a seam in the glass rather than a drawn border.
    var axis: Axis = .horizontal

    /// Vertical only: how tall the seam is. A rule between two items in a
    /// toolbar should be shorter than the toolbar, or it looks like a wall.
    var length: CGFloat = 26

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.02),
                        Color.white.opacity(0.14),
                        Color.white.opacity(0.02),
                    ],
                    startPoint: axis == .horizontal ? .leading : .top,
                    endPoint: axis == .horizontal ? .trailing : .bottom
                )
            )
            .frame(
                width: axis == .horizontal ? nil : 1,
                height: axis == .horizontal ? 1 : length
            )
    }
}
