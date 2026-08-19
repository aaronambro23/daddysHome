import SwiftUI

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        _ = scanner.scanHexInt64(&rgb)

        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Theme
//
// Liquid Glass "reflects color and light of surrounding content" — the glass
// supplies the color. Saturated fills of our own fight it and turn every
// surface to mud, so this palette is deliberately near-monochrome: white text
// hierarchy, and muted semantic colors used only on small state indicators.

enum DaddyTheme {
    /// The single accent. Pale, not neon — it reads on clear glass without
    /// competing with it.
    static var accent: Color { Color(hex: "#b3dcff") }

    // Semantic state colors. Desaturated on purpose: these mark information,
    // they are not decoration. Only ever applied to dots, glyphs and labels —
    // never as a surface fill.
    //
    // `.ready` is saturated green — the loudest colour in the palette, reserved
    // for the one state that needs to jump out: the agent is done and waiting
    // for you. `.working` is amber — a warm "still processing" signal that
    // stands apart from both the success-green and the error-red.
    static var working: Color { Color(hex: "#ffb545") }
    static var ready: Color { Color(hex: "#00dd77") }
    static var limited: Color { Color(hex: "#ecca8f") }
    static var failure: Color { Color(hex: "#f0a6a6") }
    static var launching: Color { Color(hex: "#aecdf2") }
    static var idle: Color { Color(hex: "#9aa4b2") }

    // Provider identity colors — small monogram-circle tint only (icon fill +
    // glyph), same doctrine as the semantic state colors: never a panel surface.
    static var providerClaude: Color { Color(hex: "#e0b88f") }
    static var providerCodex: Color { Color(hex: "#9ecbe8") }
    static var providerCursor: Color { Color(hex: "#c3a6e8") }
    static var providerOpenCode: Color { Color(hex: "#a8d99f") }

    // Text hierarchy — the primary carrier of structure now that surfaces are
    // all clear.
    static var textPrimary: Color { Color.white.opacity(0.96) }
    static var textSecondary: Color { Color.white.opacity(0.72) }
    static var textTertiary: Color { Color.white.opacity(0.50) }
    static var textMuted: Color { Color.white.opacity(0.34) }
    static var textVeryDim: Color { Color.white.opacity(0.16) }

    // Inset surfaces *inside* a glass panel. Plain white alpha, never glass —
    // stacking glass on glass is what dims it.
    static var insetFill: Color { Color.white.opacity(0.055) }
    static var insetFillSelected: Color { Color.white.opacity(0.15) }
    static var insetStroke: Color { Color.white.opacity(0.10) }
    static var insetStrokeSelected: Color { Color.white.opacity(0.28) }

    /// Opaque ground for terminal focus mode. Unlike floating panels, the
    /// workspace must prioritize legibility over showing the aurora through it.
    ///
    /// Genuinely opaque, and it matters. At 0.97 this was *nearly* solid, which
    /// is the worst of both: nobody could see the 3%, and the compositor still
    /// had to keep the entire stack underneath alive — glass re-blurring an
    /// animating aurora — behind every glyph the terminal repainted.
    static var focusSurface: Color { Color(hex: "#0d111a") }

    /// The terminal's own ground, docked and focused alike.
    ///
    /// SwiftTerm clears each dirty rect to transparent and lets the layer's
    /// background show through for default-background cells, so a clear
    /// terminal means every repaint punches a hole all the way down to the
    /// aurora. Solid here; the glass lives everywhere else.
    static var terminalSurface: Color { Color(hex: "#0d111a") }

    /// The corner of a card in the focused workspace — the toolbar, the agent's
    /// terminal and your shell. One number, in one place, because the three sit
    /// side by side with a gap between them and nothing gives a layout away
    /// faster than three corners that nearly match.
    static let focusedPaneRadius: CGFloat = 22

    /// The rail's two widths. Shared, because `FleetView` sizes the frame and
    /// `WorkspaceRail` has to lay its expanded content out at the *wide* one
    /// whatever the frame currently says — otherwise the content is squeezed
    /// into a 50pt frame for the length of the animation, overflows it (a
    /// `.frame(width:)` does not clip), and drags the hover region out with it.
    static let railWideWidth: CGFloat = 264
    static let railNarrowWidth: CGFloat = 50

    /// Rim behind a bubble in a stacked deck, so an overlapping neighbour reads
    /// as sitting in front of it rather than merging with it. Dark, because it
    /// stands in for the panel's own ground.
    static var bubbleRim: Color { Color(hex: "#131722").opacity(0.92) }

    /// Fill for popovers we draw ourselves. A popover is its own window, so
    /// there is no panel behind it to tint — it needs an opaque ground of its
    /// own or the system's grey shows through.
    static var popoverBackground: Color { Color(hex: "#141a2e") }
}
