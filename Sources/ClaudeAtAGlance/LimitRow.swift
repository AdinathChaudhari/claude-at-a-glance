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
            // Drawn by hand: the system progress bar can ignore .tint (e.g. when the
            // panel isn't the key window), which lost the orange/red warning colours.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.2))
                    Capsule()
                        .fill(color(for: limit.severity))
                        .frame(width: geo.size.width * min(max(limit.percent, 0), 100) / 100)
                }
            }
            .frame(height: 6)
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
