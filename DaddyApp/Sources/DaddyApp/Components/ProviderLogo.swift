import SwiftUI
import AppKit
import DaddyCore

/// Each provider's own mark, loaded once.
///
/// The circles used to carry a letter — C, X, U, O — which is fine to read and
/// slow to *recognise*: at 34pt you are reading a glyph and then mapping it to a
/// product. A logo is recognised at a glance, which is the whole point of the
/// bubble.
///
/// Loaded through `Bundle.module`, so the files live in
/// `Sources/DaddyApp/Resources/` and SwiftPM puts them in a resource bundle. The
/// lookup is cached and every call site has a monogram fallback, because a
/// missing resource bundle must degrade to the old letter rather than to an
/// empty circle. (`bundle.sh` copies that bundle into the .app — if the letters
/// come back after a build, that copy is what broke.)
enum ProviderLogo {
    /// Filenames as they are on disk, casing included — `codexlogo` really is
    /// spelled without the capital.
    private static let filenames: [AgentKind: String] = [
        .claude: "claudeLogo",
        .codex: "codexlogo",
        .cursor: "cursorLogo",
        .opencode: "opencodeLogo",
    ]

    /// One `NSImage` per provider for the life of the process. The bubbles are
    /// rebuilt on every state tick, and decoding a 1000×1000 PNG per tick per
    /// agent is not something to leave to chance.
    private static let cache: [AgentKind: Image] = {
        var loaded: [AgentKind: Image] = [:]
        for (kind, name) in filenames {
            guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
                  let image = NSImage(contentsOf: url)
            else { continue }
            loaded[kind] = Image(nsImage: image)
        }
        return loaded
    }()

    static func image(for kind: AgentKind) -> Image? {
        cache[kind]
    }

    /// The mark as it goes inside a circle: the logo when we have it, the old
    /// monogram when we do not.
    ///
    /// `diameter` is the circle's, not the logo's — the inset is applied here so
    /// every bubble in the app sizes its logo the same way. Cursor's PNG is an
    /// opaque dark square rather than a transparent glyph, so it is clipped to a
    /// rounded rect and reads as a small app icon sitting on the tint.
    @ViewBuilder
    static func mark(for kind: AgentKind, diameter: CGFloat) -> some View {
        // 0.74 rather than 0.62: at bubble sizes the logo is the *only* thing
        // being read, and the extra ring of empty tint bought nothing but a
        // squint. The rim still shows, so the circle keeps its shape.
        let side = diameter * 0.74

        if let image = image(for: kind) {
            image
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: side * 0.28, style: .continuous))
        } else {
            Text(CompactAgentIcon.monogram(for: kind))
                .font(.system(size: diameter * 0.4, weight: .bold))
                .foregroundStyle(CompactAgentIcon.tint(for: kind))
        }
    }

    /// The mark inside its provider-tinted circle — a bubble without the state
    /// dot, for places that show a *provider* rather than a running agent:
    /// menu rows, the switcher list.
    @ViewBuilder
    static func badge(for kind: AgentKind, diameter: CGFloat) -> some View {
        Circle()
            .fill(CompactAgentIcon.tint(for: kind).opacity(0.16))
            .overlay {
                Circle().strokeBorder(
                    CompactAgentIcon.tint(for: kind).opacity(0.4),
                    lineWidth: 1
                )
            }
            .frame(width: diameter, height: diameter)
            .overlay { mark(for: kind, diameter: diameter) }
    }
}
