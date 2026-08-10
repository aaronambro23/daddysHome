import Cocoa
import DaddyCore
import SwiftTerm

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var sessionManager: SessionManager?
    var terminalView: LocalProcessTerminalView?
    var statusItem: NSStatusItem?
    var statusMenu: NSMenu?
    var statusUpdateTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        sessionManager = SessionManager()
        setupMenuBar()
        setupMainWindow()
        startStatusUpdates()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusMenu = NSMenu()
        statusItem?.menu = statusMenu
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let statusItem = statusItem, let sessionManager = sessionManager, let menu = statusMenu else { return }

        let sessions = sessionManager.getActiveSessions()
        let activeSessions = sessions.count
        let rateLimited = sessions.filter { $0.state == .rateLimited }.count

        if activeSessions == 0 {
            statusItem.button?.title = "◇"
        } else if rateLimited > 0 {
            statusItem.button?.title = "⚠ \(activeSessions)"
        } else {
            statusItem.button?.title = "● \(activeSessions)"
        }

        menu.removeAllItems()
        let headerItem = NSMenuItem(title: "Active Sessions: \(activeSessions)", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        if activeSessions > 0 {
            menu.addItem(NSMenuItem.separator())
            for session in sessions {
                let stateEmoji = stateEmoji(session.state)
                let title = "\(stateEmoji) \(session.agent.rawValue) • \(session.projectID)"
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let showWindowItem = NSMenuItem(
            title: "Show Window",
            action: #selector(showWindowClicked),
            keyEquivalent: ""
        )
        showWindowItem.target = self
        menu.addItem(showWindowItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit Daddy",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
    }

    private func stateEmoji(_ state: AgentState) -> String {
        switch state {
        case .launching:
            return "⚙️"
        case .ready:
            return "✓"
        case .working:
            return "▶"
        case .rateLimited:
            return "⏸"
        case .error:
            return "✗"
        case .exited:
            return "⊗"
        }
    }

    private func startStatusUpdates() {
        statusUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatusItem()
            }
        }
    }

    @objc func showWindowClicked() {
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func setupMainWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Daddy — Command Center"
        window.isReleasedWhenClosed = false

        let splitView = NSSplitView(frame: window.contentView!.bounds)
        splitView.isVertical = false

        let topPanel = NSView(frame: NSRect(x: 0, y: 500, width: 1000, height: 200))
        topPanel.wantsLayer = true
        topPanel.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        let titleLabel = NSTextField(
            frame: NSRect(x: 20, y: 170, width: 400, height: 20)
        )
        titleLabel.stringValue = "Daddy — macOS AI Coding Control Plane v0.1"
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.backgroundColor = NSColor.clear
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        topPanel.addSubview(titleLabel)

        let statusLabel = NSTextField(
            frame: NSRect(x: 20, y: 60, width: 500, height: 100)
        )
        statusLabel.stringValue = """
        Status: Ready

        SessionManager initialized
        Ready for voice commands via HEX

        Supported agents: Claude, Codex, Cursor, OpenCode
        """
        statusLabel.isEditable = false
        statusLabel.isBordered = false
        statusLabel.backgroundColor = NSColor.clear
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        topPanel.addSubview(statusLabel)

        let button = NSButton(frame: NSRect(x: 20, y: 20, width: 150, height: 30))
        button.title = "Launch Claude"
        button.target = self
        button.action = #selector(launchClaudeButtonClicked)
        topPanel.addSubview(button)

        let button2 = NSButton(frame: NSRect(x: 180, y: 20, width: 150, height: 30))
        button2.title = "Open Project..."
        button2.target = self
        button2.action = #selector(openProjectButtonClicked)
        topPanel.addSubview(button2)

        splitView.addArrangedSubview(topPanel)

        let terminalPanel = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 500))
        terminalPanel.wantsLayer = true
        terminalPanel.layer?.backgroundColor = NSColor.black.cgColor

        let terminalView = LocalProcessTerminalView(frame: terminalPanel.bounds)
        terminalView.autoresizingMask = [.width, .height]
        terminalPanel.addSubview(terminalView)
        self.terminalView = terminalView

        splitView.addArrangedSubview(terminalPanel)

        window.contentView = splitView
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    @objc func launchClaudeButtonClicked() {
        guard let sessionManager = sessionManager else { return }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("daddy-test")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        do {
            let session = try sessionManager.createSession(
                projectID: "test",
                workUnitID: "default",
                agent: .claude,
                cwd: tempDir
            )

            try sessionManager.launchSession(session)

            let alert = NSAlert()
            alert.messageText = "Claude Session Launched"
            alert.informativeText = """
            Session ID: \(session.id)
            Agent: Claude
            Directory: \(tempDir.path)
            Status: Ready
            """
            alert.runModal()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Error"
            alert.informativeText = "Failed to launch Claude: \(error.localizedDescription)"
            alert.runModal()
        }
    }

    @objc func openProjectButtonClicked() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a project directory"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            self.openProject(at: url)
        }
    }

    func openProject(at url: URL) {
        guard let sessionManager = sessionManager else { return }

        do {
            let session = try sessionManager.createSession(
                projectID: url.lastPathComponent,
                workUnitID: "default",
                agent: .claude,
                cwd: url
            )

            let alert = NSAlert()
            alert.messageText = "Project Opened"
            alert.informativeText = """
            Project: \(url.lastPathComponent)
            Session: \(session.id)
            Agent: Claude
            State: Ready

            Ready to coordinate agent CLIs for this project.
            """
            alert.runModal()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Error"
            alert.informativeText = "Failed to open project: \(error.localizedDescription)"
            alert.runModal()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
