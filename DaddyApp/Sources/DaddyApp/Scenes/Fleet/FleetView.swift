import SwiftUI

struct FleetView: View {
    @Environment(MockStore.self) private var store

    var body: some View {
        HStack(spacing: 16) {
            ProjectsSidebar()
                .frame(width: 264)

            AgentDashboard()
                .frame(minWidth: 380)

            // Show progress panel if a project is selected
            if let project = store.selectedProject {
                FileTreeView(project: project)
                    .frame(width: 280)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }

            TerminalPane()
                .frame(width: 496)
        }
    }
}
