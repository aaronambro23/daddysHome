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
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}
