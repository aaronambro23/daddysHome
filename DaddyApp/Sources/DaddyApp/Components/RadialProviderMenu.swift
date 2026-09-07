import SwiftUI
import DaddyCore

enum FleetCoordinateSpace {
    static let name = "fleet"
}

struct PlusLaunchFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// Plus in the focus deck. Toggles the hoisted overlay; reports its frame in
/// fleet space so the compass can sit on the plus without living in the header.
struct RadialProviderMenu<Label: View>: View {
    @Binding var isOpen: Bool
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .background {
            GeometryReader { g in
                Color.clear.preference(
                    key: PlusLaunchFrameKey.self,
                    value: g.frame(in: .named(FleetCoordinateSpace.name))
                )
            }
        }
    }
}

/// Backdrop + compass, drawn in FleetView on top of the terminal/shell.
struct RadialProviderMenuOverlay: View {
    @Environment(MockStore.self) private var store

    let project: MockProject
    let plusFrame: CGRect
    let isOpen: Bool
    var armedKind: AgentKind? = nil
    let onDismiss: () -> Void

    /// 0 = parked on the plus, 1 = full compass. Drives travel *and* scale so
    /// collapse can play; a transition would unmount before the inward move.
    @State private var expansion: CGFloat = 0
    /// Plus frame at the moment the menu opened. Hover on the deck must not
    /// drag the compass.
    @State private var frozenOrigin: CGPoint?

    private var origin: CGPoint {
        frozenOrigin ?? CGPoint(x: plusFrame.midX, y: plusFrame.midY)
    }

    private var items: [ProviderMenuItem] {
        [AgentKind.claude, .codex, .cursor, .opencode].map { kind in
            let installed = store.isInstalled(kind)
            return ProviderMenuItem(
                kind: kind,
                isEnabled: installed
            ) {
                AppActionDispatcher(store: store).perform(.launchSession(kind: kind, projectID: project.id))
                onDismiss()
            }
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.25 * expansion)
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }
                .allowsHitTesting(expansion > 0.05)

            ForEach(items, id: \.kind.rawValue) { item in
                CompassLaunchBubble(
                    kind: item.kind,
                    isEnabled: item.isEnabled,
                    expansion: expansion,
                    origin: origin,
                    travel: Self.compassOffset(for: item.kind),
                    isArmed: armedKind == item.kind,
                    action: item.action
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(expansion > 0.05)
        .onChange(of: isOpen) { _, open in
            if open {
                frozenOrigin = CGPoint(x: plusFrame.midX, y: plusFrame.midY)
            }
            withAnimation(.smooth(duration: 0.28)) {
                expansion = open ? 1 : 0
            }
        }
        .onAppear {
            if isOpen {
                frozenOrigin = CGPoint(x: plusFrame.midX, y: plusFrame.midY)
                withAnimation(.smooth(duration: 0.28)) { expansion = 1 }
            }
        }
    }

    static func compassOffset(for kind: AgentKind) -> CGSize {
        let distance: CGFloat = 40
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

    /// Same map as `compassOffset`: up Claude, right Codex, down Cursor, left OpenCode.
    static func kind(for event: NSEvent) -> AgentKind? {
        switch event.keyCode {
        case 126: return .claude
        case 124: return .codex
        case 125: return .cursor
        case 123: return .opencode
        default: break
        }
        switch event.specialKey {
        case .upArrow: return .claude
        case .rightArrow: return .codex
        case .downArrow: return .cursor
        case .leftArrow: return .opencode
        default: return nil
        }
    }
}

/// One compass bubble. Hover lifts it along its cardinal, same 1.14 scale as
/// the deck — local so it does not perturb expansion or the frozen origin.
private struct CompassLaunchBubble: View {
    let kind: AgentKind
    let isEnabled: Bool
    let expansion: CGFloat
    let origin: CGPoint
    let travel: CGSize
    var isArmed: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ProviderLogo.badge(for: kind, diameter: 34)
                .background {
                    Circle()
                        .fill(DaddyTheme.bubbleRim)
                        .frame(width: 39, height: 39)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(kind.rawValue.capitalized)
        .opacity((isEnabled ? 1 : 0.4) * expansion)
        .scaleEffect((0.2 + 0.8 * expansion) * (lifted ? 1.14 : 1))
        .allowsHitTesting(expansion > 0.8 && isEnabled)
        .onHover { hovering = isEnabled && $0 }
        .position(
            x: origin.x + travel.width * expansion + lift.width,
            y: origin.y + travel.height * expansion + lift.height
        )
        .animation(.smooth(duration: 0.18), value: hovering)
        .animation(.smooth(duration: 0.18), value: isArmed)
    }

    private var lifted: Bool { isEnabled && (hovering || isArmed) }

    private var lift: CGSize {
        guard lifted else { return .zero }
        let length = hypot(travel.width, travel.height)
        guard length > 0 else { return .zero }
        let extra: CGFloat = 6
        return CGSize(
            width: travel.width / length * extra,
            height: travel.height / length * extra
        )
    }
}

struct ProviderMenuItem {
    let kind: AgentKind
    let isEnabled: Bool
    let action: () -> Void
}
