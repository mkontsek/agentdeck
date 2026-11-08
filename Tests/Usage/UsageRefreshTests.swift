import XCTest

final class UsageRefreshTests: XCTestCase {
    func testKeychainInteractionIsRestoredOnFailureAndSuppressionIsMandatory() {
        var changes: [Bool] = []
        XCTAssertThrowsError(
            try NoninteractiveKeychain.withoutInteraction(
                getAllowed: { true },
                setAllowed: {
                    changes.append($0)
                    return true
                }, read: { throw UsageParseError.unavailable("Locked fixture") }))
        XCTAssertEqual(changes, [false, true])
        var read = false
        XCTAssertThrowsError(
            try NoninteractiveKeychain.withoutInteraction(
                getAllowed: { true }, setAllowed: { _ in false }, read: { read = true }))
        XCTAssertFalse(read)
    }

    private actor Reader {
        var calls = 0
        func credential() -> String {
            calls += 1
            return "fixture-\(calls)"
        }
        func snapshot(_ id: String) -> CLIUsageSnapshot {
            calls += 1
            return CLIUsageSnapshot(providerID: id, source: "fixture")
        }
    }

    private actor CancelledReader {
        var calls = 0
        func snapshot(_ id: String) throws -> CLIUsageSnapshot {
            calls += 1
            if calls == 1 { throw CancellationError() }
            return CLIUsageSnapshot(providerID: id, source: "fixture")
        }
    }

    @MainActor
    func testCancelledRefreshCanRetryImmediatelyAfterReopening() async {
        let reader = CancelledReader()
        let monitor = CLIUsageMonitor { try await reader.snapshot($0) }
        let now = Date()
        await monitor.refresh(["claude"], force: false, now: now)
        XCTAssertNil(monitor.snapshots["claude"])
        await monitor.refresh(["claude"], force: false, now: now.addingTimeInterval(1))
        XCTAssertNotNil(monitor.snapshots["claude"])
        XCTAssertFalse(monitor.refreshing)
        let calls = await reader.calls
        XCTAssertEqual(calls, 2)
    }

    func testCredentialsSurvivePanelReopeningButExpireAndInvalidate() async throws {
        let reader = Reader()
        let cache = UsageCredentialCache(lifetime: 60) { await reader.credential() }
        let start = Date(timeIntervalSince1970: 1000)
        let first = try await cache.token(now: start)
        let reopened = try await cache.token(now: start.addingTimeInterval(10))
        XCTAssertEqual(first, reopened)
        let expired = try await cache.token(now: start.addingTimeInterval(61))
        XCTAssertNotEqual(first, expired)
        await cache.invalidate()
        let refreshed = try await cache.token(now: start.addingTimeInterval(62))
        XCTAssertNotEqual(expired, refreshed)
        let calls = await reader.calls
        XCTAssertEqual(calls, 3)
    }

    @MainActor
    func testReopeningUsesFreshSamplesAndManualRefreshStillWorks() async {
        let reader = Reader()
        let monitor = CLIUsageMonitor { await reader.snapshot($0) }
        let now = Date()
        await monitor.refresh(["claude"], force: false, now: now)
        await monitor.refresh(["claude"], force: false, now: now.addingTimeInterval(5))
        var calls = await reader.calls
        XCTAssertEqual(calls, 1)
        await monitor.refresh(["claude"], force: false, now: now.addingTimeInterval(61))
        await monitor.refresh(["claude"], force: true, now: now.addingTimeInterval(62))
        calls = await reader.calls
        XCTAssertEqual(calls, 3)
    }
}
