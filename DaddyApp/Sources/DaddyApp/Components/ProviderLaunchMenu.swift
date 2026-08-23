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
    @Binding var isOpen: Bool

    /// Where the agent will run. Nil disables the menu with an explanation
    /// rather than launching into a guess.
    let project: MockProject?
    /// Wider than the plain dropdown default: the rows carry a logo now, and
    /// "not installed" has to sit beside the name without wrapping.
    var width: CGFloat = 240
    /// Passed through, for a trigger that draws itself — see `GlassDropdown`.
    var chromelessLabel: Bool = false

    @State private var highlightedIndex = 0
    @State private var hasKeyboardSelection = false

    @ViewBuilder let label: () -> Label

    var body: some View {
        GlassDropdown(
            items: items,
            width: width,
            emptyMessage: "Select a project first",
            staysOpenOnPick: true,
            chromelessLabel: chromelessLabel,
            externalIsOpen: $isOpen,
            highlightedIndex: hasKeyboardSelection ? highlightedIndex : nil,
            onKeyboardMove: moveSelection,
            onKeyboardActivate: activateSelection,
            label: label
        )
        .onChange(of: isOpen) { _, open in
            if open {
                highlightedIndex = firstEnabledIndex ?? 0
                hasKeyboardSelection = false
            }
        }
    }

    private var items: [GlassDropdownItem] {
        guard let project else { return [] }

        var items = [AgentKind.claude, .codex, .cursor, .opencode].map { kind in
            let installed = store.isInstalled(kind)
            return GlassDropdownItem(
                id: kind.rawValue,
                title: kind.rawValue.capitalized,
                note: installed ? nil : "not installed",
                isEnabled: installed,
                leading: AnyView(ProviderLogo.badge(for: kind, diameter: 24))
            ) {
                store.launchReal(kind, in: project)
            }
        }

        // Also here, and not only on a card's menu: a project with nothing
        // running has no cards to open a menu from, and that is exactly when
        // you want to pick up where you left off.
        let chats = store.pastChats[project.id] ?? []
        if !chats.isEmpty {
            items.append(
                GlassDropdownItem(
                    id: "past-chats",
                    title: "Past chats",
                    note: "\(chats.count)",
                    childrenWidth: 380,
                    children: chats.prefix(12).map { chat in
                        GlassDropdownItem(
                            id: "past-\(chat.id)",
                            title: chat.title,
                            note: chat.age,
                            leading: AnyView(ProviderLogo.badge(for: chat.agent, diameter: 24))
                        ) {
                            store.openPastChat(chat, in: project)
                        }
                    }
                )
            )
        }

        return items
    }

    private var enabledIndices: [Int] {
        items.indices.filter { items[$0].isEnabled }
    }

    private var firstEnabledIndex: Int? { enabledIndices.first }

    private func moveSelection(_ direction: Int) {
        guard !enabledIndices.isEmpty else { return }
        let current = enabledIndices.firstIndex(of: highlightedIndex) ?? 0
        let next = (current + direction + enabledIndices.count) % enabledIndices.count
        highlightedIndex = enabledIndices[next]
        hasKeyboardSelection = true
    }

    private func activateSelection() {
        let index = items.indices.contains(highlightedIndex) && items[highlightedIndex].isEnabled
            ? highlightedIndex
            : firstEnabledIndex
        guard let index else { return }
        items[index].action()
    }

}
