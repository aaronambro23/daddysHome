import SwiftUI

/// Several work items sent together in one multi-task dispatch, drawn as one
/// card. The items themselves stay independent — this is only how the board
/// groups them; each row opens the same `BoardDetailPane` a lone card would.
///
/// Distinct from `BoardCard` on purpose: a gradient header and a stacked-cards
/// glyph mark it as "several things", not another flavor of the plain card.
struct BoardBundleCard: View {
    let bundleID: UUID
    let items: [OrchestratorWorkItem]
    let isCollapsed: Bool
    let selectedID: UUID?
    let showsCategory: Bool
    let projectName: (OrchestratorWorkItem) -> String?
    let onToggleCollapsed: () -> Void
    let onSelectItem: (OrchestratorWorkItem) -> Void
    /// Opens the bundle-level summary pane — the only way to see the whole
    /// bundle at once or unbundle it, since the card itself has no fields.
    let onOpenDetail: () -> Void

    @State private var hoveringHeader = false

    private var tints: [Color] { Array(Set(items.map(\.category.tint))).prefix(4).map { $0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !isCollapsed {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(items) { item in
                        row(item)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.055))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: tints.isEmpty ? [DaddyTheme.accent] : tints,
                        startPoint: .leading,
                        endPoint: .trailing
                    ).opacity(0.55),
                    lineWidth: 1
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(headerTint)

            Text("\(items.count) TASKS BUNDLED")
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(DaddyTheme.textSecondary)

            Spacer(minLength: 0)

            HStack(spacing: 2) {
                ForEach(Array(tints.enumerated()), id: \.offset) { _, tint in
                    Circle().fill(tint).frame(width: 5, height: 5)
                }
            }

            Button(action: onOpenDetail) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(headerTint)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Bundle details — see every task, or unbundle")

            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(DaddyTheme.textMuted)
                .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                .animation(.easeOut(duration: 0.12), value: isCollapsed)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background {
            LinearGradient(
                colors: (tints.isEmpty ? [DaddyTheme.accent] : tints).map { $0.opacity(hoveringHeader ? 0.22 : 0.14) },
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggleCollapsed)
        .onHover { hoveringHeader = $0 }
    }

    private var headerTint: Color { tints.first ?? DaddyTheme.accent }

    // MARK: - Rows

    private func row(_ item: OrchestratorWorkItem) -> some View {
        BundleRow(
            item: item,
            isSelected: selectedID == item.id,
            projectName: projectName(item),
            onSelect: { onSelectItem(item) }
        )
    }
}

/// One clickable line inside a bundle card — a compact echo of `BoardCard`'s
/// content, not its own drag/context-menu surface. Archiving or deleting a
/// sub-task happens from its own detail pane, opened by tapping the row.
private struct BundleRow: View {
    let item: OrchestratorWorkItem
    let isSelected: Bool
    let projectName: String?
    let onSelect: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Circle()
                    .fill(item.category.tint)
                    .frame(width: 5, height: 5)

                Text(item.title.isEmpty ? "Untitled" : item.title)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(DaddyTheme.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let projectName {
                    Text(projectName)
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(DaddyTheme.textVeryDim)
                        .lineLimit(1)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(DaddyTheme.textVeryDim)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.10 : (hovering ? 0.06 : 0)))
        }
        .onHover { hovering = $0 }
    }
}
