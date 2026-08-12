import SwiftUI
import DaddyCore

struct SettingsView: View {
    @Environment(MockStore.self) private var store

    private static let claudeModels = ["opus-5", "sonnet-5", "haiku-4-5"]

    var body: some View {
        @Bindable var store = store

        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "AGENT DEFAULTS") {
                    HeaderCaption(text: "applies to new sessions")
                }

                VStack(alignment: .leading, spacing: 22) {
                    settingBlock(
                        "Default Claude model",
                        "Used when a voice command doesn't name a model."
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
                        "Approval policy",
                        store.approvalPolicy == .safeAuto
                            ? "Agents pause before writes outside the work unit."
                            : "Agents never pause. Fast, and entirely on you."
                    ) {
                        Picker("", selection: $store.approvalPolicy) {
                            Text("safe-auto").tag(ApprovalPolicy.safeAuto)
                            Text("full-bypass").tag(ApprovalPolicy.fullBypass)
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
                SectionHeader(title: "NOTIFICATIONS") {
                    HeaderCaption(text: "\(activeNotificationCount)/3 on")
                }

                VStack(alignment: .leading, spacing: 22) {
                    settingBlock("Agent ready", "Ping when a session finishes and wants input.") {
                        Toggle("", isOn: $store.notifyOnReady)
                            .toggleStyle(.switch).labelsHidden()
                    }

                    settingBlock("Rate limited", "Ping when an agent hits a provider limit.") {
                        Toggle("", isOn: $store.notifyOnRateLimit)
                            .toggleStyle(.switch).labelsHidden()
                    }

                    settingBlock("Session error", "Ping when an adapter exits unexpectedly.") {
                        Toggle("", isOn: $store.notifyOnError)
                            .toggleStyle(.switch).labelsHidden()
                    }
                }
                .padding(20)

                GlassHairline()

                VStack(alignment: .leading, spacing: 12) {
                    Text("STATE")
                        .font(.system(size: 9, weight: .medium))
                        .tracking(0.6)
                        .foregroundStyle(DaddyTheme.textMuted)

                    MetricRow(label: "projects", value: "\(store.projects.count)")
                    MetricRow(label: "sessions", value: "\(store.liveAgentCount) live")
                    MetricRow(label: "units", value: "\(store.workUnits.count)")
                    MetricRow(label: "store", value: "~/Library/Daddy/state.json")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)

                Spacer(minLength: 0)
            }
            .glassPanel()
        }
    }

    private var activeNotificationCount: Int {
        [store.notifyOnReady, store.notifyOnRateLimit, store.notifyOnError]
            .filter { $0 }.count
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
