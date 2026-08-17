import SwiftUI

struct ProjectsSidebar: View {
    @Environment(MockStore.self) private var store
    @Binding var expanded: Bool
    var hoverExpansionEnabled = true

    /// Held open by the chevron / folder button rather than by the cursor.
    /// A pinned sidebar ignores hover entirely.
    @State private var pinned = false
    @State private var expandedProjectIDs: Set<String> = []

    /// Leaving the panel starts a short countdown instead of collapsing at
    /// once. Without it, clipping the edge on the way to the grid — or crossing
    /// the gap between the rail and its own popovers — slams the sidebar shut
    /// mid-movement.
    @State private var collapseTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            if expanded {
                HStack(spacing: 12) {
                    Text("PROJECTS")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(DaddyTheme.textPrimary)

                    Spacer()

                    Button(action: { togglePin() }) {
                        Image(systemName: pinned ? "pin.fill" : "chevron.left")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(pinned ? DaddyTheme.textSecondary : DaddyTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                    .help(pinned ? "Unpin" : "Keep open")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                ScrollView {
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
                                    withAnimation(.smooth(duration: 0.3)) {
                                        if !children.isEmpty {
                                            expandedProjectIDs.insert(project.id)
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
                    .padding(10)
                }

                GlassHairline()

                VStack(alignment: .leading, spacing: 6) {
                    Text("FOCUS")
                        .font(.system(size: 9, weight: .medium))
                        .tracking(0.6)
                        .foregroundStyle(DaddyTheme.textMuted)

                    Text(focusDescription)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(DaddyTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            } else {
                VStack(spacing: 4) {
                    Button(action: { togglePin() }) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DaddyTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 8)

                    Divider()
                        .opacity(0.2)
                        .padding(.vertical, 4)

                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(store.rootProjects) { project in
                                Button(action: {
                                    withAnimation(.smooth(duration: 0.3)) {
                                        store.select(project: project.id)
                                    }
                                }) {
                                    Circle()
                                        .fill(store.agentCount(for: project.id) > 0 ? DaddyTheme.working : DaddyTheme.textVeryDim)
                                        .frame(width: 8, height: 8)
                                        .overlay(
                                            Circle().strokeBorder(
                                                store.selectedProjectID == project.id ? DaddyTheme.textPrimary.opacity(0.6) : Color.clear,
                                                lineWidth: 1.5
                                            )
                                        )
                                }
                                .buttonStyle(.plain)
                                .help(project.name)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 10)
            }
        }
        .glassPanel()
        // One hover on the whole panel, expanded or collapsed. The old version
        // only ever expanded from the *first* project's dot, and nothing
        // collapsed it again.
        .onHover { hovering in
            if hovering {
                collapseTask?.cancel()
                collapseTask = nil
                guard hoverExpansionEnabled else { return }
                guard !expanded else { return }
                withAnimation(.smooth(duration: 0.3)) { expanded = true }
            } else {
                scheduleCollapse()
            }
        }
    }

    private func togglePin() {
        pinned.toggle()
        collapseTask?.cancel()
        collapseTask = nil
        withAnimation(.smooth(duration: 0.3)) { expanded = pinned ? true : false }
    }

    private func scheduleCollapse() {
        guard !pinned, expanded else { return }

        collapseTask?.cancel()
        collapseTask = Task {
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.3)) { expanded = false }
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

    private var focusDescription: String {
        guard let project = store.selectedProject else { return "all projects" }
        guard let agent = store.selectedAgent, agent.projectID == project.id else {
            return project.name
        }
        return "\(project.name) › \(agent.workUnitID)"
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
