import XCTest

final class SubagentLimitTests: XCTestCase {
    func testNewAndLegacyDefaultSettingsAllowTwentyWorkers() throws {
        XCTAssertEqual(AppSettings().maximumConcurrentSubagents, 20)
        for json in ["{}", #"{"maximumConcurrentSubagents":3}"#] {
            let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
            XCTAssertEqual(settings.maximumConcurrentSubagents, 20)
            XCTAssertTrue(settings.concurrentSubagentDefaultUpdated)
        }
    }

    func testExplicitLimitsSurviveMigrationAndRoundTrip() throws {
        for limit in [1, 2, 4, 8, 20] {
            let json = "{\"maximumConcurrentSubagents\":\(limit)}"
            let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
            XCTAssertEqual(settings.maximumConcurrentSubagents, limit)
        }
        var settings = AppSettings()
        settings.maximumConcurrentSubagents = 3
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.maximumConcurrentSubagents, 3)
    }

    func testDecodedLimitsAreClamped() throws {
        for (value, expected) in [(-1, 1), (0, 1), (21, 20), (Int.max, 20)] {
            let json = "{\"maximumConcurrentSubagents\":\(value)}"
            let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
            XCTAssertEqual(settings.maximumConcurrentSubagents, expected)
        }
    }

    @MainActor
    func testTwentyWorkersFitWithCompletedTabsAndTwentyFirstIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        var parent = ManagedSession(name: "Limit fixture", kind: .cli)
        parent.cliProfileID = "codex"
        parent.workingDirectory = directory.path
        store.addSession(parent, start: false)

        for index in 1...20 {
            let child = try store.delegateTask(
                from: parent.id, title: "Completed \(index)", instructions: "Fixture only", start: false)
            try store.reportSubagentResult(caller: child.id, summary: "Fixture complete", blocked: false)
        }
        for index in 1...20 {
            _ = try store.delegateTask(
                from: parent.id, title: "Active \(index)", instructions: "Fixture only", start: false)
        }
        XCTAssertEqual(store.sessions.filter { $0.parentSessionID == parent.id }.count, 40)
        XCTAssertEqual(store.tasks.filter { $0.status == .inProgress }.count, 20)
        XCTAssertThrowsError(
            try store.delegateTask(from: parent.id, title: "Overflow", instructions: "Rejected", start: false))
        XCTAssertEqual(store.tasks.count, 40)

        let completed = try XCTUnwrap(store.sessions.first { $0.parentSessionID == parent.id && $0.subagentCompleted })
        store.removeSession(completed.id)
        XCTAssertThrowsError(
            try store.delegateTask(
                from: parent.id, title: "Concurrent overflow", instructions: "Rejected", start: false))
        let active = try XCTUnwrap(store.sessions.first { $0.parentSessionID == parent.id && !$0.subagentCompleted })
        try store.reportSubagentResult(caller: active.id, summary: "Fixture complete", blocked: false)
        XCTAssertNoThrow(
            try store.delegateTask(from: parent.id, title: "Replacement", instructions: "Fixture only", start: false))
        XCTAssertEqual(store.focusedSessionID, parent.id)
    }
}
