import XCTest
@testable import GlanceCore

final class FormatterTests: XCTestCase {
    private let locale = Locale(identifier: "en_US_POSIX")
    private let kolkata = TimeZone(identifier: "Asia/Kolkata")!
    private let newYork = TimeZone(identifier: "America/New_York")!

    private func iso(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)!
    }


    private var fixedNow: Date { iso("2026-11-23T05:00:00Z") }

    func testSameDayKolkata() {
        let s = ResetFormatter.string(for: iso("2026-11-23T09:09:59.391426+00:00"),
                                      now: fixedNow, timeZone: kolkata, locale: locale)
        XCTAssertEqual(s, "Resets 2:40pm")
    }

    func testOtherDayKolkata() {
        let s = ResetFormatter.string(for: iso("2026-11-28T23:59:59.391445+00:00"),
                                      now: fixedNow, timeZone: kolkata, locale: locale)
        XCTAssertEqual(s, "Resets Nov 29 at 5:30am")
    }

    func testNilReturnsNil() {
        XCTAssertNil(ResetFormatter.string(for: nil, now: fixedNow, timeZone: kolkata, locale: locale))
    }

    func testNewYork() {
        // now = 00:00 EST Nov 23; 09:09:59Z = 4:10am EST (rounded up from 4:09:59)
        let same = ResetFormatter.string(for: iso("2026-11-23T09:09:59.391426+00:00"),
                                         now: fixedNow, timeZone: newYork, locale: locale)
        XCTAssertEqual(same, "Resets 4:10am")
        // 23:59:59Z Nov 28 = 6:59pm EST (rounded to 7:00pm)
        let other = ResetFormatter.string(for: iso("2026-11-28T23:59:59.391445+00:00"),
                                          now: fixedNow, timeZone: newYork, locale: locale)
        XCTAssertEqual(other, "Resets Nov 28 at 7:00pm")
    }

    func testMidnightBoundaryKolkata() {
        // Kolkata = UTC+5:30. now = 2026-11-23 10:30 local (05:00Z).
        // 18:29Z = 23:59 local Nov 23 -> same day.
        let before = ResetFormatter.string(for: iso("2026-11-23T18:29:00Z"),
                                           now: fixedNow, timeZone: kolkata, locale: locale)
        XCTAssertEqual(before, "Resets 11:59pm")
        // 18:30Z = 00:00 local Nov 24 -> tomorrow.
        let after = ResetFormatter.string(for: iso("2026-11-23T18:30:00Z"),
                                          now: fixedNow, timeZone: kolkata, locale: locale)
        XCTAssertEqual(after, "Resets Nov 24 at 12:00am")
    }

    func testRoundingCrossesMidnight() {
        // 23:59:40 local rounds up to 00:00 next day.
        let s = ResetFormatter.string(for: iso("2026-11-23T18:29:40Z"),
                                      now: fixedNow, timeZone: kolkata, locale: locale)
        XCTAssertEqual(s, "Resets Nov 24 at 12:00am")
    }

    func testNoon() {
        let s = ResetFormatter.string(for: iso("2026-11-23T06:30:00Z"),
                                      now: fixedNow, timeZone: kolkata, locale: locale)
        XCTAssertEqual(s, "Resets 12:00pm")
    }

    func testClockIsTwelveHourLowercase() {
        let utc = TimeZone(identifier: "UTC")!
        let midnight: TimeInterval = 1_799_971_200 // a UTC midnight
        let noon = Date(timeIntervalSince1970: midnight + 43_440)
        XCTAssertEqual(ResetFormatter.clock(noon, timeZone: utc), "12:04pm")
        XCTAssertEqual(ResetFormatter.clock(noon.addingTimeInterval(13 * 3600), timeZone: utc), "1:04am")
    }

    func testSpokenSummary() {
        XCTAssertEqual(ResetFormatter.spokenSummary(label: "Current session", percent: 27.2, resetText: "Resets 2:40pm"),
                       "Current session, 27 percent used, resets 2:40pm")
        XCTAssertEqual(ResetFormatter.spokenSummary(label: "X", percent: 5, resetText: nil), "X, 5 percent used")
    }
}
