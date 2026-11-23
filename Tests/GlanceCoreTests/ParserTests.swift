import XCTest
@testable import GlanceCore

final class ParserTests: XCTestCase {
    private func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "usage-sample", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func testFixtureParsesThreeLimits() throws {
        let limits = try UsageParser.parse(try fixture())
        XCTAssertEqual(limits.count, 3)
        XCTAssertEqual(limits.map(\.label), ["Current session", "Current week (all models)", "Current week (Fable)"])
        XCTAssertEqual(limits.map(\.percent), [42, 67, 5])
        XCTAssertEqual(limits.map(\.kind), [.session, .weeklyAll, .weeklyScoped])
        XCTAssertEqual(Set(limits.map(\.id)).count, 3)
        let reset = try XCTUnwrap(limits[0].resetsAt)
        XCTAssertEqual(reset.timeIntervalSince1970, 1_795_425_000.391, accuracy: 0.01)
    }

    func testLegacyFallbackWhenLimitsMissing() throws {
        let json = #"{"five_hour":{"utilization":80.5,"resets_at":"2026-11-23T09:10:00Z"},"seven_day":{"utilization":10,"resets_at":null}}"#
        let limits = try UsageParser.parse(Data(json.utf8))
        XCTAssertEqual(limits.map(\.label), ["Current session", "Current week (all models)"])
        XCTAssertEqual(limits[0].percent, 80.5)
        XCTAssertEqual(limits[0].severity, .warning)
        XCTAssertNotNil(limits[0].resetsAt)
        XCTAssertNil(limits[1].resetsAt)
        XCTAssertEqual(limits[1].severity, .normal)
    }

    func testEmptyLimitsArrayFallsBack() throws {
        let json = #"{"limits":[],"five_hour":{"utilization":95}}"#
        let limits = try UsageParser.parse(Data(json.utf8))
        XCTAssertEqual(limits.count, 1)
        XCTAssertEqual(limits[0].severity, .critical)
    }

    func testMalformedElementDoesNotBlankOthers() throws {
        let json = #"""
        {"limits":[
          {"kind":"session","percent":"oops","severity":"normal"},
          7,
          {"kind":"weekly_all","percent":30,"severity":"normal","resets_at":null}
        ]}
        """#
        let limits = try UsageParser.parse(Data(json.utf8))
        XCTAssertEqual(limits.count, 1)
        XCTAssertEqual(limits[0].kind, .weeklyAll)
    }

    func testPercentOver100Preserved() throws {
        let json = #"{"limits":[{"kind":"session","percent":120,"severity":"critical","resets_at":null}]}"#
        XCTAssertEqual(try UsageParser.parse(Data(json.utf8))[0].percent, 120)
    }

    func testNullResetsAtIsNil() throws {
        let json = #"{"limits":[{"kind":"session","percent":1,"severity":"normal","resets_at":null}]}"#
        XCTAssertNil(try UsageParser.parse(Data(json.utf8))[0].resetsAt)
    }

    func testUnknownSeverityUsesThresholds() throws {
        let json = #"""
        {"limits":[
          {"kind":"session","percent":90,"severity":"bananas"},
          {"kind":"weekly_all","percent":75,"severity":"bananas"},
          {"kind":"weekly_scoped","percent":74,"severity":"bananas"}
        ]}
        """#
        let limits = try UsageParser.parse(Data(json.utf8))
        XCTAssertEqual(limits.map(\.severity), [.critical, .warning, .normal])
        XCTAssertEqual(limits[2].label, "Current week (scoped)")
    }

    func testGarbageThrowsFormatChanged() {
        for s in ["not json", "[]", "{}", #"{"limits":[{"kind":"future","percent":1}]}"#] {
            XCTAssertThrowsError(try UsageParser.parse(Data(s.utf8))) {
                XCTAssertEqual($0 as? UsageParseError, .formatChanged)
            }
        }
    }

    func testCredentialPayloadParsing() throws {
        let json = #"{"claudeAiOauth":{"accessToken":"abc","expiresAt":1795338600000}}"#
        let c = try CredentialReader.parse(Data(json.utf8))
        XCTAssertEqual(c.accessToken, "abc")
        XCTAssertEqual(c.expiresAt, Date(timeIntervalSince1970: 1_795_338_600))
        let hex = Data(json.utf8).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(try CredentialReader.parse(Data(hex.utf8)).accessToken, "abc")
        XCTAssertThrowsError(try CredentialReader.parse(Data("{}".utf8)))
    }

    /// Live Keychain gate. Opt-in: GLANCE_LIVE_CREDS=1 swift test --filter testLiveCredentialRead
    /// Prints only token length and whether expiry is in the future, never the token.
    func testLiveCredentialRead() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GLANCE_LIVE_CREDS"] == "1")
        let c = try CredentialReader.read()
        print("GATE token length=\(c.accessToken.count) expiresAtInFuture=\(c.expiresAt.map { $0 > Date() } ?? false)")
    }
}
