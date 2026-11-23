import Foundation

public enum StatsParseError: Error, Equatable, Sendable {
    case formatChanged
}

public struct ModelTokens: Equatable, Sendable {
    public let name: String
    public let tokens: Int
}

public struct DayTokens: Equatable, Sendable {
    public let date: Date
    public let tokens: Int
}

public struct LongestSession: Equatable, Sendable {
    public let messageCount: Int?
    public let durationMs: Int?
    /// "5d 5h"-style text, nil when the duration is unknown.
    public var durationText: String? { durationMs.map(StatsParser.durationText) }
}

/// Lossy summary of Claude Code's stats-cache.json. Every field may be missing.
public struct StatsSummary: Equatable, Sendable {
    public var todayTokens: [ModelTokens] = []
    public var todayMessages: Int?
    public var todayToolCalls: Int?
    /// Seven entries, oldest first, ending today. Missing days are 0.
    public var last7Days: [DayTokens] = []
    public var weekTokensByModel: [ModelTokens] = []
    /// Sum of every day's tokens across all models.
    public var allTimeTokens: Int = 0
    /// Per model over all days, display names merged, largest first.
    public var allTimeTokensByModel: [ModelTokens] = []
    public var totalSessions: Int?
    public var totalMessages: Int?
    public var firstSessionDate: Date?
    public var longestSession: LongestSession?
    public var busiestHour: String?
    public var currentStreak: Int = 0
    public var lastComputedDate: String?

    public var todayTotalTokens: Int { todayTokens.reduce(0) { $0 + $1.tokens } }
    public var weekTotalTokens: Int { last7Days.reduce(0) { $0 + $1.tokens } }
}

public enum StatsParser {
    public static func parse(_ data: Data, today: Date, calendar: Calendar) throws -> StatsSummary {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw StatsParseError.formatChanged
        }
        var s = StatsSummary()
        let todayKey = key(today, calendar)
        let weekDates: [Date] = (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let weekKeys = weekDates.map { key($0, calendar) }

        // Tokens per day per model.
        var tokensByDay: [String: [String: Int]] = [:]
        for entry in (root["dailyModelTokens"] as? [Any]) ?? [] {
            guard let e = entry as? [String: Any], let d = e["date"] as? String,
                  let byModel = e["tokensByModel"] as? [String: Any] else { continue }
            var m = tokensByDay[d] ?? [:]
            for (model, v) in byModel { if let n = int(v) { m[model, default: 0] += max(n, 0) } }
            tokensByDay[d] = m
        }
        func sorted(_ m: [String: Int]) -> [ModelTokens] {
            Dictionary(m.map { (ModelName.display($0.key), $0.value) }, uniquingKeysWith: +)
                .map { ModelTokens(name: $0.key, tokens: $0.value) }
                .sorted { $0.tokens != $1.tokens ? $0.tokens > $1.tokens : $0.name < $1.name }
        }
        s.todayTokens = sorted(tokensByDay[todayKey] ?? [:])
        var week: [String: Int] = [:]
        s.last7Days = zip(weekDates, weekKeys).map { date, k in
            let perModel = tokensByDay[k] ?? [:]
            for (model, n) in perModel { week[model, default: 0] += n }
            return DayTokens(date: date, tokens: perModel.values.reduce(0, +))
        }
        s.weekTokensByModel = sorted(week)
        var allTime: [String: Int] = [:]
        for perModel in tokensByDay.values { for (model, n) in perModel { allTime[model, default: 0] += n } }
        s.allTimeTokens = allTime.values.reduce(0, +)
        s.allTimeTokensByModel = sorted(allTime)

        // Activity: today's counts and the streak.
        var activeDays = Set(tokensByDay.filter { $0.value.values.contains { $0 > 0 } }.keys)
        for entry in (root["dailyActivity"] as? [Any]) ?? [] {
            guard let e = entry as? [String: Any], let d = e["date"] as? String else { continue }
            let msgs = int(e["messageCount"]), tools = int(e["toolCallCount"]), sess = int(e["sessionCount"])
            if (msgs ?? 0) > 0 || (tools ?? 0) > 0 || (sess ?? 0) > 0 { activeDays.insert(d) }
            if d == todayKey { s.todayMessages = msgs; s.todayToolCalls = tools }
        }
        var cursor = today
        if !activeDays.contains(todayKey), let y = calendar.date(byAdding: .day, value: -1, to: today) { cursor = y }
        while activeDays.contains(key(cursor, calendar)) {
            s.currentStreak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }

        // Totals.
        s.totalSessions = int(root["totalSessions"])
        s.totalMessages = int(root["totalMessages"])
        s.lastComputedDate = root["lastComputedDate"] as? String
        if let f = root["firstSessionDate"] as? String { s.firstSessionDate = parseISO(f) }
        if let l = root["longestSession"] as? [String: Any] {
            let ls = LongestSession(messageCount: int(l["messageCount"]), durationMs: int(l["duration"]))
            if ls.messageCount != nil || ls.durationMs != nil { s.longestSession = ls }
        }
        if let h = root["hourCounts"] as? [String: Any] {
            let counts = h.compactMap { k, v -> (Int, Int)? in
                guard let hour = Int(k), (0..<24).contains(hour), let n = int(v), n > 0 else { return nil }
                return (hour, n)
            }
            if let best = counts.max(by: { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 > $1.0 }) {
                s.busiestHour = hourText(best.0)
            }
        }
        return s
    }

    // MARK: - Helpers

    static func key(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func int(_ v: Any?) -> Int? {
        if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() {
            let d = n.doubleValue
            return d.isFinite && abs(d) < 9e15 ? Int(d) : nil
        }
        return nil
    }

    static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// 10 -> "10am", 0 -> "12am", 15 -> "3pm".
    public static func hourText(_ hour: Int) -> String {
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(h12)\(hour < 12 ? "am" : "pm")"
    }

    /// 450000000 ms -> "5d 5h"; under a day "5h 20m"; under an hour "42m".
    public static func durationText(_ ms: Int) -> String {
        let minutes = max(ms, 0) / 60_000
        let days = minutes / 1440, hours = (minutes % 1440) / 60, mins = minutes % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }
}
