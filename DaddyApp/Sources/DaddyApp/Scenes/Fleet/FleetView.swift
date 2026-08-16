import SwiftUI

struct FleetView: View {
    @Environment(MockStore.self) private var store
    @State private var sidebarExpanded = false
    @State private var progressPanelOpen = false
    @State private var progressPanelProjectID: String?

    var body: some View {
        HStack(spacing: 16) {
            ProjectsSidebar(expanded: $sidebarExpanded)
                .frame(width: sidebarExpanded ? 264 : 50)
                .transition(.asymmetric(insertion: .identity, removal: .identity))

            VStack(spacing: 0) {
                AgentDashboard(
                    progressOpen: $progressPanelOpen,
                    onOpenProgress: { projectID in
                        progressPanelProjectID = projectID
                        withAnimation(.smooth(duration: 0.3)) {
                            progressPanelOpen = true
                        }
                    }
                )
                .transition(.opacity)

                if progressPanelOpen {
                    Divider()
                    let panelProject = store.project(progressPanelProjectID ?? "") ?? store.selectedProject
                    FileTreeView(project: panelProject)
                        .frame(height: 280)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .frame(minWidth: 380)

            TerminalPane()
                .frame(width: 496)
        }
        .onAppear {
            installEscapeMonitor()
        }
    }

    private func installEscapeMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 && progressPanelOpen {
                withAnimation(.smooth(duration: 0.3)) {
                    progressPanelOpen = false
                }
                return nil
            }
            return event
        }
    }
}
