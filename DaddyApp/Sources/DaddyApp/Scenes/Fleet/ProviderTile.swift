import SwiftUI
import DaddyCore

// Inside a glass panel — so this tile is NOT glass. It's an inset surface.

/// One provider's agents.
///
/// The size rule this exists to enforce: **no tile is ever bigger than another**.
/// Not a hardcoded frame — that would break on a different display — but a
/// content skeleton that does not vary. Nothing in here sizes off
/// `agents.count`: the deck's width is bounded by `AgentBubbleRow`, its height
/// is fixed by the bubble size, and the three lines below it are always three
/// lines. So one agent and fourteen agents produce the same tile. The previous
/// version squared each avatar cell inside the tile, which made a one-agent
/// group ~276pt tall and a five-agent group 120pt, and `LazyVGrid` then
/// stretched the neighbour to match.
///
/// Everything shown here is real. There is no placeholder metric: when a value
/// does not exist yet, its row is simply absent.
struct ProviderTile: View {
    @Environment(MockStore.self) private var store

    let kind: AgentKind
    let agents: [MockAgent]
    let onOpenProgress: (String) -> Void

    @State private var hovering = false

    /// The agent this tile is describing: the selected one when it belongs to
    /// this provider and still live, otherwise the newest live one, otherwise
    /// the first finished one. Never nil — the tile is not rendered for an
    /// empty provider.
    private var active: MockAgent? {
        agents.first { $0.id == store.selectedAgentID && $0.isLive }
            ?? agents.filter(\.isLive).max(by: { $0.lastOutputAt < $1.lastOutputAt })
            ?? agents.first
    }

