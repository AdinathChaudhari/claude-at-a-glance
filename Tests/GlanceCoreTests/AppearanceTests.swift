import XCTest
@testable import GlanceCore

final class AppearanceTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "appearance-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testDefaultIsSystem() {
        XCTAssertEqual(AppearanceChoice.load(from: freshDefaults()), .system)
    }

    func testRoundTrip() {
        let d = freshDefaults()
        for choice in AppearanceChoice.allCases {
            choice.save(to: d)
            XCTAssertEqual(AppearanceChoice.load(from: d), choice)
        }
    }

    func testUnknownValueFallsBackToSystem() {
        let d = freshDefaults()
        d.set("sepia", forKey: "appearance")
        XCTAssertEqual(AppearanceChoice.load(from: d), .system)
    }

    func testTitles() {
        XCTAssertEqual(AppearanceChoice.allCases.map(\.title), ["System", "Light", "Dark"])
    }
}
