import SwiftUI
import DaddyCore

/// Voice intake, foreground-only.
///
/// HEX keeps its global hotkey and stays useful in every other app. Daddy takes
/// no microphone permission and watches no files: when Daddy becomes frontmost
/// it focuses the field below, HEX pastes the transcription straight into it
/// (`useClipboardPaste: true`, and there is no silent mode), and the
/// interpretation appears underneath.
///
/// Nothing runs until Return. Seeing what was heard before it executes is the
/// point — a misheard phrase should be visible, not surprising.
struct VoiceView: View {
    @Environment(AppStore.self) private var store
    @Environment(HandoffViewModel.self) private var handoffs

    @FocusState private var fieldFocused: Bool
    @State private var resolution: VoiceRouter.Resolution?

    private let router = VoiceRouter()

    private static let examples: [String] = [
        "start claude on payments",
        "continue 002",
        "copy the brief",
        "open wagerwise",
    ]

    var body: some View {
        @Bindable var store = store

        HStack(spacing: 16) {
            listenPanel(store: store)
                .frame(width: 460)

            logPanel
        }
        .onAppear {
            fieldFocused = true
            // Batch documents must be loaded before interpreting, or phrases
            // naming a batch ("continue payments") silently fall back to
            // starting a new one.
            handoffs.refresh(project: store.selectedProject)
            resolution = interpret(store.composeText)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            // The field must hold focus or HEX's paste lands nowhere.
            fieldFocused = true
        }
        .onChange(of: store.installedAgents) {
            // PATH resolution finishes on a background queue after launch, so
            // an early interpretation can wrongly report an agent as missing.
            resolution = interpret(store.composeText)
        }
    }

    // MARK: Intake

    private func listenPanel(store: AppStore) -> some View {
        @Bindable var store = store

        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "VOICE") {
                HeaderCaption(text: "hold ⌥ to dictate")
            }

            VStack(alignment: .leading, spacing: 16) {
                Text("""
                Speak while Daddy is in front. HEX types into the field below; \
                press Return to run it.
                """)
                    .font(.system(size: 10.5))
                    .foregroundStyle(DaddyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .font(.system(size: 12))
                        .foregroundStyle(
                            fieldFocused ? DaddyTheme.working : DaddyTheme.textMuted
                        )

                    TextField("say something, or type it", text: $store.composeText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(DaddyTheme.textPrimary)
                        .focused($fieldFocused)
                        .onChange(of: store.composeText) { _, new in
                            resolution = interpret(new)
                        }
                        .onSubmit(run)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .insetSurface(cornerRadius: 12, selected: fieldFocused)

                interpretation

                Spacer(minLength: 0)
            }
            .padding(20)

            GlassHairline()

            VStack(alignment: .leading, spacing: 9) {
                Text("EXAMPLES")
                    .font(.system(size: 9, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(DaddyTheme.textMuted)

                FlowRow(spacing: 7) {
                    ForEach(Self.examples, id: \.self) { phrase in
                        Button(phrase) {
                            store.composeText = phrase
                            resolution = interpret(phrase)
                            fieldFocused = true
                        }
                        .buttonStyle(.inset(DaddyTheme.textSecondary))
                    }
                }
            }
            .padding(18)
        }
        .glassPanel()
    }

    @ViewBuilder
    private var interpretation: some View {
        if let resolution, !resolution.preview.isEmpty {
            HStack(spacing: 9) {
                Image(systemName: isActionable ? "arrow.turn.down.right" : "questionmark.circle")
                    .font(.system(size: 10))
                Text(resolution.preview)
                    .font(.system(size: 11))
                Spacer(minLength: 6)
                if isActionable {
                    Text("return")
                        .font(.system(size: 9, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .insetCapsule(opacity: 0.10)
                }
            }
            .foregroundStyle(isActionable ? DaddyTheme.accent : DaddyTheme.textMuted)
        }
    }

    private var isActionable: Bool {
        switch resolution?.action {
        case .newBatch, .continueBatch, .copyBrief, .openProject: return true
        default: return false
        }
    }

    // MARK: Log

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "HISTORY") {
                HeaderCaption(text: "\(store.voiceLog.count)")
            }

            if store.voiceLog.isEmpty {
                VStack(spacing: 6) {
                    Text("Nothing yet")
                        .font(.system(size: 11))
                        .foregroundStyle(DaddyTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 9) {
                        ForEach(store.voiceLog) { entry in
                            VoiceLogRow(entry: entry)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .glassPanel()
    }

    // MARK: Behaviour

    private func interpret(_ text: String) -> VoiceRouter.Resolution? {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return router.resolve(
            text,
            projects: store.projects,
            documents: handoffs.documents,
            currentProjectID: store.selectedProjectID,
            installed: store.installedAgents
        )
    }

    private func run() {
        guard let resolution, isActionable else { return }
        let spoken = store.composeText

        switch resolution.action {
        case .newBatch(let agent, let projectID):
            if let project = store.project(projectID) {
                handoffs.launchNewBatch(agent: agent, in: project)
            }

        case .continueBatch(let agent, let projectID, let number):
            if let project = store.project(projectID),
               let doc = handoffs.documents.first(where: { $0.number == number }) {
                handoffs.launchContinuing(doc, agent: agent, in: project)
            }

        case .copyBrief(let projectID):
            if let project = store.project(projectID) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    handoffs.handoffBrief(for: project), forType: .string
                )
            }

        case .openProject(let projectID):
            store.openBatches(for: projectID)
            if let project = store.project(projectID) {
                handoffs.refresh(project: project)
            }

        case .needsTarget, .unrecognised:
            return
        }

        store.voiceLog.insert(
            VoiceEntry(
                at: Date(),
                transcript: spoken,
                resolution: resolution.preview,
                didSucceed: true
            ),
            at: 0
        )
        store.composeText = ""
        self.resolution = nil
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
                    .foregroundStyle(DaddyTheme.textMuted)
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
