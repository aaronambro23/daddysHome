import SwiftUI
import DaddyCore

/// Your terminals, beside the agent's.
///
/// Not agents, not sessions, nothing supervising them: plain login shells in the
/// selected project, for the half of the work that was never the agent's —
/// running the app locally, `cd`-ing somewhere, reading `git status`, committing
/// and pushing. All of that used to mean leaving Daddy for Terminal.app and
/// losing sight of every agent on the way.
///
/// It reuses `TerminalSurface` untouched, which is the whole reason this is
/// small: that view takes a bare `PTYProcess`, not a session and not an agent,
/// so a shell is the same renderer pointed at a different process.
///
/// ## Every tab stays mounted
///
/// The obvious implementation renders one `TerminalSurface` and points it at
/// whichever pty is selected. That path goes through
/// `TerminalSurface.Coordinator.rebindIfNeeded`, which resets the emulator and
/// replays `PTYProcess.recentOutput` — capped at 200 lines — so returning to a
/// tab would silently eat its scrollback. Instead every tab has its own surface,
/// all of them alive, and switching tabs only changes which one is on top. Same
/// rule `FleetView` follows for the agent pane, for the same reason.
struct ShellPane: View {
    @Environment(MockStore.self) private var store

    /// The project whose shells this shows. Nil before anything is selected.
    let project: MockProject?

    @State private var branch: String?
    @State private var branchPoll: Task<Void, Never>?
    @State private var hoveredTabID: String?
    @State private var plusHovering = false

    private var tabs: [ShellTab] {
        project.map { store.shellTabs(for: $0.id) } ?? []
    }

    private var activeTab: ShellTab? {
        project.flatMap { store.activeShellTab(for: $0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabStrip
            GlassHairline()
            terminals
        }
        .background(DaddyTheme.terminalSurface)
        .clipShape(
            RoundedRectangle(cornerRadius: DaddyTheme.focusedPaneRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DaddyTheme.focusedPaneRadius, style: .continuous)
                .strokeBorder(DaddyTheme.insetStroke, lineWidth: 1)
        }
        .onAppear { start() }
        .onDisappear { branchPoll?.cancel() }
        .onChange(of: project?.id) { _, _ in start() }
    }

    // MARK: Tabs

    /// Tabs scroll; the `+` does not. It is the one control you reach for
    /// blind, so it stays in the corner however many shells are open.
    private var tabStrip: some View {
        HStack(spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(tabs) { tab in
                            tabButton(tab).id(tab.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                }
                .onChange(of: activeTab?.id) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }

            newTabButton
                .padding(.trailing, 8)
        }
        .frame(height: 38)
    }

    private func tabButton(_ tab: ShellTab) -> some View {
        let isActive = activeTab?.id == tab.id
        let isHovering = hoveredTabID == tab.id

        return HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(isActive ? DaddyTheme.textMuted : DaddyTheme.textVeryDim)

            Text(title(for: tab))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isActive ? DaddyTheme.textSecondary : DaddyTheme.textMuted)
                .lineLimit(1)
                .fixedSize()

            // Only on the tab you are looking at. The branch is a property of
            // the project, not of one shell, so repeating it on every tab would
            // spend the whole strip saying the same word.
            if isActive, let branch {
                Text(branch)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(DaddyTheme.textMuted)
                    .lineLimit(1)
                    .fixedSize()
            }

            // Closing the only shell would leave an empty panel, so there is
            // nothing to close until there are two.
            if tabs.count > 1 {
                Button { store.closeShellTab(tab) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(
                            isHovering ? DaddyTheme.textSecondary : DaddyTheme.textVeryDim
                        )
                        .frame(width: 14, height: 14)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close this shell")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .insetSurface(cornerRadius: 13, selected: isActive, filled: isHovering)
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .onTapGesture { store.selectShellTab(tab) }
        .onHover { hoveredTabID = $0 ? tab.id : (hoveredTabID == tab.id ? nil : hoveredTabID) }
        .animation(.easeOut(duration: 0.14), value: isHovering)
    }

    private var newTabButton: some View {
        Button { if let project { store.openShellTab(for: project) } } label: {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(plusHovering ? DaddyTheme.textPrimary : DaddyTheme.textMuted)
                .frame(width: 22, height: 22)
                .background { Circle().fill(Color.white.opacity(plusHovering ? 0.14 : 0.06)) }
                .overlay { Circle().strokeBorder(DaddyTheme.insetStroke, lineWidth: 1) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(project == nil)
        .onHover { plusHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: plusHovering)
        .help("New shell in this project")
    }

    /// `daddy`, `daddy 2`, `daddy 3` — the project name, then the shell's own
    /// number once there is more than one to tell apart.
    private func title(for tab: ShellTab) -> String {
        let name = project?.name ?? "shell"
        return tab.ordinal == 1 ? name : "\(name) \(tab.ordinal)"
    }

    // MARK: Terminals

    @ViewBuilder
    private var terminals: some View {
        if project == nil {
            placeholder("No project selected")
        } else if tabs.isEmpty {
            placeholder("Starting shell…")
        } else {
            ZStack {
                ForEach(tabs) { tab in
                    if let pty = store.shell(for: tab), pty.isProcessRunning {
                        let isActive = activeTab?.id == tab.id

                        TerminalSurface(
                            pty: pty,
                            isActive: isActive,
                            // The one place that sends Ctrl-L to fix a prompt
                            // printed before the pane's real width was known.
                            redrawsOnFirstAttach: true
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        // Hidden, not unmounted — see the type's doc comment.
                        // The frame stays real so no background shell is ever
                        // handed a 0-column TIOCSWINSZ.
                        .opacity(isActive ? 1 : 0)
                        .allowsHitTesting(isActive)
                        .zIndex(isActive ? 1 : 0)
                    }
                }
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(DaddyTheme.textMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Lifecycle

    /// Launching happens here rather than in `body` on purpose: spawning a
    /// process during layout is what crashed the launch menu.
    private func start() {
        branch = nil
        branchPoll?.cancel()

        guard let project else { return }
        store.ensureShell(for: project)

        // Polled, not watched. A branch changes when a human changes it, so
        // five seconds is far more often than necessary, and the alternative is
        // a `git` process per frame.
        let path = (project.path as NSString).expandingTildeInPath
        branchPoll = Task {
            while !Task.isCancelled {
                let name = await Self.currentBranch(at: path)
                if Task.isCancelled { return }
                branch = name
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private static func currentBranch(at path: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = ["-C", path, "rev-parse", "--abbrev-ref", "HEAD"]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                guard process.terminationStatus == 0,
                      let text = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty
                else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: text)
            }
        }
    }
}
