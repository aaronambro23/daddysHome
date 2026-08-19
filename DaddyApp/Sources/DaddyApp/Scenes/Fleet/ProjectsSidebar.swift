import SwiftUI

/// The project tree, as one section of `WorkspaceRail`.
///
/// This used to be the whole left sidebar — its own glass panel, its own hover
/// and pin behaviour, its own scroll view, its own FOCUS footer. All of that
/// moved up to the rail when the rail gained a second section, so what is left
/// here is the tree itself and the row it is built from.
struct ProjectsSection: View {
    @Environment(MockStore.self) private var store

    /// Owned by the rail, so the tree's disclosure state survives the section
    /// being rebuilt around it.
    @Binding var expandedProjectIDs: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(store.rootProjects) { project in
                let children = store.childProjects(for: project.id)
                let isTreeExpanded = expandedProjectIDs.contains(project.id)

                VStack(alignment: .leading, spacing: 4) {
                    ProjectRow(
                        project: project,
                        isSelected: store.selectedProjectID == project.id,
                        sessionCount: store.agentCount(for: project.id),
                        hasChildren: !children.isEmpty,
                        isExpanded: isTreeExpanded,
                        onDisclosure: { toggleTree(project.id) }
                    ) {
                        // The row is the disclosure. Tapping a project opened it
                        // and nothing else closed it again, so the only way back
                        // was to aim at the chevron — which is there for people
                        // who want to look inside a project without selecting it,
                        // not as the only way out.
                        withAnimation(.smooth(duration: 0.3)) {
                            if !children.isEmpty {
                                if expandedProjectIDs.contains(project.id) {
                                    expandedProjectIDs.remove(project.id)
                                } else {
                                    expandedProjectIDs.insert(project.id)
                                }
                            }
                            store.select(project: project.id)
                        }
                    }

                    if isTreeExpanded {
                        ForEach(children) { child in
                            ProjectRow(
                                project: child,
                                isSelected: store.selectedProjectID == child.id,
                                sessionCount: store.agentCount(for: child.id),
                                hasChildren: false,
                                isExpanded: false,
                                onDisclosure: {}
                            ) {
                                withAnimation(.smooth(duration: 0.3)) {
                                    store.select(project: child.id)
                                }
                            }
                            .padding(.leading, 20)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
            }
        }
    }

    private func toggleTree(_ projectID: String) {
        withAnimation(.smooth(duration: 0.22)) {
            if expandedProjectIDs.contains(projectID) {
                expandedProjectIDs.remove(projectID)
            } else {
                expandedProjectIDs.insert(projectID)
            }
        }
    }
}

// MARK: - Row
//
// Inside a glass panel, so: no glass. Selection is a plain white-alpha inset.

struct ProjectRow: View {
    let project: MockProject
    let isSelected: Bool
    let sessionCount: Int
    let hasChildren: Bool
    let isExpanded: Bool
    let onDisclosure: () -> Void
    let onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            if hasChildren {
                Button(action: onDisclosure) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(DaddyTheme.textMuted)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 12, height: 16)
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Collapse folder" : "Show subfolders")
            } else {
                Color.clear.frame(width: 12, height: 16)
            }

            Circle()
                .fill(sessionCount > 0 ? DaddyTheme.working : DaddyTheme.textVeryDim)
                .frame(width: 6, height: 6)

            Button(action: onTap) {
                HStack(spacing: 6) {
                    Text(project.name)
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? DaddyTheme.textPrimary : DaddyTheme.textSecondary)
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    if sessionCount > 0 {
                        Text("\(sessionCount)")
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(DaddyTheme.working)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .insetCapsule(tint: DaddyTheme.working, opacity: 0.10)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(
                    isSelected ? DaddyTheme.insetFillSelected
                        : (hovering ? DaddyTheme.insetFill : Color.clear)
                )
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(DaddyTheme.insetStrokeSelected, lineWidth: 1)
            }
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}
