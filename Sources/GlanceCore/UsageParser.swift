import Foundation

public enum UsageParseError: Error, Equatable {
    case formatChanged
}

/// Lossy parser for the /api/oauth/usage response.
/// Decodes limits[] element by element, skips unknown kinds, falls back to
/// five_hour / seven_day utilization, and throws formatChanged when nothing usable is found.
public enum UsageParser {
    public static func parse(_ data: Data) throws -> [UsageLimit] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw UsageParseError.formatChanged
        }

        var limits: [UsageLimit] = []
        if let array = root["limits"] as? [Any] {
            for element in array {
                if let dict = element as? [String: Any], let limit = parseLimit(dict) {
                    limits.append(limit)
                }
            }
        }
        if limits.isEmpty {
            limits = legacyLimits(root)
        }
        guard !limits.isEmpty else { throw UsageParseError.formatChanged }
        return limits
    }

    // MARK: - limits[]

    private static func parseLimit(_ dict: [String: Any]) -> UsageLimit? {
        guard let kindString = dict["kind"] as? String,
              let percent = number(dict["percent"]) else { return nil }

        let kind: LimitKind
        let label: String
        var id = kindString
        switch kindString {
        case "session":
            kind = .session
            label = "Current session"
        case "weekly_all":
            kind = .weeklyAll
            label = "Current week (all models)"
        case "weekly_scoped":
            kind = .weeklyScoped
            let scope = dict["scope"] as? [String: Any]
            let model = scope?["model"] as? [String: Any]
            let name = (model?["display_name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "scoped"
            label = "Current week (\(name))"
            id = "weekly_scoped:\(name)"
        default:
            return nil
        }

        let severity = (dict["severity"] as? String).flatMap(Severity.init(rawValue:)) ?? severity(forPercent: percent)
        return UsageLimit(id: id, kind: kind, label: label, percent: percent,
                          resetsAt: date(dict["resets_at"]), severity: severity)
    }

    // MARK: - legacy fallback

    private static func legacyLimits(_ root: [String: Any]) -> [UsageLimit] {
        var result: [UsageLimit] = []
        if let w = root["five_hour"] as? [String: Any], let p = number(w["utilization"]) {
            result.append(UsageLimit(id: "session", kind: .session, label: "Current session", percent: p,
                                     resetsAt: date(w["resets_at"]), severity: severity(forPercent: p)))
        }
        if let w = root["seven_day"] as? [String: Any], let p = number(w["utilization"]) {
            result.append(UsageLimit(id: "weekly_all", kind: .weeklyAll, label: "Current week (all models)", percent: p,
                                     resetsAt: date(w["resets_at"]), severity: severity(forPercent: p)))
        }
        return result
    }

    // MARK: - helpers

    static func severity(forPercent p: Double) -> Severity {
        p >= 90 ? .critical : (p >= 75 ? .warning : .normal)
    }

    private static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.doubleValue }
        return nil
    }

    private static func date(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: s) { return d }
        // Fractional part longer than ISO8601DateFormatter accepts (e.g. 6 digits): trim to milliseconds.
        if let dot = s.firstIndex(of: "."),
           let tz = s[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            let frac = String(s[s.index(after: dot)..<tz]).prefix(3)
            let trimmed = String(s[..<dot]) + "." + frac + String(s[tz...])
            return withFraction.date(from: trimmed)
        }
        return nil
    }
}
