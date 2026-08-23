import SwiftUI
import DaddyCore

// A clear glass panel. No dark fill, no tint, no neon — the terminal reads as
// near-white monospace over whatever the backdrop is doing behind the glass.

struct TerminalPane: View {
    @Environment(MockStore.self) private var store
    var isFocused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "OUTPUT") {
                if let agent = store.selectedAgent {
                    HStack(spacing: 8) {
                        // Driven by whether the process is actually running.
                        // This used to key off `isRealSession`, which is true of
                        // every card now — so a dead agent still said LIVE.
                        if isLaunching(agent) {
                            HStack(spacing: 5) {
                                BreathingDot(color: DaddyTheme.launching, glowRadius: 6, size: 4)
                                Text("LAUNCHING")
                                    .font(.system(size: 8, weight: .bold))
                                    .tracking(0.8)
                                    .foregroundStyle(DaddyTheme.launching)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .insetCapsule(tint: DaddyTheme.launching, opacity: 0.12)
                        } else if isRunning(agent) {
                            HStack(spacing: 5) {
                                BreathingDot(color: DaddyTheme.working, glowRadius: 6, size: 4)
                                Text("LIVE")
                                    .font(.system(size: 8, weight: .bold))
                                    .tracking(0.8)
                                    .foregroundStyle(DaddyTheme.working)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .insetCapsule(tint: DaddyTheme.working, opacity: 0.12)
                        } else {
                            Text("ENDED")
                                .font(.system(size: 8, weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(DaddyTheme.textMuted)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .insetCapsule(opacity: 0.08)
                        }

                        HeaderCaption(text: "\(agent.agent.rawValue) · \(agent.workUnitID)")
                    }
                }
            }
            .frame(height: isFocused ? 0 : nil)
            .opacity(isFocused ? 0 : 1)
            .clipped()
            .allowsHitTesting(!isFocused)

            terminalBody

        }
        // Solid, docked and focused alike — no glass under a terminal.
        //
        // A terminal repaints on its own schedule, not the app's: an agent
        // rewriting a status footer dirties rows several times a second, and
        // every one of those repaints used to force the glass beneath to
        // re-blur an animating aurora. Clear glass costs nothing behind a
        // static panel and everything behind a live one. The rounded corner
        // and the panel's shape stay; only the material is gone.
        //
        // Rounded in focus mode too, since batch 014. It was square because it
        // ran to the window edges and had no corners to round; now it is one of
        // three cards floating with a gap between them, and the shell beside it
        // has been rounded all along.
        .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(DaddyTheme.terminalSurface))
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(DaddyTheme.insetStroke, lineWidth: 1)
        }
    }

    private var radius: CGFloat {
        isFocused ? DaddyTheme.focusedPaneRadius : 26
    }

    @ViewBuilder
    private var terminalBody: some View {
        if let agent = store.selectedAgent {
            if isLaunching(agent) {
                // A CLI that has not printed yet has nothing to show, and an
                // empty black rectangle reads as a session that failed. Cursor
                // in particular can take several seconds to come up.
                LaunchingState(agent: agent)
            } else if let pty = store.pty(for: agent), pty.isProcessRunning {
                // Real pty: SwiftTerm renders it, including colour and any
                // interactive prompts the agent draws.
                TerminalSurface(pty: pty, fontSize: store.terminalFontSize)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            } else {
                // A pty that has exited is *not* shown as a terminal. The
                // emulator keeps painting the last frame and a blinking
                // caret, so a dead session looked alive and half-drawn.
                endedState(pty: store.pty(for: agent))
            }
        } else if store.agents.isEmpty {
            emptyState(
                "No agents running",
                detail: "Pick a project in the sidebar and launch one."
            )
        } else {
            emptyState("Select an agent to view its output", detail: nil)
        }
    }

    private func isRunning(_ agent: MockAgent) -> Bool {
        store.pty(for: agent)?.isProcessRunning ?? false
    }

    /// The window between forkpty returning and the CLI's first byte.
    /// `MockStore` holds a session in `.launching` until it has spoken.
    private func isLaunching(_ agent: MockAgent) -> Bool {
        if case .launching = agent.state { return true }
        return false
    }

    /// What a finished session looks like.
    ///
    /// The last output is kept, as plain selectable text rather than a live
    /// terminal — agents often say something useful on the way out (OpenCode
    /// prints the command to resume that exact session), and throwing it away
    /// would lose it. Escape sequences are stripped, so what is left is what a
    /// person would have read.
    @ViewBuilder
    private func endedState(pty: PTYProcess?) -> some View {
        let tail = pty.map { OutputHeuristics.recentWindow($0.recentOutput, lines: 14) } ?? ""

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "stop.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(DaddyTheme.textMuted)

                Text(exitDescription(pty))
                    .font(.system(size: 11))
                    .foregroundStyle(DaddyTheme.textSecondary)
            }

            if !tail.isEmpty {
                ScrollView {
                    Text(tail)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(DaddyTheme.textMuted)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
            }

            Text("Resume chat on the card reopens this conversation.")
                .font(.system(size: 10))
                .foregroundStyle(DaddyTheme.textVeryDim)

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func exitDescription(_ pty: PTYProcess?) -> String {
        guard let code = pty?.exitCode else { return "Session ended" }
        return code == 0 ? "Session ended cleanly" : "Session ended (exit \(code))"
    }

    @ViewBuilder
    private func emptyState(_ title: String, detail: String?) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(DaddyTheme.textSecondary)
            if let detail {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(DaddyTheme.textMuted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

/// What a session looks like while its CLI is still booting.
private struct LaunchingState: View {
    let agent: MockAgent

    @State private var sweep = false
    @State private var halo = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)

            ZStack {
                // A ring that expands and fades out of the mark, over and over,
                // so the pane reads as waiting rather than stuck.
                Circle()
                    .strokeBorder(DaddyTheme.launching.opacity(0.5), lineWidth: 1)
                    .frame(width: halo ? 96 : 46, height: halo ? 96 : 46)
                    .opacity(halo ? 0 : 1)

                ProviderLogo.badge(for: agent.agent, diameter: 46)
            }
            .frame(width: 96, height: 96)

            VStack(spacing: 5) {
                Text("Starting \(agent.agent.rawValue)…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DaddyTheme.textSecondary)

                Text("waiting for its first output")
                    .font(.system(size: 10))
                    .foregroundStyle(DaddyTheme.textVeryDim)
            }

            // Indeterminate, because nothing here knows how long a CLI takes.
            Capsule()
                .fill(Color.white.opacity(0.05))
                .frame(width: 180, height: 2)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    DaddyTheme.launching.opacity(0.9),
                                    .clear,
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 64, height: 2)
                        .offset(x: sweep ? 180 : -64)
                }
                .clipShape(Capsule())

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                sweep = true
            }
            withAnimation(.easeOut(duration: 1.9).repeatForever(autoreverses: false)) {
                halo = true
            }
        }
    }
}
