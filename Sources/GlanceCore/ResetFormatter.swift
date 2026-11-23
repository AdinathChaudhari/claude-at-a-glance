import Foundation

public enum ResetFormatter {
    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                 "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "12:04pm": 12-hour lowercase am/pm, fixed format independent of the Mac's clock setting.
    public static func clock(_ date: Date, timeZone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.hour, .minute], from: date)
        return clockString(hour: c.hour ?? 0, minute: c.minute ?? 0)
    }

    private static func clockString(hour: Int, minute: Int) -> String {
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(h12):" + (minute < 10 ? "0\(minute)" : "\(minute)") + (hour < 12 ? "am" : "pm")
    }

    /// VoiceOver text for a limit row, e.g. "Current session, 27 percent used, resets 2:40pm".
    public static func spokenSummary(label: String, percent: Double, resetText: String?) -> String {
        var s = "\(label), \(Int(percent.rounded())) percent used"
        if let r = resetText { s += ", " + r.prefix(1).lowercased() + r.dropFirst() }
        return s
    }

    /// Returns nil for nil input. Otherwise "Resets 2:40pm" (same local day as `now`)
    /// or "Resets Nov 29 at 5:30am" (other day). Rounds to the nearest minute.
    /// Output is fixed English with a 12-hour clock; `locale` is accepted for API
    /// stability but deliberately not used, so the text never varies by system settings.
    public static func string(for date: Date?, now: Date, timeZone: TimeZone, locale: Locale) -> String? {
        guard let date else { return nil }
        _ = locale

        let rounded = Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded() * 60)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone

        let c = cal.dateComponents([.month, .day, .hour, .minute], from: rounded)
        guard let month = c.month, let day = c.day, let hour = c.hour, let minute = c.minute else { return nil }

        let time = clockString(hour: hour, minute: minute)

        if cal.isDate(rounded, inSameDayAs: now) {
            return "Resets \(time)"
        }
        return "Resets \(months[month - 1]) \(day) at \(time)"
    }
}
