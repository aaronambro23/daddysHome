import SwiftUI

/// One work item on the board.
///
/// Dragging is a plain `DragGesture` reported up to `BoardView`, not the
/// system drag-and-drop APIs — see `BoardDrag.swift` for why. Selection is a
/// `simultaneousGesture` so it cannot claim the mouse-down ahead of the drag,
/// and the drag has a `minimumDistance` so a click that does not move still
/// reads as a click.
struct BoardCard: View {
    let item: OrchestratorWorkItem
    let isSelected: Bool
    /// Dimmed while it is the card in hand, because the thing following the
    /// cursor is standing in for it.
    let isDragging: Bool
    /// False when the card already sits under a category group header, where
    /// repeating the category on every card is noise.
    let showsCategory: Bool
    /// Only supplied in the all-projects scope, where a card is ambiguous
    /// without it. Within one project it would be the same word on every card.
    let projectName: String?
    let onSelect: () -> Void
    let onDragChanged: (CGPoint) -> Void
    let onDragEnded: (CGPoint) -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void
    let onSendToOrchestrator: () -> Void

    @State private var hovering = false

    var body: some View {
        visual
            .opacity(isDragging ? 0.3 : 1)
            .contentShape(Rectangle())
            // One gesture, not two.
            //
            // A `TapGesture` alongside a `DragGesture` cannot resolve until
            // SwiftUI knows the drag is not happening, so selecting a card
            // lagged noticeably. This decides for itself: past the threshold
            // it is a drag, otherwise it was a click, and either way it
            // resolves the instant the mouse comes up.
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(BoardSpace.name))
                    .onChanged { value in
                        guard Self.isDrag(value.translation) else { return }
                        onDragChanged(value.location)
                    }
                    .onEnded { value in
                        if Self.isDrag(value.translation) {
                            onDragEnded(value.location)
                        } else {
                            onSelect()
                        }
                    }
            )
            .onHover { hovering = $0 }
            .contextMenu {
                Button("Send to Orchestrator", action: onSendToOrchestrator)
                Divider()
                if item.status != .archived {
                    Button("Archive", action: onArchive)
                }
                Button("Delete", role: .destructive, action: onDelete)
            }
    }

    // MARK: - Appearance

    private var visual: some View {
        HStack(spacing: 0) {
            // The category, as colour rather than as another line of text.
            // Reading a column is then a matter of scanning one edge.
            Rectangle()
                .fill(item.category.tint)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 6) {
                if showsCategory || urgencyTint != nil {
                    HStack(spacing: 5) {
                        if showsCategory {
                            Text(item.category.boardTitle)
                                .font(.system(size: 8.5, weight: .bold))
                                .tracking(0.5)
                                .foregroundStyle(item.category.tint)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        // Only the two priorities that change what you do
                        // next. A dot on every card is noise; a dot on the two
                        // that jumped the queue explains why they are on top.
                        if let urgencyTint {
                            Circle()
                                .fill(urgencyTint)
                                .frame(width: 5, height: 5)
                        }
                    }
                }

                Text(item.title)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(DaddyTheme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    if let projectName {
                        Text(projectName)
                            .lineLimit(1)
                        Text("·")
                    }
                    Text(Self.age(item.updatedAt))
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(DaddyTheme.textVeryDim)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .insetSurface(cornerRadius: 10, selected: isSelected || hovering)
    }

    /// Far enough to mean it. Below this the pointer only wobbled and the
    /// gesture was a click.
    private static func isDrag(_ translation: CGSize) -> Bool {
        hypot(translation.width, translation.height) > 4
    }

    private var urgencyTint: Color? {
        switch item.priority {
        case .urgent: return DaddyTheme.failure
        case .high: return DaddyTheme.working
        case .medium, .low: return nil
        }
    }

    /// Compact enough to sit in a narrow column: "3h", "2d", "5w".
    static func age(_ date: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(date))
        switch seconds {
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86_400: return "\(Int(seconds / 3600))h"
        case ..<604_800: return "\(Int(seconds / 86_400))d"
        default: return "\(Int(seconds / 604_800))w"
        }
    }
}
