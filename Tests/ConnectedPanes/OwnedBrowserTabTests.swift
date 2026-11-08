import AppKit
import XCTest

final class OwnedBrowserTabTests: XCTestCase {
    @MainActor
    func testAutomationCannotCrossOwnerOrSelectedTabAndMigrationRetainsLiveHosts() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        var isolatedProfiles: Set<UUID> = []
        defer {
            store.shutdown()
            for id in isolatedProfiles { BrowserHost.deleteProfile(id) }
            BrowserHost.deleteProfile(store.settings.sharedBrowserProfileID)
            try? FileManager.default.removeItem(at: directory)
        }
        var parent = ManagedSession(name: "Parent", kind: .cli)
        parent.cliProfileID = "codex"
        parent = store.addSession(parent, start: false)
        let worker = try store.delegateTask(from: parent.id, title: "Fixture", instructions: "Local only", start: false)
        let ownerIDs = [parent.id, worker.id]
        var tabs: [UUID: [ManagedSession]] = [:]
        for (index, ownerID) in ownerIDs.enumerated() {
            store.settings.shareAgentBrowserSignIns = index == 0
            _ = try XCTUnwrap(store.agentBrowserController(for: ownerID))
            let first = try XCTUnwrap(store.agentBrowser(for: ownerID))
            isolatedProfiles.insert(first.browserProfileID)
            store.selectTab(first.id)
            let second = try XCTUnwrap(store.addBrowserTab(to: first.id, focus: false))
            tabs[ownerID] = [first, second]
            for (tabIndex, tab) in [first, second].enumerated() {
                store.selectTab(tab.id)
                let marker = "owner\(index)-tab\(tabIndex)"
                let result = await store.invokeTool(
                    name: "browser_navigate",
                    args: ["url": "data:text/html,<title>\(marker)</title><p>\(marker)</p>", "wait_ms": 0],
                    caller: ownerID)
                XCTAssertFalse(result.isError, result.text)
                XCTAssertEqual(store.agentBrowser(for: ownerID)?.id, tab.id)
            }
        }
        // Selection in B's pane cannot route A's automation to B, even though B owns global keyboard focus.
        let resultA = await store.invokeTool(
            name: "browser_eval", args: ["script": "document.title"], caller: parent.id)
        let resultB = await store.invokeTool(
            name: "browser_eval", args: ["script": "document.title"], caller: worker.id)
        XCTAssertEqual(resultA.text, "owner0-tab1")
        XCTAssertEqual(resultB.text, "owner1-tab1")
        let firstA = try XCTUnwrap(tabs[parent.id]?.first)
        store.selectTab(firstA.id)
        let unchanged = await store.invokeTool(
            name: "browser_eval", args: ["script": "document.title"], caller: parent.id)
        XCTAssertEqual(unchanged.text, "owner0-tab0")
        store.selectTab(parent.id)
        XCTAssertEqual(
            store.agentBrowser(for: parent.id)?.id, firstA.id, "Selecting the terminal retains its last browser tab")
        store.selectTab(firstA.id)
        let controllers = store.browsers.controllers
        for index in store.sessions.indices { store.sessions[index].paneID = parent.paneID }
        store.separateConnectedPanes()
        XCTAssertEqual(store.panes.count, 2)
        for (id, controller) in controllers {
            XCTAssertTrue(store.browsers.controllers[id] === controller)
            XCTAssertTrue(store.browsers.controllers[id]?.webView === controller.webView)
        }
        XCTAssertEqual(store.focusedSessionID, firstA.id)
        XCTAssertEqual(store.session(firstA.id)?.browserProfileMode, .shared)
        let firstB = try XCTUnwrap(tabs[worker.id]?.first)
        XCTAssertEqual(store.session(firstB.id)?.browserProfileMode, .isolated)
        XCTAssertNotEqual(store.session(firstA.id)?.paneID, store.session(firstB.id)?.paneID)
    }
}
