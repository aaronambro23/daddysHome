import SwiftUI
import DaddyCore

struct RadialProviderMenu: View {
    @State private var isOpen = false
    @State private var hoveredKind: AgentKind?

    let items: [ProviderMenuItem]
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            if isOpen {
                Color.black.opacity(0.3)
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { closeMenu() }
                    .transition(.opacity)
            }

            // Center button (plus or X)
            Button(action: { toggleMenu() }) {
                Image(systemName: isOpen ? "xmark" : "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DaddyTheme.textPrimary)
                    .frame(width: 40, height: 40)
                    .background {
                        Circle().fill(Color.white.opacity(isOpen ? 0.08 : 0.12))
                    }
                    .overlay {
                        Circle().strokeBorder(
                            Color.white.opacity(isOpen ? 0.16 : 0.20),
                            lineWidth: 1
                        )
                    }
                    .background {
                        Circle()
                            .fill(DaddyTheme.bubbleRim)
                            .frame(width: 45, height: 45)
                    }
            }
            .buttonStyle(.plain)
            .zIndex(10)

            // Provider circles in compass positions
            if isOpen {
                ForEach(items, id: \.kind.rawValue) { item in
                    let isHovering = hoveredKind == item.kind

                    Button(action: { selectProvider(item) }) {
                        VStack(spacing: 6) {
                            ProviderLogo.badge(for: item.kind, diameter: 28)

                            Text(item.kind.rawValue.capitalized)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(DaddyTheme.textSecondary)
                        }
                        .frame(width: 56, height: 56)
                        .background {
                            Circle().fill(
                                Color.white.opacity(isHovering ? 0.14 : 0.08)
                            )
                        }
                        .overlay {
                            Circle().strokeBorder(
                                Color.white.opacity(isHovering ? 0.24 : 0.14),
                                lineWidth: 1
                            )
                        }
                        .shadow(
                            color: Color.white.opacity(isHovering ? 0.2 : 0.08),
                            radius: isHovering ? 12 : 6,
                            x: 0,
                            y: isHovering ? 2 : 0
                        )
                    }
                    .buttonStyle(.plain)
                    .opacity(item.isEnabled ? 1 : 0.4)
                    .allowsHitTesting(item.isEnabled)
                    .offset(compassOffset(for: item.kind))
                    .scaleEffect(isHovering ? 1.1 : 1)
                    .onHover { hovering in
                        hoveredKind = hovering ? item.kind : nil
                    }
                    .transition(.scale.combined(with: .opacity))
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
        let distance: CGFloat = 90
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
