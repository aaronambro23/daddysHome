import AppKit
import SwiftTerm

/// A `TerminalView` you can drop files onto.
///
/// ## Why this has to exist here
///
/// Dropping an image onto a terminal and having its path appear at the cursor
/// is not a feature of Claude, Cursor, Codex or OpenCode. It is a feature of
/// the *terminal emulator*: Terminal.app and iTerm2 accept the drag, insert the
/// escaped path as if you had typed it, and the CLI on the other end simply
/// reads a path like any other text. SwiftTerm implements no part of
/// `NSDraggingDestination` — it never calls `registerForDraggedTypes` — so
/// inside Daddy there was nothing in the view hierarchy willing to accept a
/// drag, and every drop was rejected.
///
/// This adds the missing half. What to *do* with the paths is the coordinator's
/// business; this view only accepts the drag and reports it.
final class DroppableTerminalView: TerminalView {
    /// Called on the main thread with one or more file URLs.
    var onDropFiles: (([URL]) -> Void)?

    private var isReceivingDrag = false {
        didSet {
            guard isReceivingDrag != oldValue else { return }
            layer?.borderWidth = isReceivingDrag ? 2 : 0
            layer?.borderColor = isReceivingDrag ? Self.dropHighlight : nil
        }
    }

    /// `DaddyTheme.accent` (#b3dcff) as AppKit sees it.
    private static let dropHighlight = NSColor(
        srgbRed: 0xb3 / 255, green: 0xdc / 255, blue: 0xff / 255, alpha: 0.9
    ).cgColor

    private static let readOptions: [NSPasteboard.ReadingOptionKey: Any] = [
        .urlReadingFileURLsOnly: true
    ]

    override init(frame: CGRect, font: NSFont?) {
        super.init(frame: frame, font: font)
        registerForDraggedTypes([.fileURL, .tiff, .png])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL, .tiff, .png])
    }

    /// Cursor (and the other TUIs) enable mouse reporting, and SwiftTerm's
    /// `mouseDown` then sends the click to the child and returns without
    /// becoming first responder. After the board steals focus, a click that
    /// never focuses is a session you cannot type into.
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    // MARK: NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !urls(from: sender).isEmpty else { return [] }
        isReceivingDrag = true
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        isReceivingDrag ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isReceivingDrag = false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        isReceivingDrag = false
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !urls(from: sender).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isReceivingDrag = false

        let dropped = urls(from: sender)
        guard !dropped.isEmpty else { return false }

        // The caret belongs in the terminal after a drop — you dropped the file
        // in order to type the rest of the sentence.
        window?.makeFirstResponder(self)
        onDropFiles?(dropped)
        return true
    }

    // MARK: Reading the drag

    /// File URLs on the pasteboard, or — for a drag that carries only image
    /// data — a temporary file written for it.
    ///
    /// The second case is what dragging a picture out of a browser or a Preview
    /// window gives you: no file exists on disk, so there is no path to insert
    /// until we make one. Finder drags and screenshot thumbnails take the first
    /// path and touch nothing.
    private func urls(from sender: NSDraggingInfo) -> [URL] {
        let pasteboard = sender.draggingPasteboard

        if let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: Self.readOptions
        ) as? [URL], !objects.isEmpty {
            return objects
        }

        if let image = NSImage(pasteboard: pasteboard),
           let file = Self.writeTemporaryPNG(image) {
            return [file]
        }

        return []
    }

    private static func writeTemporaryPNG(_ image: NSImage) -> URL? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return nil }

        // Built per drop rather than shared: a drop is a human action, so the
        // cost is irrelevant, and a shared formatter is mutable global state.
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("daddy-drop-\(stamp.string(from: Date())).png")

        do {
            try png.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
