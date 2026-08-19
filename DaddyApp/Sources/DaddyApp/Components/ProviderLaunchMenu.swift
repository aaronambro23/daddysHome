import SwiftUI
import DaddyCore

/// "Start an agent here." One definition, two homes: the dashboard's AGENTS
/// header and the focus toolbar.
///
/// It lived only on the dashboard, which meant that once you were inside a
/// terminal the only way to start a second agent was to navigate out of it. The
/// list of providers and their installed state must not be maintained in two
/// places, so this is the list.
struct ProviderLaunchMenu<Label: View>: View {
    @Environment(MockStore.self) private var store

    /// Where the agent will run. Nil disables the menu with an explanation
    /// rather than launching into a guess.
    let project: MockProject?
    /// Passed through, for a trigger that draws itself — see `GlassDropdown`.
    var chromelessLabel: Bool = false

    @ViewBuilder let label: () -> Label

    var body: some View {
        if project == nil {
            label()
                .disabled(true)
                .help("Select a project first")
        } else {
            RadialProviderMenu(
                items: providerItems,
                onDismiss: {},
                label: label
            )
        }
    }

    private var providerItems: [ProviderMenuItem] {
        guard let project else { return [] }

        return [AgentKind.claude, .codex, .cursor, .opencode].map { kind in
            let installed = store.isInstalled(kind)
            return ProviderMenuItem(
                kind: kind,
                isEnabled: installed
            ) {
                store.launchReal(kind, in: project)
            }
        }
    }
}
