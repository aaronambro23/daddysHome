import SwiftUI
import DaddyCore

/// "This session is nearly full. Here is what it wrote down. Who continues?"
///
/// Shaped after `BoardDispatchPicker` on purpose — the decision is the same
/// shape (pick a provider, big targets, one click) and the two should not look
/// like different apps. What is different is the middle: a handoff is worth
/// reading before you approve it, so the document's own summary is in the panel
/// rather than behind a link.
struct HandoffApprovalOverlay: View {
    @Environment(MockStore.self) private var store

    let pending: PendingContextHandoff

    private static let providers: [AgentKind] = [.claude, .codex, .cursor, .opencode]

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .contentShape(Rectangle())
                .onTapGesture { store.dismissContextHandoff() }

            VStack(spacing: 20) {
                heading
                summary
                providerRow
                footer
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
            .glassPanel()
            .frame(maxWidth: 660)
            .fixedSize(horizontal: false, vertical: true)
            .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
        }
        .transition(.opacity)
    }

    // MARK: - Heading

    private var heading: some View {
        VStack(spacing: 6) {
            Text("CONTEXT HANDOFF")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(DaddyTheme.textSecondary)

            Text(
                "\(pending.provider.rawValue.uppercased()) is at "
                    + "\(Int(pending.percent.rounded()))% and wrote a handoff for "
                    + pending.workUnitID
            )
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(DaddyTheme.textPrimary)
            .multilineTextAlignment(.center)

            Text("pick who continues — the prompt lands in its composer, unsent")
                .font(.system(size: 9.5))
                .foregroundStyle(DaddyTheme.textVeryDim)
        }
    }

    // MARK: - The document

    private var summary: some View {
        ScrollView {
            Text(pending.summary.isEmpty ? "The document is empty." : pending.summary)
                .font(.system(size: 11.5))
                .foregroundStyle(DaddyTheme.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxHeight: 180)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: - Providers
    //
    // The one that filled up comes first and is named "same again": continuing
    // where you were is the common answer, and it should be the shortest reach.

    private var providerRow: some View {
        HStack(spacing: 16) {
            ForEach(orderedProviders, id: \.self) { kind in
                bubble(kind)
            }
        }
    }

    private var orderedProviders: [AgentKind] {
        [pending.provider] + Self.providers.filter { $0 != pending.provider }
    }

    private func bubble(_ kind: AgentKind) -> some View {
        let installed = store.isInstalled(kind)

        return HandoffBubble(
            diameter: kind == pending.provider ? 92 : 76,
            tint: CompactAgentIcon.tint(for: kind),
            isEnabled: installed,
            title: kind.rawValue.capitalized,
            note: installed ? (kind == pending.provider ? "same again" : nil) : "not installed",
            bubble: AnyView(
                ProviderLogo.badge(for: kind, diameter: kind == pending.provider ? 92 : 76)
            )
        ) {
            withAnimation(.smooth(duration: 0.24)) {
                store.approveContextHandoff(continuingOn: kind)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            Button("open \(pending.filename)") { store.revealContextHandoff() }
                .buttonStyle(.inset(DaddyTheme.textMuted))

            Button("not now") { store.dismissContextHandoff() }
                .buttonStyle(.inset(DaddyTheme.textMuted))
        }
    }
}

/// Same idea as the board's dispatch bubble, which is `private` to its own file.
private struct HandoffBubble: View {
    let diameter: CGFloat
    let tint: Color
    let isEnabled: Bool
    let title: String
    let note: String?
    let bubble: AnyView
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                bubble
                    .overlay {
                        Circle()
                            .strokeBorder(tint.opacity(hovering ? 0.9 : 0), lineWidth: 2)
                            .frame(width: diameter, height: diameter)
                    }
                    .scaleEffect(hovering ? 1.06 : 1)
                    .shadow(color: tint.opacity(hovering ? 0.35 : 0), radius: 16)

                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DaddyTheme.textPrimary)
                        .lineLimit(1)
                    if let note {
                        Text(note)
                            .font(.system(size: 9))
                            .foregroundStyle(DaddyTheme.textVeryDim)
                            .lineLimit(1)
                    }
                }
                .frame(width: diameter + 24)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .animation(.easeOut(duration: 0.14), value: hovering)
        .onHover { hovering = isEnabled && $0 }
    }
}
