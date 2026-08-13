import SwiftUI

struct FleetView: View {
    @Environment(MockStore.self) private var store
    @State private var sidebarVisible = true

    var body: some View {
        HStack(spacing: 16) {
            if sidebarVisible {
                ProjectsSidebar()
                    .frame(width: 264)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            VStack(spacing: 0) {
                HStack {
                    Button(action: { withAnimation(.smooth(duration: 0.3)) { sidebarVisible.toggle() } }) {
                        Image(systemName: sidebarVisible ? "sidebar.leading" : "sidebar.leading")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DaddyTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 12)
                    .padding(.vertical, 8)

                    Spacer()
                }
                .frame(height: 32)

                AgentDashboard()
            }
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
