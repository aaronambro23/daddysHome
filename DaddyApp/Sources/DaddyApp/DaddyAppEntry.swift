import SwiftUI
import DaddyCore

@main
struct DaddyAppEntry: App {
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
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}
