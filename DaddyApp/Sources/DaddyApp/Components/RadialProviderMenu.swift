import SwiftUI
import DaddyCore

struct RadialProviderMenu<Label: View>: View {
    @State private var isOpen = false

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
                    let offset = compassOffset(for: item.kind)

                    Button(action: { selectProvider(item) }) {
                        VStack(spacing: 4) {
                            ProviderLogo.mark(for: item.kind, diameter: 24)

                            Text(item.kind.rawValue.capitalized)
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(DaddyTheme.textPrimary)
                        }
                        .frame(width: 70, height: 70)
                        .background {
                            RoundedRectangle(cornerRadius: 35, style: .continuous)
                                .fill(Color.white.opacity(0.12))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 35, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .opacity(item.isEnabled ? 1 : 0.4)
                    .allowsHitTesting(item.isEnabled)
                    .offset(offset)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(6)
                }
            }
        }
        .animation(.smooth(duration: 0.24), value: isOpen)
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
        }
        onDismiss()
    }
}

struct ProviderMenuItem {
    let kind: AgentKind
    let isEnabled: Bool
    let action: () -> Void
}
