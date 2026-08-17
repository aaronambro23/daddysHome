import SwiftUI

// A dropdown that looks like the rest of the app.
//
// SwiftUI's `Menu` renders a native `NSMenu`. That is the system's own window,
// drawn with the system's own materials and metrics, and none of it can be
// restyled — so it lands on top of a carefully built glass interface looking
// like it came from a different decade. This is a popover we draw ourselves,
// using the same inset surfaces as everything else inside a panel.

struct GlassDropdownItem: Identifiable {
    let id: String
    let title: String
    /// Shown dimmed to the right of the title — for "not installed" and similar.
    var note: String?
    var isEnabled: Bool = true
    let action: () -> Void

    init(
        id: String,
        title: String,
        note: String? = nil,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.isEnabled = isEnabled
        self.action = action
    }
}

struct GlassDropdown<Label: View>: View {
    let items: [GlassDropdownItem]
    var width: CGFloat = 210
    var emptyMessage: String?

    /// Keeps the popover up after a pick, for menus whose whole point is firing
    /// several in a row — launching four agents should not mean opening the
    /// same menu four times. Escape or a click outside still closes it.
    var staysOpenOnPick: Bool = false

    @ViewBuilder let label: () -> Label

    @State private var isOpen = false
    @State private var hoveringTrigger = false

    var body: some View {
        // Padding and the capsule belong *inside* the button.
        //
        // Applied outside it, as they were, the visible capsule was 9pt wider
        // and 5pt taller on each side than the button's hit region: clicking
        // the middle of the control worked and clicking its rim missed
        // entirely, falling through to whatever was behind. On a provider tile
        // that meant the card opened instead of the menu.
        Button {
            isOpen.toggle()
        } label: {
            label()
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .insetCapsule(opacity: hoveringTrigger || isOpen ? 0.16 : 0.08)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hoveringTrigger = $0 }
        .animation(.easeOut(duration: 0.15), value: hoveringTrigger)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            menuBody
        }
    }

    private var menuBody: some View {
        VStack(alignment: .leading, spacing: 3) {
            if items.isEmpty {
                Text(emptyMessage ?? "Nothing available")
                    .font(.system(size: 11))
                    .foregroundStyle(DaddyTheme.textMuted)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
            } else {
                ForEach(items) { item in
                    GlassDropdownRow(item: item) {
                        if !staysOpenOnPick { isOpen = false }
                        item.action()
                    }
                }
            }
        }
        .padding(6)
        .frame(width: width)
        // The popover chrome is the system's; this paints our own surface
        // across the whole of it so no system grey shows through.
        .background(DaddyTheme.popoverBackground)
    }
}

private struct GlassDropdownRow: View {
    let item: GlassDropdownItem
    let onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(
                        item.isEnabled ? DaddyTheme.textPrimary : DaddyTheme.textVeryDim
                    )

                Spacer(minLength: 6)

                if let note = item.note {
                    Text(note)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(DaddyTheme.textMuted)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!item.isEnabled)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hovering && item.isEnabled ? DaddyTheme.insetFill : Color.clear)
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
