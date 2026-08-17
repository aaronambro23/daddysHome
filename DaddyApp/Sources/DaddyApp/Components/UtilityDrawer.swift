import SwiftUI
import DaddyCore

enum UtilityPanel: Equatable {
    case hex
    case settings
}

/// Contextual utilities that sit over Fleet without changing its geometry.
struct UtilityDrawer: View {
    @Environment(MockStore.self) private var store

    let panel: UtilityPanel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: panel == .hex ? "waveform" : "gearshape")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DaddyTheme.textSecondary)

                Text(panel == .hex ? "TRANSCRIPTS" : "SETTINGS")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(DaddyTheme.textPrimary)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DaddyTheme.textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .insetSurface(cornerRadius: 14)
                .help("Close")
            }
            .padding(16)

            GlassHairline()

            switch panel {
            case .hex:
                HEXUtilityPanel()
            case .settings:
                SettingsUtilityPanel()
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(DaddyTheme.popoverBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(DaddyTheme.insetStroke, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 28, x: -8, y: 12)
        .onExitCommand(perform: onClose)
    }
}

private struct HEXUtilityPanel: View {
    @Environment(MockStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("SESSION HISTORY")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(DaddyTheme.textMuted)
                Spacer()
                Text("\(store.voiceLog.count)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(DaddyTheme.textMuted)
            }

            if store.voiceLog.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 18))
                        .foregroundStyle(DaddyTheme.textVeryDim)
                    Text("No HEX transcripts this session.")
                        .font(.system(size: 11))
                        .foregroundStyle(DaddyTheme.textMuted)

                    Text("Transcripts appear here when HEX dictates into Daddy.")
                        .font(.system(size: 9.5))
                        .foregroundStyle(DaddyTheme.textVeryDim)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(store.voiceLog) { entry in
                            HEXHistoryRow(entry: entry)
                        }
                    }
                }
            }
        }
        .padding(14)
    }
}

private struct HEXHistoryRow: View {
    let entry: VoiceEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.didSucceed ? "waveform" : "questionmark.circle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(entry.didSucceed ? DaddyTheme.working : DaddyTheme.limited)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("“\(entry.transcript)”")
                    .font(.system(size: 11))
                    .foregroundStyle(DaddyTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(entry.resolution)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(entry.didSucceed ? DaddyTheme.textMuted : DaddyTheme.limited)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 6)

            Text(formatTimeAgo(entry.at))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(DaddyTheme.textMuted)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .insetSurface(cornerRadius: 12)
    }
}

private struct SettingsUtilityPanel: View {
    @Environment(MockStore.self) private var store

    private static let claudeModels = ["opus-5", "sonnet-5", "haiku-4-5"]

    var body: some View {
        @Bindable var store = store

        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                section("AGENT DEFAULTS") {
                    setting("Default Claude model", "Used for new Claude sessions.") {
                        Picker("", selection: $store.defaultModel) {
                            ForEach(Self.claudeModels, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    setting(
                        "Approval policy",
                        store.approvalPolicy == .safeAuto
                            ? "Pause before writes outside the work unit."
                            : "Run without approval pauses."
                    ) {
                        Picker("", selection: $store.approvalPolicy) {
                            Text("safe-auto").tag(ApprovalPolicy.safeAuto)
                            Text("full-bypass").tag(ApprovalPolicy.fullBypass)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    toggleSetting(
                        "Launch at login",
                        "Keep Daddy available after login.",
                        binding: $store.launchAtLogin
                    )
                }

                section("NOTIFICATIONS") {
                    toggleSetting(
                        "Agent ready",
                        "Notify when a session wants input.",
                        binding: $store.notifyOnReady
                    )
                    toggleSetting(
                        "Rate limited",
                        "Notify when a provider blocks progress.",
                        binding: $store.notifyOnRateLimit
                    )
                    toggleSetting(
                        "Session error",
                        "Notify when an adapter exits unexpectedly.",
                        binding: $store.notifyOnError
                    )
                }

                section("CURRENT STATE") {
                    MetricRow(label: "projects", value: "\(store.projects.count)")
                    MetricRow(label: "sessions", value: "\(store.liveAgentCount) live")
                    MetricRow(label: "storage", value: "session-only")
                }
            }
            .padding(16)
        }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(DaddyTheme.textMuted)

            VStack(alignment: .leading, spacing: 18) {
                content()
            }
            .padding(14)
            .insetSurface(cornerRadius: 15)
        }
    }

    private func setting<Control: View>(
        _ title: String,
        _ detail: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(DaddyTheme.textPrimary)
            Text(detail)
                .font(.system(size: 9.5))
                .foregroundStyle(DaddyTheme.textMuted)
            control()
                .controlSize(.small)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggleSetting(
        _ title: String,
        _ detail: String,
        binding: Binding<Bool>
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(DaddyTheme.textPrimary)
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(DaddyTheme.textMuted)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: binding)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
    }
}
