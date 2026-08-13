import SwiftUI

// MARK: - Glass Tab Bar
//
// The one place in the app that uses a tint, because this is the one place a
// tint is for: "Assign a tint color to suggest prominence."
//
// The selection indicator is a single glass view with a constant
// `glassEffectID`, so changing tabs morphs it across rather than cross-fading.

struct GlassTabBar: View {
    @Binding var selection: DaddyTab
    @Namespace private var namespace

    var body: some View {
        GlassEffectContainer(spacing: 18) {
            HStack(spacing: 2) {
                ForEach(DaddyTab.allCases) { tab in
                    tabButton(tab)
                }
            }
        }
    }

    private func tabButton(_ tab: DaddyTab) -> some View {
        let isSelected = selection == tab

        return Button {
            withAnimation(.smooth(duration: 0.42, extraBounce: 0.2)) {
                selection = tab
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(tab.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .tracking(0.2)
            }
            .foregroundStyle(isSelected ? Color.black.opacity(0.72) : DaddyTheme.textTertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                Color.clear
                    .glassEffect(
                        .regular.tint(DaddyTheme.accent.opacity(0.22)).interactive(),
                        in: Capsule()
                    )
                    .glassEffectID("tab-selection", in: namespace)
            }
        }
    }
}
