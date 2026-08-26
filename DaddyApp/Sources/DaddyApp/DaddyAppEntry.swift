import SwiftUI
import DaddyCore

/// Claims foreground-application status at startup.
///
/// A bundled app gets this from its Info.plist. Run straight out of
/// `.build/debug/`, though, macOS treats the process as an extension of the
/// terminal that started it: no Dock icon, no menu bar of its own, and — the
/// part that actually bites — the terminal stays the "frontmost application".
/// Dictation then pastes into the terminal instead of into Daddy, which makes
/// the frontmost-only voice design impossible to use, or even to test.
///
/// Use `bundle.sh` for the real thing. This makes the unbundled binary behave.
final class AppActivator: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct DaddyAppEntry: App {
    @NSApplicationDelegateAdaptor(AppActivator.self) private var activator
    @State private var store = MockStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .frame(minWidth: 1400, minHeight: 900)
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: NSApplication.willTerminateNotification
                    )
                ) { _ in
                    // Otherwise every launched agent — and the Node processes
                    // it spawned — keeps running after the window closes.
                    store.shutdownAllRealSessions()
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: NSApplication.didBecomeActiveNotification
                    )
                ) { _ in
                    store.acknowledgeReadyAttention()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        // ⌘N belongs to the file tree.
        //
        // A `WindowGroup` puts "New Window" in the File menu for free, and a
        // menu key equivalent is matched before the event ever reaches the
        // focused view — so the rail's "new file" shortcut was unreachable by
        // construction, not by conflict. Daddy is one window with one fleet in
        // it; a second copy of it was never a thing this app could usefully do.
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
