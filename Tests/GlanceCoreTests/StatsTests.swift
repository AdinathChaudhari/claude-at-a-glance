import XCTest
@testable import GlanceCore

final class StatsTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.calendar = cal; f.timeZone = cal.timeZone; f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)!.addingTimeInterval(12 * 3600)
    }
    private func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "stats-sample", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func testFixtureParses() throws {
        let s = try StatsParser.parse(try fixture(), today: date("2026-03-14"), calendar: cal)
        XCTAssertEqual(s.todayTokens, [
            ModelTokens(name: "Opus 5.5", tokens: 18_000_000),
            ModelTokens(name: "Fable 5", tokens: 632_089),
            ModelTokens(name: "claude-mystery", tokens: 999)])
        XCTAssertEqual(s.todayTotalTokens, 18_633_088)
        XCTAssertEqual(s.todayMessages, 143)
        XCTAssertEqual(s.todayToolCalls, 31)
        XCTAssertEqual(s.totalSessions, 42)
        XCTAssertEqual(s.totalMessages, 9876)
        XCTAssertEqual(s.longestSession?.messageCount, 2204)
        XCTAssertEqual(s.longestSession?.durationText, "5d 5h")
        XCTAssertEqual(s.busiestHour, "10am")   // tie with 14 -> earlier hour
        XCTAssertEqual(s.lastComputedDate, "2026-03-14")
        XCTAssertNotNil(s.firstSessionDate)
        XCTAssertEqual(s.weekTokensByModel.first, ModelTokens(name: "Opus 5.5", tokens: 20_001_300))
    }

    func testAllTimeTokens() throws {
        let s = try StatsParser.parse(try fixture(), today: date("2026-03-14"), calendar: cal)
        XCTAssertEqual(s.allTimeTokens, 21_387_044)
        XCTAssertEqual(s.allTimeTokensByModel, [
            ModelTokens(name: "Opus 5.5", tokens: 20_001_300),
            ModelTokens(name: "Sonnet 5.5", tokens: 752_656),
            ModelTokens(name: "Fable 5", tokens: 632_089),
            ModelTokens(name: "claude-mystery", tokens: 999)])
    }

    func testAllTimeMergesSameDisplayNameAndIncludesOldDays() throws {
        let json = #"{"dailyModelTokens":[{"date":"2020-01-01","tokensByModel":{"claude-haiku-4-5":100,"claude-haiku-4-5-20251001":50}},{"date":"2026-03-14","tokensByModel":{"claude-haiku-4-5-20251001":25,"claude-opus-5-5":10}}]}"#
        let s = try StatsParser.parse(Data(json.utf8), today: date("2026-03-14"), calendar: cal)
        XCTAssertEqual(s.allTimeTokens, 185)
        XCTAssertEqual(s.allTimeTokensByModel, [ModelTokens(name: "Haiku 4.5", tokens: 175),
                                                ModelTokens(name: "Opus 5.5", tokens: 10)])
        let empty = try StatsParser.parse(Data("{}".utf8), today: date("2026-03-14"), calendar: cal)
        XCTAssertEqual(empty.allTimeTokens, 0)
        XCTAssertEqual(empty.allTimeTokensByModel, [])
    }

    func testMissingDaysZeroFilled() throws {
        let s = try StatsParser.parse(try fixture(), today: date("2026-03-14"), calendar: cal)
        XCTAssertEqual(s.last7Days.count, 7)
        XCTAssertEqual(s.last7Days.map(\.tokens), [0, 1000, 0, 2_000_500, 752_156, 300, 18_633_088])
        XCTAssertEqual(s.last7Days.last?.date, date("2026-03-14"))
    }

    func testStreak() throws {
        let d = try fixture()
        // 11, 12, 13, 14 active; 10 missing.
        XCTAssertEqual(try StatsParser.parse(d, today: date("2026-03-14"), calendar: cal).currentStreak, 4)
        // Today (15th) has no entry yet: counts back from yesterday.
        XCTAssertEqual(try StatsParser.parse(d, today: date("2026-03-15"), calendar: cal).currentStreak, 4)
        // Two days without activity: streak is broken.
        XCTAssertEqual(try StatsParser.parse(d, today: date("2026-03-16"), calendar: cal).currentStreak, 0)
    }

    func testModelNames() {
        let table = [
            "claude-opus-5-5": "Opus 5.5", "claude-fable-5": "Fable 5", "claude-sonnet-5-5": "Sonnet 5.5",
            "claude-haiku-5-5": "Haiku 5.5", "claude-opus-4-8": "Opus 4.8",
            "claude-haiku-4-5-20251001": "Haiku 4.5",
            "gpt-x": "gpt-x", "claude-mystery": "claude-mystery", "": ""]
        for (id, want) in table { XCTAssertEqual(ModelName.display(id), want, id) }
    }

    func testTokenFormatting() {
        let table: [(Int, String)] = [(0, "0"), (999, "999"), (1000, "1K"), (752_156, "752K"), (999_499, "999K"),
                                      (999_500, "1M"), (1_000_000, "1M"), (12_345_678, "12.3M"),
                                      (1_000_000_000, "1B"), (1_234_567_890, "1.2B"),
                                      (2_500_000_000, "2.5B"), (-5, "0")]
        for (n, want) in table { XCTAssertEqual(TokenFormatter.string(n), want, "\(n)") }
    }

    func testDurationAndHour() {
        XCTAssertEqual(StatsParser.durationText(450_000_000), "5d 5h")
        XCTAssertEqual(StatsParser.durationText(5 * 3_600_000 + 20 * 60_000), "5h 20m")
        XCTAssertEqual(StatsParser.durationText(42 * 60_000), "42m")
        XCTAssertEqual([0, 10, 12, 15].map(StatsParser.hourText), ["12am", "10am", "12pm", "3pm"])
    }

    func testGarbageThrows() {
        for bad in ["not json", "[1,2,3]", "", "42"] {
            XCTAssertThrowsError(try StatsParser.parse(Data(bad.utf8), today: Date(), calendar: cal), bad)
        }
    }

    func testMissingKeysGivePartialSummary() throws {
        let s = try StatsParser.parse(Data(#"{"totalSessions":3,"dailyActivity":[{"date":"bad"},5],"hourCounts":{"x":1}}"#.utf8),
                                      today: date("2026-03-14"), calendar: cal)
        XCTAssertEqual(s.totalSessions, 3)
        XCTAssertNil(s.totalMessages)
        XCTAssertNil(s.todayMessages)
        XCTAssertNil(s.busiestHour)
        XCTAssertNil(s.longestSession)
        XCTAssertEqual(s.todayTokens, [])
        XCTAssertEqual(s.last7Days.map(\.tokens), Array(repeating: 0, count: 7))
        XCTAssertEqual(s.currentStreak, 0)
        let empty = try StatsParser.parse(Data("{}".utf8), today: date("2026-03-14"), calendar: cal)
        XCTAssertEqual(empty.last7Days.count, 7)
    }

    @MainActor func testStoreStates() throws {
        let data = try fixture()
        let ok = StatsStore(read: { data }, now: { Date() }, calendar: cal)
        ok.reload()
        if case .loaded = ok.state {} else { XCTFail("expected loaded") }
        let missing = StatsStore(read: { throw StatsReadError.missing })
        missing.reload()
        XCTAssertEqual(missing.state.message, "No stats yet. Run Claude Code once.")
        let bad = StatsStore(read: { Data("nope".utf8) })
        bad.reload()
        XCTAssertEqual(bad.state.message, "Stats format changed.")
    }
}
