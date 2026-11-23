import XCTest
@testable import GlanceCore

final class Box: @unchecked Sendable {
    var fetchCalls = 0
    var result: Result<Data, Error> = .success(Data())
    var expiresAt: Date?
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

@MainActor
final class StoreTests: XCTestCase {
    private func sample() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "usage-sample", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func make(_ box: Box) -> UsageStore {
        UsageStore(
            readCredentials: { Credentials(accessToken: "t", expiresAt: box.expiresAt) },
            fetch: { _ in box.fetchCalls += 1; return try box.result.get() },
            now: { box.now }
        )
    }

    func testExpiredTokenSkipsNetwork() async {
        let box = Box()
        box.expiresAt = box.now.addingTimeInterval(-10)
        let store = make(box)
        await store.refresh()
        XCTAssertEqual(store.status, .loginExpired)
        XCTAssertEqual(store.message, "Login expired. Open Claude Code to refresh.")
        XCTAssertEqual(box.fetchCalls, 0)
    }

    func testRateLimitedBacksOffThenRecovers() async throws {
        let box = Box()
        box.result = .failure(UsageFetchError.rateLimited)
        let store = make(box)
        await store.refresh()
        XCTAssertEqual(store.nextInterval, 300)
        await store.refresh()
        XCTAssertEqual(store.nextInterval, 600)
        await store.refresh()
        await store.refresh()
        XCTAssertEqual(store.nextInterval, 1200)

        box.result = .success(try sample())
        await store.refresh()
        XCTAssertEqual(store.nextInterval, 300)
        XCTAssertEqual(store.status, .ok)
        XCTAssertNil(store.message)
        XCTAssertFalse(store.limits.isEmpty)
    }

    func testLastValuesKeptOnError() async throws {
        let box = Box()
        box.result = .success(try sample())
        let store = make(box)
        await store.refresh()
        let before = store.limits
        let stamp = store.lastUpdated
        XCTAssertFalse(before.isEmpty)

        box.now = box.now.addingTimeInterval(60)
        box.result = .failure(UsageFetchError.offline)
        await store.refresh()
        XCTAssertEqual(store.status, .offline)
        XCTAssertEqual(store.limits, before)
        XCTAssertEqual(store.lastUpdated, stamp)
        XCTAssertFalse(store.menuBarTitle.hasSuffix("⚠"))
        XCTAssertEqual(store.nextInterval, 300)
    }

    func testTransientErrorWithFreshDataIsNotDimmed() async throws {
        let box = Box()
        box.result = .success(try sample())
        let store = make(box)
        await store.refresh()
        box.now = box.now.addingTimeInterval(60)
        box.result = .failure(UsageFetchError.rateLimited)
        await store.refresh()
        XCTAssertTrue(store.isErroring)
        XCTAssertFalse(store.isStale)
        XCTAssertTrue(store.valuesTrusted)
        XCTAssertNil(store.message)
        XCTAssertFalse(store.menuBarTitle.contains("⚠"))
        XCTAssertTrue(store.footerText(timeZone: TimeZone(identifier: "UTC")!).hasSuffix("retrying"))
    }

    func testTransientErrorWithOldDataIsDimmed() async throws {
        let box = Box()
        box.result = .success(try sample())
        let store = make(box)
        await store.refresh()
        box.now = box.now.addingTimeInterval(16 * 60)
        box.result = .failure(UsageFetchError.offline)
        await store.refresh()
        XCTAssertTrue(store.isStale)
        XCTAssertFalse(store.valuesTrusted)
        XCTAssertEqual(store.message, "Offline, retrying.")
        XCTAssertTrue(store.menuBarTitle.hasSuffix("⚠"))
        XCTAssertFalse(store.footerText().contains("retrying"))
    }

    private func staleAfterOffline(_ seconds: TimeInterval) async throws -> UsageStore {
        let box = Box()
        box.result = .success(try sample())
        let store = make(box)
        await store.refresh()
        box.now = box.now.addingTimeInterval(seconds)
        box.result = .failure(UsageFetchError.offline)
        await store.refresh()
        return store
    }

    func testStaleThresholdIsFifteenMinutes() async throws {
        XCTAssertEqual(UsageStore.staleAfter, 900)
        let at14 = try await staleAfterOffline(14 * 60)
        XCTAssertFalse(at14.isStale)
        let at15 = try await staleAfterOffline(15 * 60)
        XCTAssertFalse(at15.isStale)
        let over = try await staleAfterOffline(15 * 60 + 1)
        XCTAssertTrue(over.isStale)
    }

    func testLoginExpiredWithFreshDataIsDimmedWithMessage() async throws {
        let box = Box()
        box.result = .success(try sample())
        let store = make(box)
        await store.refresh()
        box.now = box.now.addingTimeInterval(30)
        box.result = .failure(UsageFetchError.unauthorized)
        await store.refresh()
        XCTAssertTrue(store.isStale)
        XCTAssertEqual(store.message, "Login expired. Open Claude Code to refresh.")
        XCTAssertTrue(store.menuBarTitle.hasSuffix("⚠"))
    }

    func testPollIntervalIsFiveMinutes() {
        XCTAssertEqual(UsageStore.pollInterval, 300)
        XCTAssertEqual(make(Box()).nextInterval, 300)
    }

    func testManualRefreshDebounced() async throws {
        let box = Box()
        box.result = .success(try sample())
        let store = make(box)
        await store.manualRefresh()
        await store.manualRefresh()
        XCTAssertEqual(box.fetchCalls, 1)
        box.now = box.now.addingTimeInterval(11)
        await store.manualRefresh()
        XCTAssertEqual(box.fetchCalls, 2)
    }
}
