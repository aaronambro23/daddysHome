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
                        if isRunning(agent) {
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
            if let pty = store.pty(for: agent), pty.isProcessRunning {
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

