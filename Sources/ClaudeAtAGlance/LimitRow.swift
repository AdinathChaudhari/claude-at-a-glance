import SwiftUI
import GlanceCore

func color(for severity: Severity) -> Color {
    switch severity {
    case .normal: return .accentColor
    case .warning: return .orange
    case .critical: return .red
    }
}

/// One usage limit: label, bar, "N% used", reset line.
struct LimitRow: View {
    let limit: UsageLimit
    let dimmed: Bool
    let resetText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(limit.label).font(.system(size: 13, weight: .bold))
            ProgressView(value: min(max(limit.percent, 0), 100), total: 100)
                .progressViewStyle(.linear)
                .tint(color(for: limit.severity))
            HStack {
                if let resetText {
                    Text(resetText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(limit.percent.rounded()))% used").font(.caption)
            }
        }
        .opacity(dimmed ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ResetFormatter.spokenSummary(label: limit.label, percent: limit.percent, resetText: resetText))
    }
}
