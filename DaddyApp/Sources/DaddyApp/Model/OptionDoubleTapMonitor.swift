import AppKit

/// Detects a system-wide double-tap of the Option key, independent of which
/// app is frontmost. Option edges are found by polling the global
/// `NSEvent.modifierFlags` on a 50ms timer — plain global state, no event
/// monitor, no Input Monitoring permission, no code-signature sensitivity.
/// Passive observation only: it never swallows the event, so whatever app is
/// frontmost still sees it too. Accepted trade-off: it needs no
/// Accessibility permission, but a keystroke used to cancel a recording
/// (Esc) still reaches the frontmost app as well — and Esc itself still
/// relies on a best-effort global `.keyDown` monitor, which delivers only
/// when the app has Input Monitoring approval.
@MainActor
final class OptionDoubleTapMonitor {
    private static let doubleTapWindow: TimeInterval = 0.4
    private static let pollInterval: TimeInterval = 0.05
    private static let escapeKeyCode: UInt16 = 53

    private var pollTimer: Timer?
    private var keyMonitor: Any?
    private var lastOptionDownAt: Date?
    private var optionCurrentlyDown = false

    /// While the caller is recording, the next Option tap means "stop" and
    /// Esc means "cancel," instead of watching for a second tap to start.
    var isActive = false

    var onDoubleTap: (() -> Void)?
    var onSingleTapWhileActive: (() -> Void)?
    var onEscape: (() -> Void)?

    func start() {
        if pollTimer == nil {
            pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
                // The timer fires on the main runloop, and this class is
                // `@MainActor`, so this hop keeps everything downstream
                // (eventually TCC mic/speech permission) on the right queue.
                DispatchQueue.main.async { self?.pollOptionFlag() }
            }
        }
        guard keyMonitor == nil else { return }
        // Esc-cancel stays on the pre-existing global monitor, best-effort:
        // without Input Monitoring approval it silently never fires, and
        // recording still stops via tap. Unchanged behaviour, kept as-is.
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            DispatchQueue.main.async { self?.handleKeyDown(event) }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func pollOptionFlag() {
        let isOptionDown = NSEvent.modifierFlags.contains(.option)
        guard isOptionDown != optionCurrentlyDown else { return }
        optionCurrentlyDown = isOptionDown
        guard isOptionDown else { return } // only act on the key-down edge

        if isActive {
            onSingleTapWhileActive?()
            return
        }

        let now = Date()
        if let lastOptionDownAt, now.timeIntervalSince(lastOptionDownAt) <= Self.doubleTapWindow {
            self.lastOptionDownAt = nil
            onDoubleTap?()
        } else {
            lastOptionDownAt = now
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard isActive, event.keyCode == Self.escapeKeyCode else { return }
        onEscape?()
    }
}
