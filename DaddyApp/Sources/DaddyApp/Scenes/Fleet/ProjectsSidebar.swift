import SwiftUI

struct ProjectsSidebar: View {
    @Environment(MockStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "PROJECTS") {
                HeaderCaption(text: "~/Documents")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.projects) { project in
                        ProjectRow(
                            project: project,
                            isSelected: store.selectedProjectID == project.id,
                            sessionCount: store.agentCount(for: project.id)
                        ) {
                            withAnimation(.smooth(duration: 0.3)) {
                                store.select(project: project.id)
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
        }
        .glassPanel()
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
    let onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Circle()
                    .fill(sessionCount > 0 ? DaddyTheme.working : DaddyTheme.textVeryDim)
                    .frame(width: 6, height: 6)

                Text(project.name)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? DaddyTheme.textPrimary : DaddyTheme.textSecondary)

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
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
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
