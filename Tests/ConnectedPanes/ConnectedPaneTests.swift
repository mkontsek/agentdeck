import XCTest

final class ConnectedPaneTests: XCTestCase {
    @MainActor
    func testLegacyNestedStateMigratesWithoutChangingIdentitiesProfilesTasksOrResume() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        var parent = ManagedSession(name: "Parent", kind: .cli)
        parent.cliProfileID = "codex"
        parent.canvasPosition = PanePoint(x: 16, y: 16)
        var other = ManagedSession(name: "Other parent tab", kind: .cli)
        other.paneID = parent.paneID
        var worker = ManagedSession(name: "Worker", kind: .cli)
        worker.parentSessionID = parent.id
        worker.delegatedTaskID = 1
        worker.paneID = parent.paneID
        worker.canvasPosition = parent.canvasPosition
        worker.cliProfileID = "codex"
        worker.initialPrompt = "Retained scope"
        var second = worker
        second.id = UUID()
        second.parentSessionID = other.id
        second.delegatedTaskID = 2
        var browser = ManagedSession(name: "Worker browser", kind: .browser)
        browser.agentOwnerID = worker.id
        browser.paneID = parent.paneID
        browser.browserProfileMode = .isolated
        browser.url = "https://example.invalid/retained"
        var tab = browser
        tab.id = UUID()
        tab.name = "Second browser tab"
        var otherBrowser = browser
        otherBrowser.id = UUID()
        otherBrowser.agentOwnerID = second.id
        otherBrowser.browserProfileMode = .shared
        otherBrowser.browserProfileID = UUID()
        var state = PersistedState()
        state.sessions = [parent, other, worker, second, browser, tab, otherBrowser]
        state.focusedSessionID = second.id
        state.selectedPaneTabs = [parent.paneID: other.id]
        state.expandedSubagentTabs = [parent.id: tab.id, other.id: second.id]
        var task = BoardTask(id: 1, title: "Preserved task")
        task.ownerSessionID = worker.id
        state.tasks = [task]
        let checkpoint = SessionResumeCheckpoint(
            profileID: "codex", directory: worker.effectiveDirectory, launchedAt: Date(),
            conversationID: UUID().uuidString, conversationPath: directory.appendingPathComponent("fixture.jsonl").path)
        try ResumeCheckpointStorage.write(
            checkpoint, id: worker.id, directory: directory.appendingPathComponent("resume"))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: url)
        let store = AppStore(stateURL: url)
        defer { store.shutdown() }
        XCTAssertEqual(Set(store.sessions.map(\.id)), Set(state.sessions.map(\.id)))
        XCTAssertEqual(store.panes.count, 3)
        XCTAssertEqual(store.pane(containing: parent.id)?.tabs.map(\.id), [parent.id, other.id])
        XCTAssertEqual(store.pane(containing: worker.id)?.tabs.map(\.id), [worker.id, browser.id, tab.id])
        XCTAssertEqual(store.pane(containing: browser.id)?.tabs.map(\.id), [worker.id, browser.id, tab.id])
        XCTAssertNotEqual(store.session(browser.id)?.paneID, store.session(otherBrowser.id)?.paneID)
        XCTAssertEqual(store.pane(containing: browser.id)?.activeSession.id, tab.id)
        XCTAssertEqual(store.focusedSessionID, second.id)
        XCTAssertEqual(store.resumeCheckpoints[worker.id], checkpoint)
        XCTAssertEqual(store.tasks.first?.ownerSessionID, worker.id)
        for original in state.sessions {
            let migrated = try XCTUnwrap(store.session(original.id))
            XCTAssertEqual(migrated.browserProfileID, original.browserProfileID)
            XCTAssertEqual(migrated.browserProfileMode, original.browserProfileMode)
            XCTAssertEqual(migrated.parentSessionID, original.parentSessionID)
            XCTAssertEqual(migrated.agentOwnerID, original.agentOwnerID)
            XCTAssertEqual(migrated.initialPrompt, original.initialPrompt)
            XCTAssertEqual(migrated.url, original.url)
        }
        store.ensureCanvasPositions(viewportWidth: 1200)
        let migrated = store.sessions
        store.separateConnectedPanes()
        XCTAssertEqual(store.sessions, migrated, "Migration must be idempotent")
        XCTAssertEqual(store.paneConnections.count, 2)
        store.saveNow()
        let restored = AppStore(stateURL: url)
        defer { restored.shutdown() }
        XCTAssertEqual(restored.sessions, migrated)
        XCTAssertEqual(restored.selectedPaneTabs, store.selectedPaneTabs)
        XCTAssertTrue(restored.expandedSubagentTabs.isEmpty)
    }

    @MainActor
    func testBrowserTabSelectionGeometryAndClosureStayWithinOwner() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        var parent = ManagedSession(name: "Main", kind: .cli)
        parent.cliProfileID = "codex"
        parent.canvasPosition = PanePoint(x: 20, y: 20)
        parent = store.addSession(parent, start: false)
        let worker = try store.delegateTask(from: parent.id, title: "Task", instructions: "Fixture", start: false)
        XCTAssertNil(store.addCLITab(to: worker.id, start: false), "A worker keeps one independent session window")
        var browser = ManagedSession(name: "Browser A", kind: .browser)
        browser.agentOwnerID = worker.id
        browser.browserProfileMode = .isolated
        browser = store.addSession(browser, start: false, focus: false)
        let tab = try XCTUnwrap(store.addBrowserTab(to: browser.id, start: false))
        var other = ManagedSession(name: "Browser B", kind: .browser)
        other.agentOwnerID = parent.id
        other = store.addSession(other, start: false, focus: false)
        XCTAssertEqual(store.agentBrowser(for: worker.id)?.id, tab.id)
        XCTAssertEqual(store.agentBrowser(for: parent.id)?.id, other.id)
        XCTAssertEqual(tab.browserProfileID, browser.browserProfileID)
        XCTAssertEqual(tab.browserProfileMode, .isolated)
        store.setCanvasPosition(for: tab.id, PanePoint(x: 900, y: 600))
        store.setPaneSize(for: browser.id, PaneSize(width: 500, height: 400))
        XCTAssertEqual(store.session(tab.id)?.paneSize?.width, 500)
        XCTAssertEqual(store.session(browser.id)?.canvasPosition, PanePoint(x: 900, y: 600))
        XCTAssertEqual(store.session(parent.id)?.canvasPosition, parent.canvasPosition)
        XCTAssertNil(store.session(other.id)?.paneSize)
        store.selectAdjacentTab(1)
        XCTAssertEqual(store.focusedSessionID, worker.id)
        store.maximizedSessionID = browser.id
        store.selectTab(worker.id)
        XCTAssertEqual(store.maximizedSessionID, worker.id)
        store.removeSession(browser.id)
        XCTAssertEqual(store.session(tab.id)?.paneID, browser.paneID)
        store.separateConnectedPanes()
        XCTAssertEqual(store.session(tab.id)?.paneID, browser.paneID, "Closing the first tab must not rename its pane")
        store.removeSession(parent.id)
        XCTAssertNotNil(store.session(worker.id))
        XCTAssertNotNil(store.session(tab.id))
        XCTAssertNil(store.session(other.id))
        XCTAssertNil(store.session(worker.id)?.parentSessionID)
        XCTAssertTrue(store.paneConnections.isEmpty)
    }
}
