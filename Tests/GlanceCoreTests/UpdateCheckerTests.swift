import XCTest
@testable import GlanceCore

final class UpdateCheckerTests: XCTestCase {
    func testParseLatest() throws {
        let json = #"{"tag_name":"v0.2.0","html_url":"https://github.com/AdinathChaudhari/claude-at-a-glance/releases/tag/v0.2.0","name":"x"}"#
        let info = try XCTUnwrap(UpdateChecker.parseLatest(Data(json.utf8)))
        XCTAssertEqual(info.version, "0.2.0")
        XCTAssertEqual(info.url.absoluteString, "https://github.com/AdinathChaudhari/claude-at-a-glance/releases/tag/v0.2.0")
    }

    func testParseLatestRejectsBadInput() {
        XCTAssertNil(UpdateChecker.parseLatest(Data("not json".utf8)))
        XCTAssertNil(UpdateChecker.parseLatest(Data(#"{"message":"Not Found"}"#.utf8)))
        XCTAssertNil(UpdateChecker.parseLatest(Data(#"{"tag_name":"v1","html_url":"javascript:alert(1)"}"#.utf8)))
    }

    func testIsNewerTable() {
        let cases: [(String, String, Bool)] = [
            ("0.2.0", "0.1.0", true),
            ("0.1.0", "0.2.0", false),
            ("0.10.0", "0.9.0", true),
            ("0.9.0", "0.10.0", false),
            ("v0.2.0", "0.1.0", true),
            ("0.2.0", "v0.1.0", true),
            ("0.1.0", "0.1.0", false),
            ("1.0", "1.0.0", false),
            ("1.0.1", "1.0", true),
            ("1.0.0-beta.1", "1.0.0", false),
            ("1.1.0-beta.1", "1.0.0", true),
            ("garbage", "0.1.0", false),
            ("0.2.0", "garbage", false),
            ("", "0.1.0", false),
            ("1..2", "0.1.0", false),
        ]
        for (remote, local, expected) in cases {
            XCTAssertEqual(UpdateChecker.isNewer(remote, than: local), expected, "\(remote) vs \(local)")
        }
    }
}

@MainActor
final class UpdateStoreTests: XCTestCase {
    private let info = ReleaseInfo(version: "0.2.0", url: URL(string: "https://example.com/r")!)

    func testNewerReleaseSetsUpdate() async {
        let info = self.info
        let store = UsageStore()
        await store.runUpdateCheck(localVersion: "0.1.0") { info }
        XCTAssertEqual(store.availableUpdate, info)
    }

    func testSameOrNilClearsUpdate() async {
        let info = self.info
        let store = UsageStore()
        await store.runUpdateCheck(localVersion: "0.1.0") { info }
        await store.runUpdateCheck(localVersion: "0.2.0") { info }
        XCTAssertNil(store.availableUpdate)
        await store.runUpdateCheck(localVersion: "0.1.0") { nil }
        XCTAssertNil(store.availableUpdate)
    }
}
