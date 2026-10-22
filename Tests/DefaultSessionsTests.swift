import XCTest

final class DefaultSessionsTests: XCTestCase {
    func testDefaultsPreferOneInterfacePerProvider() {
        let sessions = DefaultSessions.make(profiles: CLIProfile.builtins, workingDirectory: "/tmp/example")
        let cli = sessions.filter { $0.kind == .cli }
        XCTAssertEqual(
            Set(cli.compactMap(\.cliProfileID)), ["claude", "codex", "antigravity", "grok"])
        XCTAssertTrue(cli.allSatisfy { $0.workingDirectory == "/tmp/example" })
        XCTAssertEqual(sessions.filter { $0.kind == .browser }.map(\.url), [BrowserPreset.perplexity.url])
        XCTAssertEqual(Set(sessions.map(\.id)).count, sessions.count)
        XCTAssertEqual(
            CLIProfile.builtins.first { $0.id == "antigravity" }?.command, "agy --dangerously-skip-permissions")
    }

    func testDefaultsFallBackToGeminiCLIThenBrowsers() {
        let profiles = CLIProfile.builtins.filter { $0.id != "antigravity" }
        let sessions = DefaultSessions.make(profiles: profiles, workingDirectory: "/tmp/example")
        XCTAssertTrue(sessions.contains { $0.cliProfileID == "gemini" })
        XCTAssertFalse(sessions.contains { $0.url == BrowserPreset.gemini.url })
        let browsers = DefaultSessions.make(profiles: [], workingDirectory: "/tmp/example")
        XCTAssertEqual(browsers.count, 5)
        XCTAssertTrue(browsers.allSatisfy { $0.kind == .browser })
    }

    @MainActor
    func testDefaultSessionSeedingIsIdempotentAndPersists() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("state.json")
        let store = AppStore(stateURL: url)
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        store.openDefaultSessions(start: false)
        let ids = store.sessions.map(\.id)
        XCTAssertEqual(ids.count, 5)
        XCTAssertFalse(store.runtime.values.contains { $0.isRunning })
        store.openDefaultSessions(start: false)
        XCTAssertEqual(store.sessions.map(\.id), ids)
        store.saveNow()
        let restored = AppStore(stateURL: url)
        defer { restored.shutdown() }
        restored.openDefaultSessions(start: false)
        XCTAssertEqual(restored.sessions.map(\.id), ids)
    }

    func testOlderSettingsReceiveDefaultsWithoutOverwritingChoices() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{\"globalFontSize\":17}".utf8))
        XCTAssertTrue(old.openDefaultsWhenEmpty)
        XCTAssertEqual(old.globalFontSize, 17)
        XCTAssertTrue(old.skillDirectories.contains("~/gitrepos"))
        var settings = old
        settings.openDefaultsWhenEmpty = false
        settings.skillDirectories = []
        settings.disabledSkillIDs = ["chosen"]
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertFalse(restored.openDefaultsWhenEmpty)
        XCTAssertTrue(restored.skillDirectories.isEmpty)
        XCTAssertEqual(restored.disabledSkillIDs, ["chosen"])
    }

    @MainActor
    func testCorruptStateDoesNotSpawnDefaultAgents() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        try Data("broken".utf8).write(to: url)
        let store = AppStore(stateURL: url)
        store.openDefaultSessions(start: false)
        XCTAssertTrue(store.sessions.isEmpty)
        store.shutdown()
    }
}
