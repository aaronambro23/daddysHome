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
    static var working: Color { Color(hex: "#8fe9bb") }
    static var ready: Color { Color(hex: "#cfe0ee") }
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
    static var focusSurface: Color { Color(hex: "#0d111a").opacity(0.97) }

    /// Rim behind a bubble in a stacked deck, so an overlapping neighbour reads
    /// as sitting in front of it rather than merging with it. Dark, because it
    /// stands in for the panel's own ground.
    static var bubbleRim: Color { Color(hex: "#131722").opacity(0.92) }

    /// Fill for popovers we draw ourselves. A popover is its own window, so
    /// there is no panel behind it to tint — it needs an opaque ground of its
    /// own or the system's grey shows through.
    static var popoverBackground: Color { Color(hex: "#141a2e") }
}
