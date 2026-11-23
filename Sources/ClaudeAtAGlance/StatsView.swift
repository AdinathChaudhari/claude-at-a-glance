import SwiftUI
import GlanceCore

/// Stats tab: Today, Last 7 days, All time. Reads the local stats file only.
struct StatsView: View {
    let store: StatsStore
    /// True while the Stats tab is showing; reloads the file when it becomes active.
    var active: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch store.state {
            case .idle:
                Text("Loading…").foregroundStyle(.secondary)
            case .missing, .formatChanged:
                Text(store.state.message ?? "").font(.callout).foregroundStyle(.orange)
            case .loaded(let s):
                TodaySection(summary: s)
                WeekSection(summary: s)
                AllTimeSection(summary: s)
            }
        }
        .task { store.reload() }
        .onChange(of: active) { _, now in if now { store.reload() } }
    }
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.system(size: 13, weight: .bold)) }
}

/// Thin rounded proportional bar.
private struct FillBar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule().fill(Color.accentColor)
                    .frame(width: max(fraction > 0 ? 4 : 0, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 5)
    }
}

private struct TodaySection: View {
    let summary: StatsSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Today")
            Text(TokenFormatter.string(summary.todayTotalTokens) + " tokens")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            let top = summary.todayTokens.first?.tokens ?? 0
            ForEach(summary.todayTokens, id: \.name) { m in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(m.name).font(.caption)
                        Spacer()
                        Text(TokenFormatter.string(m.tokens)).font(.caption)
                    }
                    FillBar(fraction: top > 0 ? Double(m.tokens) / Double(top) : 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(m.name), \(TokenFormatter.string(m.tokens)) tokens")
            }
            if summary.todayMessages != nil || summary.todayToolCalls != nil {
                Text([summary.todayMessages.map { "\($0) messages" },
                      summary.todayToolCalls.map { "\($0) tool calls" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct WeekSection: View {
    let summary: StatsSummary
    private let chartHeight: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Last 7 days")
            let peak = max(summary.last7Days.map(\.tokens).max() ?? 0, 1)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(summary.last7Days.enumerated()), id: \.offset) { i, day in
                    let isToday = i == summary.last7Days.count - 1
                    VStack(spacing: 3) {
                        ZStack(alignment: .bottom) {
                            Color.clear
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isToday ? Color.accentColor : Color.accentColor.opacity(0.4))
                                .frame(height: max(day.tokens > 0 ? 4 : 2, chartHeight * CGFloat(day.tokens) / CGFloat(peak)))
                                .opacity(day.tokens > 0 ? 1 : 0.3)
                        }
                        .frame(height: chartHeight)
                        Text(initial(day.date))
                            .font(.system(size: 10, weight: isToday ? .bold : .regular))
                            .foregroundStyle(isToday ? Color.primary : Color.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(weekday(day.date)), \(TokenFormatter.string(day.tokens)) tokens")
                }
            }
            Text(TokenFormatter.string(summary.weekTotalTokens) + " tokens this week")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func weekday(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE"
        return f.string(from: date)
    }

    private func initial(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEEE"
        return f.string(from: date)
    }
}

private struct AllTimeSection: View {
    let summary: StatsSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle("All time")
            if summary.allTimeTokens > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(TokenFormatter.string(summary.allTimeTokens))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("Tokens").font(.caption).foregroundStyle(.secondary)
                }
                let top = summary.allTimeTokensByModel.first?.tokens ?? 0
                ForEach(summary.allTimeTokensByModel, id: \.name) { m in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(m.name).font(.caption)
                            Spacer()
                            Text(TokenFormatter.string(m.tokens)).font(.caption)
                        }
                        FillBar(fraction: top > 0 ? Double(m.tokens) / Double(top) : 0)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(m.name), \(TokenFormatter.string(m.tokens)) tokens")
                }
            }
            HStack(spacing: 14) {
                if let n = summary.totalSessions { stat("\(n)", "sessions") }
                if let n = summary.totalMessages { stat(n.formatted(), "messages") }
            }
            let facts = [
                summary.currentStreak > 0 ? "\(summary.currentStreak)-day streak" : nil,
                summary.busiestHour.map { "busiest hour \($0)" },
                summary.firstSessionDate.map { "since " + $0.formatted(.dateTime.month(.abbreviated).day().year()) }
            ].compactMap { $0 }
            if !facts.isEmpty {
                Text(facts.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
            if let l = summary.longestSession, let d = l.durationText {
                Text("Longest session \(d)" + (l.messageCount.map { ", \($0) messages" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(.system(size: 15, weight: .bold, design: .rounded))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
