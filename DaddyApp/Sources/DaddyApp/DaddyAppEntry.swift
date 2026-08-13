import SwiftUI
import DaddyCore

@main
struct DaddyAppEntry: App {
    @State private var store = AppStore()
    @State private var handoffs = HandoffViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(handoffs)
                .frame(minWidth: 1400, minHeight: 900)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}
