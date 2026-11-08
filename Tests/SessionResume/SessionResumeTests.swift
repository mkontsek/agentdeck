import AppKit
import XCTest

final class SessionResumeTests: XCTestCase {
    @MainActor
    func testRestartUsesEachTabsOwnConversationAndPreservesOptOut() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let stateURL = directory.appendingPathComponent("state.json")
        let store = AppStore(stateURL: stateURL)
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        var original = ManagedSession(name: "Codex", kind: .cli)
        original.cliProfileID = "codex"
        original.workingDirectory = directory.path
        store.addSession(original, start: false)
        let tab = try XCTUnwrap(store.addCLITab(to: original.id, start: false))
        XCTAssertFalse(tab.resumeLastConversation)
        XCTAssertTrue(tab.resumeOnRestart)
        XCTAssertFalse(store.shouldResume(tab))
        let firstID = try checkpoint(original, store: store, directory: directory)
        let secondID = try checkpoint(tab, store: store, directory: directory)
        store.saveNow()
        let restored = AppStore(stateURL: stateURL)
        defer { restored.shutdown() }
        for (sessionID, conversationID) in [(original.id, firstID), (tab.id, secondID)] {
            var session = try XCTUnwrap(restored.session(sessionID))
            XCTAssertTrue(restored.shouldResume(session))
            let command = restored.launchCommand(for: session)
            XCTAssertTrue(command.contains("resume '\(conversationID)'"))
            XCTAssertFalse(command.contains("--last"))
            XCTAssertTrue(command.contains(restored.mcpURL(for: session.id)))
            session.resumeOnRestart = false
            XCTAssertFalse(restored.shouldResume(session))
            XCTAssertFalse(restored.launchCommand(for: session).contains("resume"))
        }
        XCTAssertNotEqual(firstID, secondID)
    }

    @MainActor
    func testMissingConversationChangedDirectoryAndCustomCommandsDoNotGuess() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        var session = ManagedSession(name: "Claude", kind: .cli)
        session.cliProfileID = "claude"
        session.workingDirectory = directory.path
        session.resumeLastConversation = false
        store.addSession(session, start: false)
        let id = try checkpoint(session, store: store, directory: directory)
        XCTAssertTrue(store.launchCommand(for: session).contains("--resume '\(id)'"))
        var moved = session
        moved.workingDirectory = directory.appendingPathComponent("different").path
        XCTAssertFalse(store.shouldResume(moved))
        try FileManager.default.removeItem(at: directory.appendingPathComponent("\(id).jsonl"))
        XCTAssertFalse(store.shouldResume(session))
        let index = try XCTUnwrap(store.cliProfiles.firstIndex { $0.id == "claude" })
        store.cliProfiles[index].command += " --model custom"
        _ = try checkpoint(session, store: store, directory: directory)
        XCTAssertNil(store.cliProfiles[index].exactResumeCommand)
        XCTAssertFalse(store.shouldResume(session), "A customised launch must not silently adopt built-in resume flags")
        store.cliProfiles[index].resumeCommand = "custom --continue {conversationId}"
        XCTAssertTrue(store.shouldResume(session))
        XCTAssertTrue(store.launchCommand(for: session).hasPrefix("custom --continue '"))
        store.removeSession(session.id)
        XCTAssertNil(ResumeCheckpointStorage.read(id: session.id, directory: store.resumeDirectory))
    }

    @MainActor
    func testSavedNewTabsResumeAutomaticallyAtBootstrapWithoutLaunchingProviders() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let stateURL = directory.appendingPathComponent("state.json")
        let store = AppStore(stateURL: stateURL)
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        store.settings.openDefaultsWhenEmpty = false
        store.settings.skillDirectories = []
        store.settings.mcpPort = 0
        store.cliProfiles.append(
            CLIProfile(
                id: "resume-fixture", name: "Fixture", command: "printf fresh > {cwd}/fresh-{sessionId}.txt",
                resumeCommand: "printf '%s' {conversationId} > {cwd}/resumed-{sessionId}.txt", supportsMCP: false))
        var first = ManagedSession(name: "First", kind: .cli)
        first.cliProfileID = "resume-fixture"
        first.workingDirectory = directory.path
        first.initialPrompt = "Do not repeat this original task"
        store.addSession(first, start: false)
        let tab = try XCTUnwrap(store.addCLITab(to: first.id, start: false))
        var stopped = ManagedSession(name: "Manual", kind: .cli)
        stopped.cliProfileID = first.cliProfileID
        stopped.workingDirectory = directory.path
        stopped.autoStart = false
        store.addSession(stopped, start: false)
        let ids = [
            first.id: try checkpoint(first, store: store, directory: directory),
            tab.id: try checkpoint(tab, store: store, directory: directory),
        ]
        store.saveNow()
        let restored = AppStore(stateURL: stateURL)
        defer { restored.shutdown() }
        restored.bootstrap()
        for _ in 0..<500 {
            if ids.keys.allSatisfy({
                FileManager.default.fileExists(atPath: directory.appendingPathComponent("resumed-\($0).txt").path)
            }) {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        for (id, conversationID) in ids {
            XCTAssertEqual(
                try String(contentsOf: directory.appendingPathComponent("resumed-\(id).txt"), encoding: .utf8),
                conversationID)
            XCTAssertTrue(restored.runtime[id]?.resumed == true)
            XCTAssertTrue(restored.runtime[id]?.restoredLaunch == true)
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: directory.appendingPathComponent("fresh-\(id).txt").path))
        }
        XCTAssertFalse(restored.terminals.isRunning(stopped.id))
        await restored.prepareSessionRestoration()
        XCTAssertNil(restored.resumeTrackingTask)
    }

    func testLegacySessionDefaultsToResumingOnRestartAndGrokAdoptsResume() throws {
        let session = try JSONDecoder().decode(
            ManagedSession.self, from: Data(#"{"name":"Old tab","kind":"cli","resumeLastConversation":false}"#.utf8))
        XCTAssertTrue(session.resumeOnRestart)
        XCTAssertFalse(session.resumeLastConversation)
        let grok = CLIProfile(id: "grok", name: "Grok", command: "grok --always-approve")
            .adoptingBriefingAndResumeDefaults()
        XCTAssertEqual(grok.resumeCommand, "grok --continue --always-approve --rules {briefing}")
        XCTAssertEqual(grok.exactResumeCommand, "grok --resume {conversationId} --always-approve --rules {briefing}")
    }

    @MainActor
    func testInitialTaskIsNotReplayedWhenRestorationFallsBackToFresh() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        var session = ManagedSession(name: "Codex", kind: .cli)
        session.cliProfileID = "codex"
        session.initialPrompt = "Run the initial task only once"
        store.addSession(session, start: false)
        XCTAssertTrue(store.initialMessage(for: session)?.contains("Run the initial task only once") == true)
        store.runtime[session.id]?.restoredLaunch = true
        XCTAssertFalse(store.initialMessage(for: session)?.contains("Run the initial task only once") == true)
        XCTAssertNil(store.initialMessage(for: session), "Persistent launch instructions need no typed pointer")
        store.runtime[session.id]?.resumed = true
        XCTAssertNil(store.initialMessage(for: session))
    }

    @MainActor
    func testBrowserRestoresLastPageIncludingClientSideNavigation() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let stateURL = directory.appendingPathComponent("state.json")
        let store = AppStore(stateURL: stateURL)
        var browser = ManagedSession(name: "Web conversation", kind: .browser)
        browser.url = "about:blank"
        browser.browserProfileMode = .isolated
        store.addSession(browser)
        defer {
            store.shutdown()
            BrowserHost.deleteProfile(browser.browserProfileID)
            try? FileManager.default.removeItem(at: directory)
        }
        let controller = try XCTUnwrap(store.browsers.controllers[browser.id])
        let error = await controller.navigate("data:text/html,<title>Fixture</title>Saved%20conversation")
        XCTAssertNil(error)
        _ = await controller.evaluate("location.hash = 'conversation-42'")
        for _ in 0..<100 where store.session(browser.id)?.url?.hasSuffix("#conversation-42") != true {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(store.session(browser.id)?.url?.hasSuffix("#conversation-42") == true)
        await store.prepareSessionRestoration()
        let restored = AppStore(stateURL: stateURL)
        defer { restored.shutdown() }
        XCTAssertEqual(restored.session(browser.id)?.url, controller.webView.url?.absoluteString)
        XCTAssertEqual(restored.session(browser.id)?.browserProfileID, browser.browserProfileID)
    }

    @MainActor
    private func checkpoint(_ session: ManagedSession, store: AppStore, directory: URL) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID().uuidString.lowercased()
        let transcript = directory.appendingPathComponent("\(id).jsonl")
        try Data("fixture; must not be parsed".utf8).write(to: transcript)
        store.saveResumeCheckpoint(
            SessionResumeCheckpoint(
                profileID: session.cliProfileID ?? "", directory: session.effectiveDirectory.expandingTilde,
                launchedAt: Date(), conversationID: id, conversationPath: transcript.path), for: session.id)
        return id
    }
}
