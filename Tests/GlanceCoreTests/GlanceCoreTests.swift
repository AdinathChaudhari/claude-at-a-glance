import XCTest
@testable import GlanceCore

final class GlanceCoreTests: XCTestCase {
    func testFixtureIsBundled() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "usage-sample", withExtension: "json"))
        let data = try Data(contentsOf: url)
        XCTAssertFalse(data.isEmpty)
    }
}
