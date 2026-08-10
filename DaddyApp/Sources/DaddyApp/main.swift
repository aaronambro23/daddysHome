import Cocoa
import DaddyCore
import SwiftTerm
import UserNotifications

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var sessionManager: SessionManager?
    var terminalView: LocalProcessTerminalView?
    var statusItem: NSStatusItem?
    var statusMenu: NSMenu?
    var statusUpdateTimer: Timer?
    var projectsUpdateTimer: Timer?
    var lastNotifiedStates: [String: AgentState] = [:]
    var hexWatcher: HEXWatcher?
    var commandParser = CommandParser()

    var projectsViewController: ProjectsViewController?
    var dashboardViewController: DashboardViewController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        sessionManager = SessionManager()
        requestNotificationPermissions()
        setupMenuBar()
        setupMainWindow()
        startStatusUpdates()
        setupHEXIntegration()
    }

    private func setupHEXIntegration() {
        hexWatcher = HEXWatcher()
        if hexWatcher != nil {
            print("✓ HEX integration active (listening for voice commands)")
            hexWatcher?.onNewTranscription = { [weak self] transcript in
                self?.handleVoiceTranscript(transcript)
            }
        } else {
            print("⚠ HEX not available (file not found)")
        }
    }

    private func handleVoiceTranscript(_ transcript: String) {
        let command = commandParser.parse(transcript)

        guard let agent = command.agent else {
            print("No agent specified in: \(transcript)")
            return
        }

        guard let sessionManager = sessionManager else { return }

        let projectURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        do {
            let modelRef = command.model.flatMap { ModelRef(agent: agent, rawValue: $0) }
            let intentStr: String
            switch command.intent {
            case .work: intentStr = "work"
            case .stop: intentStr = "stop"
            case .resume: intentStr = "resume"
            case .interrupt: intentStr = "interrupt"
            case .review: intentStr = "review"
            case .handoff: intentStr = "handoff"
            case .status: intentStr = "status"
            case .runTests: intentStr = "run_tests"
            case .switchModel: intentStr = "switch_model"
            case .unknown(let val): intentStr = val
            }

            let session = try sessionManager.createSession(
                projectID: projectURL.lastPathComponent,
                workUnitID: intentStr,
                agent: agent,
                model: modelRef,
                cwd: projectURL
            )

            try sessionManager.launchSession(session)
            print("✓ Spawned \(agent.rawValue) for: \(intentStr)")

            if let prompt = command.prompt, !prompt.isEmpty {
                try sessionManager.sendPrompt(prompt, to: session.id)
            }
        } catch {
            print("✗ Error spawning agent: \(error)")
        }

        DispatchQueue.main.async {
            self.dashboardViewController?.refresh()
        }
    }

    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    NSApplication.shared.registerForRemoteNotifications()
                }
            }
        }
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

        checkAndNotifyStateChanges(sessions: sessions)

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

    private func checkAndNotifyStateChanges(sessions: [Session]) {
        for session in sessions {
            let lastState = lastNotifiedStates[session.id]

            if lastState == nil || lastState != session.state {
                notifyStateChange(session: session, oldState: lastState)
                lastNotifiedStates[session.id] = session.state
            }
        }

        for key in lastNotifiedStates.keys where !sessions.contains(where: { $0.id == key }) {
            lastNotifiedStates.removeValue(forKey: key)
        }
    }

    private func notifyStateChange(session: Session, oldState: AgentState?) {
        guard shouldNotify(state: session.state) else { return }

        let content = UNMutableNotificationContent()
        content.sound = .default

        switch session.state {
        case .rateLimited:
            content.title = "Rate Limited"
            content.body = "\(session.agent.rawValue) is rate-limited in \(session.projectID)"
        case .error(let msg):
            content.title = "Session Error"
            content.body = "\(session.agent.rawValue): \(msg)"
        case .exited:
            content.title = "Session Exited"
            content.body = "\(session.agent.rawValue) exited in \(session.projectID)"
        case .ready:
            if oldState == .launching {
                content.title = "Ready"
                content.body = "\(session.agent.rawValue) is ready in \(session.projectID)"
            }
        default:
            return
        }

        let request = UNNotificationRequest(identifier: session.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    private func shouldNotify(state: AgentState) -> Bool {
        switch state {
        case .rateLimited, .error, .exited, .ready:
            return true
        default:
            return false
        }
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
                self?.dashboardViewController?.refresh()
            }
        }

        projectsUpdateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.projectsViewController?.refreshProjects()
            }
        }
    }

    @objc func showWindowClicked() {
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func setupMainWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1400, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Daddy — AI Command Center"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)

        let containerView = NSView(frame: window.contentView!.bounds)
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1).cgColor

        let headerView = createHeaderView(width: window.frame.width)
        containerView.addSubview(headerView)

        let splitView = NSSplitView(frame: NSRect(
            x: 0, y: 0, width: window.frame.width, height: window.frame.height - 60
        ))
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        let projectsPanel = NSView()
        projectsPanel.wantsLayer = true
        projectsPanel.layer?.backgroundColor = NSColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1).cgColor

        projectsViewController = ProjectsViewController(sessionManager: sessionManager)
        if let controller = projectsViewController {
            projectsPanel.addSubview(controller.view)
            controller.view.frame = projectsPanel.bounds
            controller.view.autoresizingMask = [.width, .height]
        }
        splitView.addArrangedSubview(projectsPanel)

        let middlePanel = NSView()
        middlePanel.wantsLayer = true
        middlePanel.layer?.backgroundColor = NSColor(red: 0.06, green: 0.06, blue: 0.1, alpha: 1).cgColor

        dashboardViewController = DashboardViewController(sessionManager: sessionManager)
        if let controller = dashboardViewController {
            middlePanel.addSubview(controller.view)
            controller.view.frame = middlePanel.bounds
            controller.view.autoresizingMask = [.width, .height]
        }
        splitView.addArrangedSubview(middlePanel)

        let terminalPanel = NSView()
        terminalPanel.wantsLayer = true
        terminalPanel.layer?.backgroundColor = NSColor.black.cgColor

        let terminalView = LocalProcessTerminalView(frame: terminalPanel.bounds)
        terminalView.autoresizingMask = [.width, .height]
        terminalPanel.addSubview(terminalView)
        self.terminalView = terminalView

        splitView.addArrangedSubview(terminalPanel)

        splitView.frame = NSRect(
            x: 0, y: 0, width: window.frame.width, height: window.frame.height - 60
        )
        splitView.autoresizingMask = [.width, .height]
        containerView.addSubview(splitView)

        containerView.addSubview(headerView)
        window.contentView = containerView
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    private func createHeaderView(width: CGFloat) -> NSView {
        let header = NSView(frame: NSRect(x: 0, y: window!.frame.height - 60, width: width, height: 60))
        header.wantsLayer = true
        header.layer?.backgroundColor = NSColor(red: 0.02, green: 0.02, blue: 0.05, alpha: 1).cgColor

        let borderView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        borderView.wantsLayer = true
        borderView.layer?.backgroundColor = NSColor(red: 0.2, green: 0.3, blue: 0.9, alpha: 0.3).cgColor
        header.addSubview(borderView)

        let titleLabel = NSTextField(frame: NSRect(x: 20, y: 25, width: 300, height: 25))
        titleLabel.stringValue = "◆ DADDY — AI Command Center"
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.backgroundColor = NSColor.clear
        titleLabel.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        titleLabel.textColor = NSColor(red: 0.2, green: 0.8, blue: 1.0, alpha: 1)
        header.addSubview(titleLabel)

        let hexLabel = NSTextField(frame: NSRect(x: width - 200, y: 25, width: 180, height: 20))
        hexLabel.stringValue = "HEX: Ready (double-click option)"
        hexLabel.isEditable = false
        hexLabel.isBordered = false
        hexLabel.backgroundColor = NSColor.clear
        hexLabel.font = NSFont.systemFont(ofSize: 11)
        hexLabel.textColor = NSColor(red: 0.5, green: 1.0, blue: 0.5, alpha: 0.7)
        header.addSubview(hexLabel)

        return header
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

class ProjectsViewController: NSViewController {
    var sessionManager: SessionManager?
    var projects: [URL] = []
    var tableView: NSTableView?

    init(sessionManager: SessionManager?) {
        super.init(nibName: nil, bundle: nil)
        self.sessionManager = sessionManager
        loadProjects()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true

        let titleLabel = NSTextField(frame: NSRect(x: 15, y: container.frame.height - 40, width: 250, height: 25))
        titleLabel.stringValue = "📁 Active Projects"
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.backgroundColor = NSColor.clear
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = NSColor(red: 0.3, green: 0.9, blue: 0.8, alpha: 1)
        container.addSubview(titleLabel)

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 280, height: container.frame.height - 50))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        tableView = NSTableView(frame: scrollView.bounds)
        tableView?.delegate = self
        tableView?.dataSource = self
        tableView?.headerView = nil
        tableView?.backgroundColor = NSColor.clear

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.width = 260
        tableView?.addTableColumn(column)

        scrollView.documentView = tableView
        container.addSubview(scrollView)

        self.view = container
    }

    func loadProjects() {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        do {
            projects = try FileManager.default.contentsOfDirectory(
                at: documentsURL,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            ).filter { $0.hasDirectoryPath }
            tableView?.reloadData()
        } catch {
            print("Error loading projects: \(error)")
        }
    }

    func refreshProjects() {
        loadProjects()
    }
}

