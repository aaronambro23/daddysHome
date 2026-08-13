import SwiftUI

struct VoiceView: View {
    @Environment(MockStore.self) private var store

    @FocusState private var dictationFocused: Bool

    // Phrases the parser genuinely understands. These are not canned demos —
    // tapping one runs it through `CommandParser` and into a live session,
    // exactly as dictating it would.
    private static let examples: [String] = [
        "claude, continue",
        "codex, stop",
        "what's claude doing",
        "run the tests",
        "claude, fix the login bug",
        "dale",
        "frena",
        "hand this to codex",
    ]

    var body: some View {
        HStack(spacing: 16) {
            listenPanel
                .frame(width: 420)

            logPanel
        }
    }

    // MARK: Listening

    private var listenPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: store.isListening ? "LISTENING" : "VOICE") {
                HeaderCaption(text: "double-click ⌥")
            }

            VStack(spacing: 26) {
                Spacer(minLength: 10)

                waveform

                Button(store.isListening ? "Stop listening" : "Start listening") {
                    withAnimation(.smooth(duration: 0.35)) {
                        store.toggleListening()
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DaddyTheme.textPrimary)
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .insetCapsule(opacity: store.isListening ? 0.20 : 0.10)

                Text(store.isListening
                     ? "HEX is armed — dictation lands in the field below"
                     : "HEX is idle. Double-click ⌥ anywhere to wake it.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(DaddyTheme.textSecondary)
                    .multilineTextAlignment(.center)

                dictationField

                Spacer(minLength: 10)
            }
            .frame(maxWidth: .infinity)
            .padding(20)

            GlassHairline()

            VStack(alignment: .leading, spacing: 9) {
                Text("TRY")
                    .font(.system(size: 9, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(DaddyTheme.textMuted)

                FlowRow(spacing: 7) {
                    ForEach(Self.examples, id: \.self) { phrase in
                        Button {
                            withAnimation(.smooth(duration: 0.3)) {
                                store.submitVoice(phrase)
                            }
                        } label: {
                            Text(phrase)
                        }
                        .buttonStyle(.inset(DaddyTheme.textSecondary))
                    }
                }
            }
            .padding(18)
        }
        .glassPanel()
    }

    /// Where dictated text lands. HEX pastes into whatever has keyboard focus,
    /// so Daddy gives it a field of its own rather than reading another app's
    /// transcript file — no Full Disk Access, and you see what was heard before
    /// it reaches an agent.
    private var dictationField: some View {
        @Bindable var store = store

        return HStack(spacing: 10) {
            Image(systemName: "mic")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DaddyTheme.textMuted)

            TextField("speak, or type a command…", text: $store.voiceText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(DaddyTheme.textPrimary)
                .focused($dictationFocused)
                .onSubmit { store.submitVoice(store.voiceText) }

            Button("run") { store.submitVoice(store.voiceText) }
                .buttonStyle(.inset(DaddyTheme.working))
                .disabled(store.voiceText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .insetSurface(cornerRadius: 14)
        .onAppear { dictationFocused = true }
    }

    private var waveform: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 5) {
                ForEach(0..<28, id: \.self) { i in
                    let phase = Double(i) * 0.45
                    let wave = abs(sin(t * (store.isListening ? 3.4 : 0.7) + phase))
                    let height = 8 + wave * (store.isListening ? 66 : 12)

                    Capsule()
                        .fill(Color.white.opacity(store.isListening ? 0.85 : 0.28))
                        .frame(width: 5, height: height)
                }
            }
            .frame(height: 86)
        }
    }

    // MARK: Log

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "VOICE LOG") {
                HeaderCaption(text: "\(store.voiceLog.count) entries")
            }

            ScrollView {
                VStack(spacing: 9) {
                    ForEach(store.voiceLog) { entry in
                        VoiceLogRow(entry: entry)
                    }
                }
                .padding(16)
            }
        }
        .glassPanel()
    }
}

// MARK: - Log Row

struct VoiceLogRow: View {
    let entry: VoiceEntry

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.didSucceed ? "waveform" : "questionmark.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(entry.didSucceed ? DaddyTheme.textSecondary : DaddyTheme.limited)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                Text("“\(entry.transcript)”")
                    .font(.system(size: 12))
                    .foregroundStyle(DaddyTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(entry.resolution)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(
                        entry.didSucceed ? DaddyTheme.textMuted : DaddyTheme.limited
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Text(formatTimeAgo(entry.at))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(DaddyTheme.textMuted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .insetSurface(cornerRadius: 16, filled: hovering)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

// MARK: - Flow Layout

struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
