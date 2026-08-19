import SwiftUI
import DaddyCore

struct RadialProviderMenu<Label: View>: View {
    @State private var isOpen = false
    @State private var hoveredKind: AgentKind?

    let items: [ProviderMenuItem]
    let onDismiss: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        ZStack(alignment: .center) {
            if isOpen {
                Color.black.opacity(0.25)
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { closeMenu() }
                    .transition(.opacity)
                    .zIndex(5)
            }

            // Center button - the label wrapped in the toggle
            Button(action: { toggleMenu() }) {
                label()
            }
            .buttonStyle(.plain)
            .zIndex(10)

            // Provider circles in compass positions - rendered as overlay to avoid clipping
            if isOpen {
                ForEach(items, id: \.kind.rawValue) { item in
                    let isHovering = hoveredKind == item.kind
                    let offset = compassOffset(for: item.kind)

                    Button(action: { selectProvider(item) }) {
                        VStack(spacing: 8) {
                            ProviderLogo.mark(for: item.kind, diameter: 36)

                            Text(item.kind.rawValue.capitalized)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DaddyTheme.textPrimary)
                        }
                        .frame(width: 100, height: 100)
                        .background {
                            RoundedRectangle(cornerRadius: 50, style: .continuous)
                                .fill(
                                    Color.white.opacity(
                                        isHovering ? 0.16 : 0.08
                                    )
                                )
                                .blur(radius: 12)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 50, style: .continuous)
                                .strokeBorder(
                                    Color.white.opacity(isHovering ? 0.32 : 0.16),
                                    lineWidth: 1.5
                                )
                        }
                        .shadow(
                            color: Color.white.opacity(isHovering ? 0.25 : 0.1),
                            radius: isHovering ? 16 : 8,
                            x: 0,
                            y: isHovering ? 4 : 0
                        )
                    }
                    .buttonStyle(.plain)
                    .opacity(item.isEnabled ? 1 : 0.4)
                    .allowsHitTesting(item.isEnabled)
                    .offset(offset)
                    .scaleEffect(isHovering ? 1.08 : 1)
                    .onHover { hovering in
                        hoveredKind = hovering ? item.kind : nil
                    }
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(6)
                }
            }
        }
        .animation(.smooth(duration: 0.24), value: isOpen)
        .animation(.easeOut(duration: 0.15), value: hoveredKind)
    }

    private func toggleMenu() {
        withAnimation(.smooth(duration: 0.24)) {
            isOpen.toggle()
        }
    }

    private func selectProvider(_ item: ProviderMenuItem) {
        item.action()
        closeMenu()
    }

    private func compassOffset(for kind: AgentKind) -> CGSize {
        let distance: CGFloat = 110
        switch kind {
        case .claude:
            return CGSize(width: 0, height: -distance)
        case .codex:
            return CGSize(width: distance, height: 0)
        case .cursor:
            return CGSize(width: 0, height: distance)
        case .opencode:
            return CGSize(width: -distance, height: 0)
        }
    }

    private func closeMenu() {
        withAnimation(.smooth(duration: 0.24)) {
            isOpen = false
            hoveredKind = nil
        }
        onDismiss()
    }
}

struct ProviderMenuItem {
    let kind: AgentKind
    let isEnabled: Bool
    let action: () -> Void
}
