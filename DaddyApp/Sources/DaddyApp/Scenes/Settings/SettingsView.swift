import SwiftUI
import DaddyCore

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(HandoffViewModel.self) private var handoffs

    private static let claudeModels = ["opus-5", "sonnet-5", "haiku-4-5"]

    var body: some View {
        @Bindable var store = store

        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "DEFAULTS") {
                    HeaderCaption(text: "applies to launched agents")
                }

                VStack(alignment: .leading, spacing: 22) {
                    settingBlock(
                        "Default Claude model",
                        "Used when a launch doesn't name a model."
                    ) {
                        Picker("", selection: $store.defaultModel) {
                            ForEach(Self.claudeModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    settingBlock(
                        "Launch at login",
                        "Keep Daddy in the menu bar across restarts."
                    ) {
                        Toggle("", isOn: $store.launchAtLogin)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }
                .padding(20)

                Spacer(minLength: 0)
            }
            .glassPanel()

            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "AGENT CLIS") {
                    HeaderCaption(text: "\(store.installedAgents.count)/4 found")
                }

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(AgentKind.allCases, id: \.rawValue) { kind in
                        HStack(spacing: 10) {
                            Image(systemName: store.isInstalled(kind)
                                  ? "checkmark.circle.fill"
                                  : "xmark.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(store.isInstalled(kind)
                                                 ? DaddyTheme.working
                                                 : DaddyTheme.textMuted)

                            Text(kind.displayName)
                                .font(.system(size: 12))
                                .foregroundStyle(DaddyTheme.textPrimary)

                            Spacer(minLength: 6)

                            Text(kind.executableName)
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(DaddyTheme.textMuted)
                        }
                    }
                }
                .padding(20)

                GlassHairline()

                VStack(alignment: .leading, spacing: 10) {
                    Text("TRACKED")
                        .font(.system(size: 9, weight: .medium))
                        .tracking(0.6)
                        .foregroundStyle(DaddyTheme.textMuted)

                    statRow("projects", "\(store.projects.count)")
                    statRow("with batches", "\(handoffs.summaries.count)")
                    statRow("tasks open", "\(handoffs.totalOutstandingTasks)")
                    statRow("needs attention", "\(handoffs.attentionItems.count)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)

                Spacer(minLength: 0)
            }
            .glassPanel()
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(DaddyTheme.textMuted)
                .frame(width: 110, alignment: .leading)

            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(DaddyTheme.textSecondary)
        }
    }

    @ViewBuilder
    private func settingBlock<Control: View>(
        _ title: String,
        _ detail: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DaddyTheme.textPrimary)

            Text(detail)
                .font(.system(size: 10.5))
                .foregroundStyle(DaddyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            control()
                .controlSize(.small)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
