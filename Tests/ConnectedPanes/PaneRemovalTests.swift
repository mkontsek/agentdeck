import AppKit
import WebKit
import XCTest

@MainActor
final class PaneRemovalTests: XCTestCase {
    private func fixture() throws -> (AppStore, ManagedSession, ManagedSession, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        var owner = ManagedSession(name: "Window owner", kind: .cli)
        owner.cliProfileID = "codex"
        owner.workingDirectory = directory.path
        owner = store.addSession(owner, start: false)
        var browser = ManagedSession(name: "Selected browser", kind: .browser)
        browser.agentOwnerID = owner.id
        browser = store.addSession(browser, start: false)
        return (store, owner, browser, directory)
    }

    private func cleanup(_ store: AppStore, _ directory: URL) {
        store.shutdown()
        try? FileManager.default.removeItem(at: directory)
    }

    func testBrowserSelectedHeaderRemovalClosesEveryTabAndRetainsOtherWindow() throws {
        let (store, owner, browser, directory) = try fixture()
        defer { cleanup(store, directory) }
        let cli = try XCTUnwrap(store.addCLITab(to: owner.id, start: false))
        let browserTab = try XCTUnwrap(store.addBrowserTab(to: browser.id, start: false))
        let other = store.addSession(ManagedSession(name: "Other window", kind: .cli), start: false)
        store.selectTab(browserTab.id)
        store.maximizedSessionID = browserTab.id
        let marker = directory.appendingPathComponent("provider-history-fixture.txt")
        try Data("retained history".utf8).write(to: marker)
        store.removeMiniWindow(containing: browserTab.id)
        for id in [owner.id, cli.id, browser.id, browserTab.id] { XCTAssertNil(store.session(id)) }
        XCTAssertEqual(store.sessions.map(\.id), [other.id])
        XCTAssertNil(store.selectedPaneTabs[owner.paneID])
        XCTAssertNil(store.maximizedSessionID)
        XCTAssertEqual(store.focusedSessionID, other.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        store.saveNow()
        let restored = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer { restored.shutdown() }
        XCTAssertEqual(restored.sessions.map(\.id), [other.id])
    }

    func testSingleTabCloseStillRetainsOwnerAndSiblingBrowser() throws {
        let (store, owner, browser, directory) = try fixture()
        defer { cleanup(store, directory) }
        let sibling = try XCTUnwrap(store.addBrowserTab(to: browser.id, start: false))
        store.removeSession(browser.id)
        XCTAssertNotNil(store.session(owner.id))
        XCTAssertNotNil(store.session(sibling.id))
        XCTAssertEqual(store.panes.count, 1)
    }

    func testBrowserOnlyWindowRemovalClosesAllTabs() throws {
        let (store, owner, browser, directory) = try fixture()
        defer { cleanup(store, directory) }
        store.removeSession(owner.id)
        XCTAssertNil(store.session(browser.id))
        let standalone = store.addSession(ManagedSession(name: "Browser window", kind: .browser), start: false)
        let sibling = try XCTUnwrap(store.addBrowserTab(to: standalone.id, start: false))
        store.removeMiniWindow(containing: sibling.id)
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertNil(store.focusedSessionID)
        XCTAssertTrue(store.panes.isEmpty)
    }

    func testClosingParentWindowPreservesIndependentWorkerAndItsTask() throws {
        let (store, owner, browser, directory) = try fixture()
        defer { cleanup(store, directory) }
        let child = try store.delegateTask(
            from: owner.id, title: "Independent work", instructions: "Fixture", start: false)
        let task = try XCTUnwrap(store.tasks.first)
        store.removeMiniWindow(containing: browser.id)
        let remaining = try XCTUnwrap(store.session(child.id))
        XCTAssertNil(remaining.parentSessionID)
        XCTAssertNil(remaining.delegatedTaskID)
        XCTAssertEqual(store.tasks.first?.ownerSessionID, child.id)
        XCTAssertEqual(store.tasks.first?.status, task.status)
        XCTAssertEqual(store.sessions.map(\.id), [child.id])
    }

    func testReservedContinuationPreventsPartialWindowRemoval() throws {
        for phase in [WorkerResumePhase.checking, .queued, .started, .uncertain] {
            let (store, owner, browser, directory) = try fixture()
            defer { cleanup(store, directory) }
            let child = try store.delegateTask(
                from: owner.id, title: "Protected work", instructions: "Fixture", start: false)
            var childBrowser = ManagedSession(name: "Worker browser", kind: .browser)
            childBrowser.agentOwnerID = child.id
            childBrowser = store.addSession(childBrowser, start: false)
            let request = WorkerResumeRequest(
                id: UUID(), workerID: child.id, parentID: owner.id, taskID: child.delegatedTaskID!,
                taskRevision: store.tasks[0].revision, generation: 0, conversationID: UUID().uuidString,
                directory: directory.path, instructions: "Reserved", phase: phase)
            try store.workerResumes.put(request)
            let before = store.sessions
            let selection = store.selectedPaneTabs
            for target in [browser.id, childBrowser.id] {
                store.removeMiniWindow(containing: target)
                XCTAssertEqual(store.sessions, before, "No tab may close before a continuation guard rejects removal")
                XCTAssertEqual(store.selectedPaneTabs, selection)
                XCTAssertNotNil(store.lastError)
                XCTAssertEqual(store.tasks.first?.ownerSessionID, child.id)
            }
        }
    }

    func testRemovalDisposesNativeHostsButRetainsIsolatedBrowserCookies() async throws {
        _ = NSApplication.shared
        for browserSelected in [false, true] {
            let (store, owner, browser, directory) = try fixture()
            defer {
                cleanup(store, directory)
                BrowserHost.deleteProfile(browser.browserProfileID)
            }
            let profile = CLIProfile(
                id: "remove-fixture", name: "Fixture", command: "exec /bin/cat", supportsMCP: false)
            store.cliProfiles.append(profile)
            var cli = owner
            cli.cliProfileID = profile.id
            cli.resumeLastConversation = false
            store.updateSession(cli)
            var separate = browser
            separate.browserProfileMode = .isolated
            separate.url = "about:blank"
            store.updateSession(separate)
            store.startSession(owner.id)
            store.startSession(browser.id)
            XCTAssertTrue(store.terminals.isRunning(owner.id))
            let data = try XCTUnwrap(store.browsers.controllers[browser.id]?.webView.configuration.websiteDataStore)
            let cookie = try XCTUnwrap(
                HTTPCookie(properties: [
                    .domain: "agentdeck.test", .path: "/", .name: "remove-window-fixture", .value: "retained",
                    .expires: Date().addingTimeInterval(3600),
                ]))
            await data.httpCookieStore.setCookie(cookie)
            store.removeMiniWindow(containing: browserSelected ? browser.id : owner.id)
            XCTAssertTrue(store.sessions.isEmpty)
            XCTAssertNil(store.terminals.view(for: owner.id))
            XCTAssertFalse(store.terminals.isRunning(owner.id))
            XCTAssertNil(store.browsers.controllers[browser.id])
            XCTAssertNil(store.runtime[owner.id])
            XCTAssertNil(store.runtime[browser.id])
            let retained = await data.httpCookieStore.allCookies()
            XCTAssertTrue(retained.contains { $0.name == cookie.name && $0.value == cookie.value })
            await data.httpCookieStore.deleteCookie(cookie)
        }
    }
}
