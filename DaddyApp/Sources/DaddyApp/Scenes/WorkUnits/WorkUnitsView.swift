import SwiftUI

struct WorkUnitsView: View {
    @Environment(MockStore.self) private var store
    @State private var sidebarExpanded = true

    var body: some View {
        HStack(spacing: 16) {
            ProjectsSidebar(expanded: $sidebarExpanded)
                .frame(width: sidebarExpanded ? 264 : 60)

            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "WORK UNITS") {
                    HeaderCaption(text: "DaddyWork markdown history")
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(
                            [MockWorkUnit.Status.active, .idle, .done],
                            id: \.rawValue
                        ) { status in
                            let units = filtered(status)
                            if !units.isEmpty {
                                group(status, units)
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .glassPanel()
        }
    }

    private func filtered(_ status: MockWorkUnit.Status) -> [MockWorkUnit] {
        store.workUnits(for: store.selectedProjectID)
            .filter { $0.status == status }
            .sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    @ViewBuilder
    private func group(_ status: MockWorkUnit.Status, _ units: [MockWorkUnit]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color(status))
                    .frame(width: 5, height: 5)

                Text(status.rawValue)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(color(status))

                Text("\(units.count)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DaddyTheme.textMuted)
            }
            .padding(.leading, 4)

            ForEach(units) { unit in
                WorkUnitCard(unit: unit, accent: color(status))
            }
        }
    }

    private func color(_ status: MockWorkUnit.Status) -> Color {
        switch status {
        case .active: return DaddyTheme.working
        case .idle: return DaddyTheme.limited
        case .done: return DaddyTheme.idle
        }
    }
}

// MARK: - Card

struct WorkUnitCard: View {
    @Environment(MockStore.self) private var store

    let unit: MockWorkUnit
    let accent: Color

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(unit.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(
                        unit.status == .done ? DaddyTheme.textMuted : DaddyTheme.textPrimary
                    )
                    .strikethrough(unit.status == .done, color: DaddyTheme.textMuted)

                Text(unit.summary)
                    .font(.system(size: 10.5))
                    .foregroundStyle(DaddyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Text(unit.id)
                    Text("· \(store.project(unit.projectID)?.name ?? unit.projectID)")
                    Text("· \(formatTimeAgo(unit.lastActivityAt)) ago")
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(DaddyTheme.textMuted)
                .padding(.top, 2)
            }

            Spacer(minLength: 8)

            Button(unit.status == .done ? "Reopen" : "Mark done") {
                withAnimation(.smooth(duration: 0.32)) {
                    store.markDone(unit.id)
                }
            }
            .buttonStyle(.inset)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .insetSurface(cornerRadius: 18, filled: hovering)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}
