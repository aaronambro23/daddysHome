import SwiftUI

struct FleetView: View {
    var body: some View {
        HStack(spacing: 16) {
            ProjectsSidebar()
                .frame(width: 264)

            AgentDashboard()
                .frame(minWidth: 380)

            TerminalPane()
                .frame(width: 496)
        }
    }
}
