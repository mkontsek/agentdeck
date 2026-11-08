import XCTest

final class CLIUsageTests: XCTestCase {
    func testCodexBucketsDoNotDoubleCountLegacyView() throws {
        let response = Data(
            #"{"result":{"rateLimits":{"primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1900000000},"secondary":{"usedPercent":60,"windowDurationMins":10080,"resetsAt":1900200000}}},"rateLimitResetCredits":{"availableCount":2}}}"#
                .utf8)
        let result = try UsageParser.codex(response)
        XCTAssertEqual(result.windows.map(\.usedPercent), [25, 60])
        XCTAssertEqual(result.windows.first?.label, "codex · 5 hours")
        XCTAssertEqual(result.windows.first?.resetsAt, Date(timeIntervalSince1970: 1_900_000_000))
        XCTAssertEqual(result.detail, "2 earned resets available")
    }

    func testClaudeMissingAndFractionalResetDates() throws {
        let response = Data(
            #"{"five_hour":{"utilization":42,"resets_at":"2026-10-28T12:30:00.123Z"},"seven_day":{"utilization":15,"resets_at":null},"seven_day_opus":null}"#
                .utf8)
        let result = try UsageParser.claude(response)
        XCTAssertEqual(result.windows.count, 2)
        XCTAssertEqual(result.windows.first?.usedPercent, 42)
        XCTAssertNotNil(result.windows.first?.resetsAt)
        XCTAssertNil(result.windows.last?.resetsAt)
    }

    func testUnknownOrInvalidQuotaIsNotZeroUsage() {
        XCTAssertThrowsError(try UsageParser.codex(Data(#"{"rateLimits":null}"#.utf8)))
        XCTAssertThrowsError(try UsageParser.claude(Data(#"{"five_hour":{"utilization":-10}}"#.utf8)))
        XCTAssertThrowsError(try UsageParser.claude(Data(#"{"five_hour":{"utilization":101}}"#.utf8)))
    }

    func testGeminiUsesRemainingFractionWithoutInventingAbsoluteLimit() throws {
        let response = Data(
            #"{"buckets":[{"modelId":"gemini-pro","remainingFraction":0.75,"remainingAmount":"30","resetTime":"2026-10-29T00:00:00Z"}]}"#
                .utf8)
        let snapshot = try UsageParser.gemini(response)
        XCTAssertEqual(snapshot.windows.first?.usedPercent, 25)
        XCTAssertEqual(snapshot.windows.first?.limit, "30 units remaining")
        XCTAssertNotNil(snapshot.windows.first?.resetsAt)
    }

    @MainActor
    func testUnavailableRefreshRetainsLastKnownDataAsStale() async {
        actor Reader {
            var count = 0
            func read(_ id: String) throws -> CLIUsageSnapshot {
                count += 1
                if count > 1 { throw UsageParseError.unavailable("Offline") }
                return CLIUsageSnapshot(
                    providerID: id, windows: [UsageWindow(id: "week", label: "Week", usedPercent: 45)],
                    observedAt: Date(), source: "fixture")
            }
        }
        let reader = Reader()
        let monitor = CLIUsageMonitor { try await reader.read($0) }
        await monitor.refresh(["codex"])
        let observed = monitor.snapshots["codex"]?.observedAt
        await monitor.refresh(["codex"])
        XCTAssertEqual(monitor.snapshots["codex"]?.windows.first?.usedPercent, 45)
        XCTAssertEqual(monitor.snapshots["codex"]?.observedAt, observed)
        XCTAssertEqual(monitor.snapshots["codex"]?.error, "Offline")
        XCTAssertFalse(monitor.refreshing)
    }
}