    var body: some View {
        // The card's own tap target sits *behind* its contents, not wrapped
        // around them.
        //
        // Wrapping the card in `.onTapGesture` put the card and the `⋮` button
        // in competition for the same click, and SwiftUI does not resolve that
        // consistently — the same menu opened on one tile and fell through to
        // the card on another. Behind the content, the button is unambiguously
        // in front and always wins; the labels have no gesture of their own, so
        // clicks on empty card space fall through to the layer underneath.
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.001))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onTapGesture {
                    guard let active, active.isLive else { return }
                    withAnimation(.smooth(duration: 0.2)) {
                        store.openDetail(active.id)
                    }
                }

            VStack(alignment: .leading, spacing: 10) {
                header

                if let active {
                    AgentBubbleRow(
                        agents: agents,
                        activeID: active.id,
                        onSelect: { id in
                            guard agents.contains(where: { $0.id == id && $0.isLive }) else { return }
                            withAnimation(.smooth(duration: 0.2)) {
                                store.openDetail(id)
                            }
                        }
                    )

                    GlassHairline()

                    detail(for: active)
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 240, maxHeight: .infinity, alignment: .topLeading)
        .insetSurface(cornerRadius: 16, selected: isSelectedTile, filled: hovering)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private var isSelectedTile: Bool {
        active.map { $0.id == store.selectedAgentID } ?? false
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            // The provider's own mark, at title size. The tile below it is a
            // deck of bubbles carrying the same logo, so the grid can be read
            // by shape before any of the text is.
            ProviderLogo.mark(for: kind, diameter: 26)

            Text(kind.rawValue.capitalized)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(DaddyTheme.textPrimary)

            Text("(\(agents.count))")
                .font(.system(size: 10))
                .foregroundStyle(DaddyTheme.textSecondary)

            Spacer(minLength: 4)

            if let active {
                // Quick actions, always in the same place on every tile. The
                // hit area is deliberately larger than the glyph — a 10×14
                // icon is not a click target.
                GlassDropdown(items: menuItems(for: active), width: 210) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .bold))
                        .rotationEffect(.degrees(90))
                        .foregroundStyle(DaddyTheme.textSecondary)
                        .frame(width: 18, height: 20)
                        .contentShape(Rectangle())
                }
                .opacity(hovering ? 1 : 0.45)
            }
        }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    // MARK: The three truthful lines

    @ViewBuilder
    private func detail(for agent: MockAgent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                StatusBadge(state: agent.state)

                Text(agent.model)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(DaddyTheme.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(agent.uptime)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(DaddyTheme.textMuted)
            }

            ProviderUsageBattery(snapshot: store.providerUsage[kind], compact: true)

            secondLine(for: agent)

            HStack(spacing: 6) {
                Text(agent.workUnitID)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(DaddyTheme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 4)

                if agent.isLive {
                    Text("spoke \(formatTimeAgo(agent.lastOutputAt))")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(DaddyTheme.textMuted)
                }
            }
        }
    }

    /// What the agent is saying, or why it stopped. One line, always one line —
    /// a wrapping line here would make this tile taller than its neighbours.
    @ViewBuilder
    private func secondLine(for agent: MockAgent) -> some View {
        Group {
            if case .error(let message) = agent.state {
                label(message, color: DaddyTheme.failure)
            } else if case .exited(let code) = agent.state {
                label(
                    code == 0 ? "ended cleanly" : "ended · exit \(code)",
                    color: DaddyTheme.textMuted
                )
            } else if agent.agent != .opencode, !agent.lastLine.isEmpty {
                label("› " + agent.lastLine, color: DaddyTheme.textTertiary)
            } else if case .launching = agent.state {
                // A booting CLI says nothing for a few seconds. Saying so beats
                // a blank line that reads as "nothing is happening".
                HStack(spacing: 6) {
                    BreathingDot(color: DaddyTheme.launching, glowRadius: 6, size: 4)
                    Text("starting \(agent.agent.rawValue)…")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(DaddyTheme.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // OpenCode's last terminal line is TUI block art, not prose.
                // Do not put renderer fragments in its card. For every provider,
                // hold the line's height rather than inventing filler, so the
                // tile does not resize when the agent starts talking.
                Color.clear
            }
        }
        .frame(height: 13, alignment: .leading)
    }

    private func label(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Menu
    //
    // Same actions the old expanded card carried, reachable without leaving the
    // grid. Everything acts on this tile's active agent, except Stop all.

    private func menuItems(for agent: MockAgent) -> [GlassDropdownItem] {
        var items: [GlassDropdownItem] = []

        if agent.isLive {
            items.append(GlassDropdownItem(id: "detail", title: "Open detail") {
                withAnimation(.smooth(duration: 0.36)) { store.openDetail(agent.id) }
            })
        }

        if !agent.isLive {
            if store.canResumeChat(agent.agent) {
                items.append(GlassDropdownItem(id: "resume-chat", title: "Resume chat") {
                    store.relaunch(agent.id, continuingConversation: true)
                })
                items.append(GlassDropdownItem(id: "fresh", title: "Fresh start") {
                    store.relaunch(agent.id)
                })
            } else {
                items.append(GlassDropdownItem(id: "relaunch", title: "Relaunch") {
                    store.relaunch(agent.id)
                })
            }
        } else if agent.isBusy {
            items.append(GlassDropdownItem(id: "interrupt", title: "Interrupt") {
                store.interrupt(agent.id)
            })
            items.append(GlassDropdownItem(id: "stop", title: "Stop") {
                store.stop(agent.id)
            })
        } else {
            items.append(GlassDropdownItem(id: "continue", title: "Continue") {
                store.resume(agent.id)
            })
            items.append(GlassDropdownItem(id: "stop", title: "Stop") {
                store.stop(agent.id)
            })
        }

        items.append(GlassDropdownItem(id: "docs", title: "View docs") {
            onOpenProgress(agent.projectID)
        })

        let handoffTargets = [AgentKind.claude, .codex, .cursor, .opencode]
            .filter { $0 != agent.agent && store.isInstalled($0) }
        if !handoffTargets.isEmpty {
            items.append(
                GlassDropdownItem(
                    id: "handoff",
                    title: "Hand off",
                    children: handoffTargets.map { target in
                        GlassDropdownItem(
                            id: "handoff-\(target.rawValue)",
                            title: target.rawValue.capitalized,
                            leading: AnyView(ProviderLogo.badge(for: target, diameter: 16))
                        ) {
                            store.handOff(agent.id, to: target)
                        }
                    }
                )
            )
        }

        items.append(GlassDropdownItem(id: "dismiss", title: "Dismiss") {
            store.dismiss(agent.id)
        })

        let finishedCount = agents.filter { !$0.isLive }.count
        if finishedCount > 0 {
            items.append(
                GlassDropdownItem(
                    id: "dismiss-all",
                    title: "Dismiss all \(kind.rawValue.capitalized)",
                    note: "\(finishedCount)"
                ) {
                    store.dismissAllExited(kind, in: store.selectedProjectID)
                }
            )
        }

        if agents.filter(\.isLive).count > 1 {
            items.append(
                GlassDropdownItem(
                    id: "stop-all",
                    title: "Stop all \(kind.rawValue.capitalized)",
                    note: "\(agents.filter(\.isLive).count)"
                ) {
                    store.stopAll(kind)
                }
            )
        }

        return items
    }
}
