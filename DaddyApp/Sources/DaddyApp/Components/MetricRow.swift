import SwiftUI

struct MetricRow: View {
    let label: String
    let value: String
    var accent: Color = DaddyTheme.textSecondary

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(DaddyTheme.textMuted)
                .frame(width: 52, alignment: .leading)

            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(accent)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
