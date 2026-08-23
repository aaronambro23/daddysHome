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
    /// The row that ends the session. Drawn as a filled red block rather than a
    /// line of text, so the one item you cannot undo never reads as a peer of
    /// the ones you can.
    var isDestructive: Bool = false
    /// Optional mark before the title. Type-erased on purpose: the dropdown is
    /// a generic component and has no business knowing about providers, but a
    /// list of four products reads far faster with their logos on it.
    var leading: AnyView?
    /// One nested level, shown in a popover attached to this row on hover.
    var children: [GlassDropdownItem]
    let action: () -> Void

    init(
        id: String,
        title: String,
        note: String? = nil,
        isEnabled: Bool = true,
        isDestructive: Bool = false,
        leading: AnyView? = nil,
        children: [GlassDropdownItem] = [],
        action: @escaping () -> Void = {}
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.isEnabled = isEnabled
        self.isDestructive = isDestructive
        self.leading = leading
        self.children = children
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

    /// Hands the trigger's whole appearance to the caller: no padding, no
    /// capsule, no hit shape of our own. For a trigger that has to *be* a
    /// specific shape — the plus circle that sits in the agent deck as a peer of
    /// the bubbles — chrome wrapped around the label is the one thing that stops
    /// it matching.
    var chromelessLabel: Bool = false

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
            if chromelessLabel {
                label()
            } else {
                label()
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .insetCapsule(opacity: hoveringTrigger || isOpen ? 0.16 : 0.08)
                    .contentShape(Capsule())
            }
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
                    GlassDropdownRow(item: item) { selected in
                        if !staysOpenOnPick { isOpen = false }
                        selected.action()
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
    let onSelect: (GlassDropdownItem) -> Void

    @State private var hovering = false
    @State private var submenuOpen = false
    @State private var submenuCloseTask: Task<Void, Never>?

    var body: some View {
        Button {
            if item.children.isEmpty {
                onSelect(item)
            } else {
                submenuOpen = true
            }
        } label: {
            rowLabel
        }
        .buttonStyle(.plain)
        .disabled(!item.isEnabled)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rowFill)
        }
        .overlay {
            if item.isDestructive {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        DaddyTheme.failure.opacity(hovering && item.isEnabled ? 0.55 : 0.32)
                    )
            }
        }
        .onHover(perform: handleRowHover)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .popover(
            isPresented: $submenuOpen,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .leading
        ) {
            submenu
        }
        .onDisappear { submenuCloseTask?.cancel() }
    }

    private var rowLabel: some View {
        HStack(spacing: 9) {
            if let leading = item.leading {
                leading
                    .opacity(item.isEnabled ? 1 : 0.4)
            }

            Text(item.title)
                .font(.system(size: 12, weight: item.isDestructive ? .semibold : .medium))
                .foregroundStyle(titleColor)

            Spacer(minLength: 6)

            if let note = item.note {
                Text(note)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(DaddyTheme.textMuted)
            }

            if !item.children.isEmpty {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DaddyTheme.textMuted)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Destructive rows carry their fill at rest — that is the whole point of
    /// them — and only deepen on hover; everything else lights up from nothing.
    private var rowFill: Color {
        guard item.isEnabled else { return .clear }
        if item.isDestructive {
            return DaddyTheme.failure.opacity(hovering ? 0.26 : 0.15)
        }
        return hovering ? DaddyTheme.insetFill : .clear
    }

    private var titleColor: Color {
        guard item.isEnabled else { return DaddyTheme.textVeryDim }
        return item.isDestructive ? DaddyTheme.failure : DaddyTheme.textPrimary
    }

    private var submenu: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(item.children) { child in
                GlassDropdownRow(item: child) { selected in
                    submenuOpen = false
                    onSelect(selected)
                }
            }
        }
        .padding(6)
        .frame(width: 190)
        .background(DaddyTheme.popoverBackground)
        .onHover { inside in
            if inside {
                submenuCloseTask?.cancel()
            } else {
                scheduleSubmenuClose()
            }
        }
    }

    private func handleRowHover(_ inside: Bool) {
        hovering = inside
        guard item.isEnabled, !item.children.isEmpty else { return }

        if inside {
            submenuCloseTask?.cancel()
            submenuOpen = true
        } else {
            scheduleSubmenuClose()
        }
    }

    private func scheduleSubmenuClose() {
        submenuCloseTask?.cancel()
        submenuCloseTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            submenuOpen = false
        }
    }
}
