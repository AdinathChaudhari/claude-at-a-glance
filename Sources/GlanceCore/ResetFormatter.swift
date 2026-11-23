import Foundation

public enum ResetFormatter {
    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                 "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

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

        let h12 = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "am" : "pm"
        let time = "\(h12):" + (minute < 10 ? "0\(minute)" : "\(minute)") + suffix

        if cal.isDate(rounded, inSameDayAs: now) {
            return "Resets \(time)"
        }
        return "Resets \(months[month - 1]) \(day) at \(time)"
    }
}