extension ProjectsViewController: NSTableViewDelegate, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return projects.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView()
        let textField = NSTextField(frame: NSRect(x: 10, y: 0, width: 250, height: 24))
        textField.stringValue = projects[row].lastPathComponent
        textField.isEditable = false
        textField.isBordered = false
        textField.backgroundColor = NSColor.clear
        textField.font = NSFont.systemFont(ofSize: 12)
        textField.textColor = NSColor(red: 0.7, green: 0.8, blue: 0.9, alpha: 1)
        cell.addSubview(textField)
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 28
    }
}

class DashboardViewController: NSViewController {
    var sessionManager: SessionManager?
    var scrollView: NSScrollView?

    init(sessionManager: SessionManager?) {
        super.init(nibName: nil, bundle: nil)
        self.sessionManager = sessionManager
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true

        let titleLabel = NSTextField(frame: NSRect(x: 20, y: container.frame.height - 40, width: 300, height: 25))
        titleLabel.stringValue = "⚡ Active Agents"
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.backgroundColor = NSColor.clear
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = NSColor(red: 0.2, green: 1.0, blue: 0.8, alpha: 1)
        container.addSubview(titleLabel)

        scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: container.frame.width, height: container.frame.height - 50))
        scrollView?.hasVerticalScroller = true
        scrollView?.autohidesScrollers = true
        container.addSubview(scrollView!)

        self.view = container
        refresh()
    }

    func refresh() {
        guard let scrollView = scrollView, let sessionManager = sessionManager else { return }

        let sessions = sessionManager.getActiveSessions()

        let contentView = NSView()
        contentView.wantsLayer = true

        var yOffset: CGFloat = CGFloat(sessions.count) * 120

        if sessions.isEmpty {
            let emptyLabel = NSTextField(frame: NSRect(x: 20, y: scrollView.frame.height / 2 - 30, width: 300, height: 60))
            emptyLabel.stringValue = "No active agents\n(speak to Daddy via HEX)"
            emptyLabel.isEditable = false
            emptyLabel.isBordered = false
            emptyLabel.backgroundColor = NSColor.clear
            emptyLabel.font = NSFont.systemFont(ofSize: 12)
            emptyLabel.textColor = NSColor(red: 0.4, green: 0.4, blue: 0.5, alpha: 0.6)
            emptyLabel.alignment = .center
            contentView.addSubview(emptyLabel)
        } else {
            for (index, session) in sessions.enumerated() {
                let card = createSessionCard(session: session, y: yOffset - CGFloat(index + 1) * 120)
                contentView.addSubview(card)
            }
        }

        contentView.frame = NSRect(x: 0, y: 0, width: scrollView.frame.width, height: yOffset)
        scrollView.documentView = contentView
    }

    private func createSessionCard(session: Session, y: CGFloat) -> NSView {
        let card = NSView(frame: NSRect(x: 15, y: y, width: 380, height: 110))
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(red: 0.12, green: 0.15, blue: 0.25, alpha: 0.8).cgColor
        card.layer?.borderColor = NSColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 0.4).cgColor
        card.layer?.borderWidth = 1
        card.layer?.cornerRadius = 8

        let agentLabel = NSTextField(frame: NSRect(x: 15, y: 85, width: 200, height: 18))
        agentLabel.stringValue = "▸ \(session.agent.rawValue.uppercased())"
        agentLabel.isEditable = false
        agentLabel.isBordered = false
        agentLabel.backgroundColor = NSColor.clear
        agentLabel.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        agentLabel.textColor = NSColor(red: 0.1, green: 1.0, blue: 0.6, alpha: 1)
        card.addSubview(agentLabel)

        let stateEmoji = stateEmojiForCard(session.state)
        let stateLabel = NSTextField(frame: NSRect(x: 320, y: 85, width: 50, height: 18))
        stateLabel.stringValue = stateEmoji
        stateLabel.isEditable = false
        stateLabel.isBordered = false
        stateLabel.backgroundColor = NSColor.clear
        stateLabel.font = NSFont.systemFont(ofSize: 14)
        card.addSubview(stateLabel)

        let projectLabel = NSTextField(frame: NSRect(x: 15, y: 65, width: 360, height: 16))
        projectLabel.stringValue = "📂 " + session.projectID
        projectLabel.isEditable = false
        projectLabel.isBordered = false
        projectLabel.backgroundColor = NSColor.clear
        projectLabel.font = NSFont.systemFont(ofSize: 11)
        projectLabel.textColor = NSColor(red: 0.6, green: 0.7, blue: 0.8, alpha: 0.8)
        card.addSubview(projectLabel)

        let modelLabel = NSTextField(frame: NSRect(x: 15, y: 45, width: 360, height: 14))
        let modelStr = session.model?.rawValue ?? "default"
        modelLabel.stringValue = "Model: \(modelStr)"
        modelLabel.isEditable = false
        modelLabel.isBordered = false
        modelLabel.backgroundColor = NSColor.clear
        modelLabel.font = NSFont.systemFont(ofSize: 10)
        modelLabel.textColor = NSColor(red: 0.5, green: 1.0, blue: 0.7, alpha: 0.7)
        card.addSubview(modelLabel)

        let workUnitLabel = NSTextField(frame: NSRect(x: 15, y: 25, width: 360, height: 14))
        workUnitLabel.stringValue = "Work: \(session.workUnitID)"
        workUnitLabel.isEditable = false
        workUnitLabel.isBordered = false
        workUnitLabel.backgroundColor = NSColor.clear
        workUnitLabel.font = NSFont.systemFont(ofSize: 10)
        workUnitLabel.textColor = NSColor(red: 0.8, green: 0.6, blue: 1.0, alpha: 0.7)
        card.addSubview(workUnitLabel)

        let timeLabel = NSTextField(frame: NSRect(x: 15, y: 8, width: 360, height: 12))
        let timeAgo = formatTimeAgo(session.lastOutputAt)
        timeLabel.stringValue = "Last: \(timeAgo)"
        timeLabel.isEditable = false
        timeLabel.isBordered = false
        timeLabel.backgroundColor = NSColor.clear
        timeLabel.font = NSFont.systemFont(ofSize: 9)
        timeLabel.textColor = NSColor(red: 0.5, green: 0.5, blue: 0.6, alpha: 0.6)
        card.addSubview(timeLabel)

        return card
    }

    private func stateEmojiForCard(_ state: AgentState) -> String {
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

    private func formatTimeAgo(_ date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 60 {
            return "now"
        } else if elapsed < 3600 {
            return "\(Int(elapsed / 60))m"
        } else if elapsed < 86400 {
            return "\(Int(elapsed / 3600))h"
        } else {
            return "\(Int(elapsed / 86400))d"
        }
    }
}
