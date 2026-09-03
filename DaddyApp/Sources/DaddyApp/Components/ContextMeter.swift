import SwiftUI
import DaddyCore

/// How full this session's context window is, on the focus toolbar.
///
/// It was only in the overflow menu, which is the wrong place for the one
/// number that decides whether the session you are typing into is about to be
/// handed to someone else. You should be able to see it filling.
///
/// Deliberately the same shape as `ProviderUsageBattery` sitting next to it —
/// label, meter, percentage — because they are the same kind of fact at two
/// scales: that one is your account's quota, this one is this conversation's.
/// The colours are keyed to the handoff threshold rather than the battery's
/// generic bands, so amber means "Daddy will offer a handoff as soon as this
/// goes idle" rather than a vague warm feeling.
///
/// The states with no number are the point of this component as much as the
/// number is. An empty bar used to mean four different things at once, one of
/// which — Daddy has lost track of which conversation this card is — is a
/// broken link you can actually repair. It says so now, and offers the repair.
struct ContextMeter: View {
    @Environment(MockStore.self) private var store

    let agent: MockAgent
    var compact = false

    @State private var linkMenuOpen = false

    var body: some View {
        HStack(spacing: 7) {
            Text("CTX")
                .font(.system(size: compact ? 8.5 : 9, weight: .medium, design: .monospaced))
                .foregroundStyle(DaddyTheme.textTertiary)

            switch agent.context {
            case .reported(let percent):
                meter(percent)
                percentage(percent)
            case .noTurnYet:
                idle
            case .notReported:
                struck
            case .transcriptMissing:
                unlinked
            }
        }
        .help(helpText)
    }

    // MARK: - The number

    private func meter(_ percent: Double) -> some View {
        GeometryReader { geometry in
            let width = max(0, geometry.size.width * min(percent, 100) / 100)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.07))

                Capsule()
                    .fill(color(percent))
                    .frame(width: width)
            }
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.75)
            }
            // Where the handoff fires. A meter with no mark on it makes 64%
            // and 66% look like the same thing, and they are not.
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.45))
                    .frame(width: 1, height: compact ? 8 : 10)
                    .offset(x: geometry.size.width * ContextHandoff.threshold / 100)
            }
        }
        .frame(width: compact ? 46 : 62, height: compact ? 8 : 10)
        .animation(.easeOut(duration: 0.3), value: percent)
    }

    private func percentage(_ percent: Double) -> some View {
        Text("\(Int(percent.rounded()))%")
            .font(.system(size: compact ? 8.5 : 9.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(color(percent))
            .monospacedDigit()
            .frame(width: compact ? 30 : 34, alignment: .trailing)
    }

    // MARK: - The states with no number

    /// The transcript is there and empty. Nothing is wrong; nothing has been
    /// said yet. An outline, waiting to fill.
    private var idle: some View {
        Capsule()
            .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.75)
            .frame(width: compact ? 46 : 62, height: compact ? 8 : 10)
    }

    /// Cursor and OpenCode do not write their token usage down anywhere, so
    /// there is genuinely nothing to show. Struck through, like the battery's
    /// own unavailable state, rather than a hopeful empty bar.
    private var struck: some View {
        ZStack {
            Capsule()
                .fill(Color.white.opacity(0.05))
            Capsule()
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.75)
            Rectangle()
                .fill(DaddyTheme.textMuted)
                .frame(width: 1, height: compact ? 10 : 12)
                .rotationEffect(.degrees(55))
        }
        .frame(width: compact ? 46 : 62, height: compact ? 8 : 10)
    }

    /// The one that is actually broken, and the only one you can do anything
    /// about: this CLI keeps a transcript, and Daddy cannot find this session's.
    /// Reading a percentage is impossible until the card is pointed at the
    /// right conversation, so the control to do that *is* the state.
    private var unlinked: some View {
        GlassDropdown(
            items: linkItems,
            width: 380,
            emptyMessage: "No conversations found in this project",
            chromelessLabel: true,
            externalIsOpen: $linkMenuOpen
        ) {
            HStack(spacing: 4) {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: compact ? 8 : 9, weight: .bold))
                Text("not linked")
                    .font(.system(size: compact ? 8.5 : 9, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(DaddyTheme.limited)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background {
                Capsule().fill(DaddyTheme.limited.opacity(0.14))
            }
            .overlay {
                Capsule().strokeBorder(DaddyTheme.limited.opacity(0.35), lineWidth: 0.75)
            }
            .contentShape(Capsule())
        }
    }

    /// The conversations Daddy can see in this project, newest first. Picking
    /// one tells the card which transcript is its own.
    private var linkItems: [GlassDropdownItem] {
        (store.pastChats[agent.projectID] ?? [])
            .filter { $0.agent == agent.agent }
            .prefix(12)
            .map { chat in
                GlassDropdownItem(
                    id: chat.id,
                    title: chat.title,
                    note: Self.age(chat.updatedAt)
                ) {
                    store.linkTranscript(chat, to: agent.id)
                }
            }
    }

    private static func age(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 3_600 { return "\(max(1, seconds / 60))m ago" }
        if seconds < 86_400 { return "\(seconds / 3_600)h ago" }
        return "\(seconds / 86_400)d ago"
    }

    // MARK: - Colour and words

    private func color(_ percent: Double) -> Color {
        if percent >= 85 { return DaddyTheme.failure }
        if percent >= ContextHandoff.threshold { return DaddyTheme.limited }
        return DaddyTheme.ready
    }

    private var helpText: String {
        switch agent.context {
        case .reported(let percent) where percent >= ContextHandoff.threshold:
            return "Context \(Int(percent.rounded()))% full — "
                + "a handoff will be offered as soon as this session goes idle."
        case .reported(let percent):
            return "Context \(Int(percent.rounded()))% full. "
                + "At \(Int(ContextHandoff.threshold))%, Daddy asks for a handoff document."
        case .notReported:
            return "\(agent.displayName) does not report its context usage, "
                + "so Daddy cannot offer a handoff for this session."
        case .noTurnYet:
            return "Nothing said yet — the context fills on the first turn."
        case .transcriptMissing:
            return "Daddy cannot find this session's transcript, so it cannot read the "
                + "context or offer a handoff. Usually a conversation Daddy did not "
                + "start itself. Click to point the card at the right conversation."
        }
    }
}
