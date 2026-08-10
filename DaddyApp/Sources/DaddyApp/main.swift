import Cocoa
import DaddyCore

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Daddy — Command Center"
        window.isReleasedWhenClosed = false

        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        let label = NSTextField(
            frame: NSRect(x: 20, y: window.frame.height - 60, width: 400, height: 30)
        )
        label.stringValue = "Daddy Command Center v0.1"
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = NSColor.clear
        contentView.addSubview(label)

        let statusLabel = NSTextField(
            frame: NSRect(x: 20, y: window.frame.height - 100, width: 400, height: 80)
        )
        statusLabel.stringValue = """
        SessionManager initialized
        Ready for voice commands via HEX

        Supported agents: Claude, Codex, Cursor, OpenCode
        """
        statusLabel.isEditable = false
        statusLabel.isBordered = false
        statusLabel.backgroundColor = NSColor.clear
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        contentView.addSubview(statusLabel)

        let button = NSButton(frame: NSRect(x: 20, y: 20, width: 150, height: 30))
        button.title = "Open Project"
        button.target = self
        button.action = #selector(openProjectButtonClicked)
        contentView.addSubview(button)

        window.contentView = contentView
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    @objc func openProjectButtonClicked() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a project directory to control with Daddy"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            self.openProject(at: url)
        }
    }

    func openProject(at url: URL) {
        let manager = SessionManager()

        do {
            let session = try manager.createSession(
                projectID: url.lastPathComponent,
                workUnitID: "default",
                agent: .claude,
                cwd: url
            )

            if let window = self.window {
                let messageBox = NSAlert()
                messageBox.messageText = "Project Opened"
                messageBox.informativeText = """
                Project: \(url.lastPathComponent)
                Session: \(session.id)
                Agent: Claude
                State: Ready

                Daddy will coordinate agent CLIs for this project.
                """
                messageBox.runModal()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Error"
            alert.informativeText = "Failed to open project: \(error.localizedDescription)"
            alert.runModal()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
