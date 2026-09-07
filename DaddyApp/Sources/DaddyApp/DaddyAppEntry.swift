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
        // Only when we are not already a regular app.
        //
        // Bundled, the Info.plist has said so since before launch, and calling
        // this again mid-launch is a policy *transition* — which resets the
        // window server's idea of who should be frontmost, undoing the
        // activation macOS was already performing for a Dock launch.
        if NSApplication.shared.activationPolicy() != .regular {
            NSApplication.shared.setActivationPolicy(.regular)
        }

        // Retried, not fired once.
        //
        // At `didFinishLaunching` SwiftUI has not built the window yet, so a
        // single activation here raises nothing. One deferred pass was not
        // enough either: this window is expensive (aurora, terminals, a
        // 1400x900 minimum) and is still not on screen a run loop later.
        Task { @MainActor in await self.raiseWhenWindowExists() }
    }

    /// Activation, once there is actually a window to raise.
    ///
    /// Polls briefly rather than guessing a delay — the window appears when it
    /// appears, and a fixed `asyncAfter` is either too early on a cold start or
    /// needlessly slow every other time.
    @MainActor
    private func raiseWhenWindowExists() async {
        for _ in 0..<40 {   // ~2s at 50ms, then give up quietly
            if NSApplication.shared.windows.contains(where: { $0.canBecomeMain }) {
                bringToFront()
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        bringToFront()
    }

    /// Clicking the Dock icon, or opening the app again from Spotlight, while
    /// it is already running.
    ///
    /// `didFinishLaunching` does not fire a second time, so without this the
    /// app was only reachable by finding its window by hand.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in self.bringToFront() }
        return true
    }

    @MainActor
    private func bringToFront() {
        let app = NSApplication.shared

        // `NSRunningApplication.activate` — even with every option flag set —
        // is a no-op for a process the terminal launched: macOS 14+ silently
        // ignores `.activateIgnoringOtherApps` (confirmed: `app active=false`
        // in the log after calling it), and there is no other flag that
        // changes that. A background/terminal-spawned process is simply not
        // allowed to steal key focus through this API any more.
        //
        // System Events is not subject to that restriction — it drives focus
        // through the Accessibility layer instead, which is why `tell
        // application "System Events" to set frontmost ... true` still works
        // where the native activation call is silently swallowed. Requires
        // Terminal (or whatever launched this) to hold Automation permission
        // for System Events, granted once via the macOS permission prompt.
        forceActivateViaSystemEvents()
        NSRunningApplication.current.activate(options: [.activateAllWindows])

        // Activating the app and raising its window are separate things: a
        // window left minimised, or buried under another app's, stays exactly
        // where it is otherwise.
        guard let window = app.windows.first(where: { $0.canBecomeMain }) ?? app.windows.first else {
            FileHandle.standardError.write(Data("[activate] no window to raise\n".utf8))
            return
        }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        FileHandle.standardError.write(
            Data("[activate] raised; app active=\(app.isActive) key=\(window.isKeyWindow)\n".utf8)
        )
    }

    /// Drives focus through System Events instead of `NSRunningApplication`,
    /// since the latter is a no-op for a terminal-launched process on
    /// macOS 14+ (see `bringToFront`).
    private func forceActivateViaSystemEvents() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let source = """
        tell application "System Events"
            set frontmost of (first process whose unix id is \(pid)) to true
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            FileHandle.standardError.write(Data("[activate] System Events failed: \(error)\n".utf8))
        }
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
