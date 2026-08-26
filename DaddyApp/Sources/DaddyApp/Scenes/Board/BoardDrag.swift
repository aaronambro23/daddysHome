import SwiftUI

/// The board's own drag, done with a plain `DragGesture` and geometry.
///
/// Four attempts at the system drag-and-drop APIs failed here — `.draggable`
/// with a `Button`, without one, stripped to a bare view, and the AppKit
/// `onDrag`/`onDrop` pair — across `ScrollView`, `LazyVStack` and `List`. So
/// the board stopped asking AppKit to move cards and does it itself.
///
/// This works because on macOS a `ScrollView` is driven by scroll *events*,
/// not by drag gestures, so a `DragGesture` on a card competes with nothing.
/// The cost is that cards cannot be dragged out of the app, which they were
/// never meant to be.
enum BoardSpace {
    /// One coordinate space shared by the cards and the columns, so a point
    /// from a gesture and a column's frame are directly comparable.
    static let name = "daddy.board"
}

/// Where each column landed, in board coordinates.
struct BoardColumnFrameKey: PreferenceKey {
    static let defaultValue: [OrchestratorWorkStatus: CGRect] = [:]

    static func reduce(
        value: inout [OrchestratorWorkStatus: CGRect],
        nextValue: () -> [OrchestratorWorkStatus: CGRect]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// The card currently in hand.
struct BoardDragState {
    let id: UUID
    let title: String
    let tint: Color
    var location: CGPoint
}
