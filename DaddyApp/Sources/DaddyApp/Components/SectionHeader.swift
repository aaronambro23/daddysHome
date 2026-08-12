import SwiftUI

/// Panel header: eyebrow label left, monospaced detail right, hairline under.
/// Uniformly grey — coloured section labels were part of what made the app
/// read as paint rather than glass.
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(DaddyTheme.textSecondary)

                Spacer(minLength: 12)

                trailing
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            GlassHairline()
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

struct HeaderCaption: View {
    let text: String
    var tint: Color = DaddyTheme.textMuted

    var body: some View {
        Text(text)
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(tint)
    }
}
