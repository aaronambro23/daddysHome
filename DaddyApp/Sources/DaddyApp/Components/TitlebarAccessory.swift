import AppKit
import SwiftUI

/// Hangs a SwiftUI control in the window's own titlebar, trailing side — the
/// traffic lights' opposite number.
///
/// Drawing it in the content instead does not work, and looks like it should.
/// The window is `.hiddenTitleBar`, so the glass strip along the top of the
/// window *is* the titlebar: AppKit's titlebar container sits above the content
/// view and takes the click for window dragging, and anything drawn under it is
/// visible and dead. A titlebar accessory is the supported way into that strip,
/// and AppKit lays it out, so it stays in the corner through resizes, fullscreen
/// and a window that has not been created yet when this view is first made.
struct TitlebarAccessory<Content: View>: NSViewRepresentable {
    var size: CGSize
    @ViewBuilder var content: () -> Content

    func makeNSView(context: Context) -> NSView {
        let probe = ProbeView()
        let coordinator = context.coordinator
        // The window does not exist yet at `makeNSView` time.
        probe.onWindow = { window in
            install(in: window, coordinator: coordinator)
        }
        return probe
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.host?.rootView = AnyView(content())
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    private func install(in window: NSWindow, coordinator: Coordinator) {
        // `viewDidMoveToWindow` also fires on the way out, and on reparenting.
        guard coordinator.controller == nil else { return }

        let host = NSHostingView(rootView: AnyView(content()))
        host.frame = CGRect(origin: .zero, size: size)

        let controller = NSTitlebarAccessoryViewController()
        controller.layoutAttribute = .trailing
        controller.view = host

        window.addTitlebarAccessoryViewController(controller)
        coordinator.host = host
        coordinator.controller = controller
    }

    @MainActor
    final class Coordinator {
        var host: NSHostingView<AnyView>?
        var controller: NSTitlebarAccessoryViewController?
    }

    final class ProbeView: NSView {
        var onWindow: (@MainActor (NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            onWindow?(window)
        }
    }
}
