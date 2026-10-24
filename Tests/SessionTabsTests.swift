import AppKit
import SwiftUI
import XCTest

final class SessionTabsTests: XCTestCase {
    @MainActor
    private func withStore(_ operation: (AppStore, URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        try await operation(store, directory)
    }

    private func cli(_ name: String = "Codex", profile: String = "codex") -> ManagedSession {
        var session = ManagedSession(name: name, kind: .cli)
        session.cliProfileID = profile
        return session
    }

    @MainActor
    func testNewTabsSharePaneAndLaunchSettingsWithIndependentIdentity() async throws {
        try await withStore { store, directory in
            var original = cli()
            original.workingDirectory = directory.path
            original.worktreePath = directory.appendingPathComponent("worktree").path
            original.worktreeBranch = "agentdeck/review"
            original.worktreeRepo = directory.path
            original.initialPrompt = "Only for the original agent"
            original.isOrchestrator = true
            original.fontSizeOverride = 14
            original.paneSize = PaneSize(width: 700, height: 500)
            original.canvasPosition = PanePoint(x: 55, y: 77)
            original.autoInjectContext = false
            original.autoStart = false
            store.addSession(original, start: false)
            store.maximizedSessionID = original.id
            let tab = try XCTUnwrap(store.addCLITab(to: original.id, start: false))
            XCTAssertNotEqual(tab.id, original.id)
            XCTAssertEqual(tab.paneID, original.paneID)
            XCTAssertEqual(tab.name, "Codex 2")
            XCTAssertEqual(tab.cliProfileID, original.cliProfileID)
            XCTAssertEqual(tab.effectiveDirectory, original.effectiveDirectory)
            XCTAssertEqual(tab.worktreeBranch, original.worktreeBranch)
            XCTAssertEqual(tab.fontSizeOverride, 14)
            XCTAssertEqual(tab.paneSize, original.paneSize)
            XCTAssertEqual(tab.canvasPosition, original.canvasPosition)
            XCTAssertNil(tab.initialPrompt)
            XCTAssertFalse(tab.isOrchestrator)
            XCTAssertFalse(tab.autoInjectContext)
            XCTAssertFalse(tab.autoStart)
            XCTAssertEqual(store.focusedSessionID, tab.id)
            XCTAssertEqual(store.maximizedSessionID, tab.id)
            XCTAssertEqual(store.panes.count, 1)
            XCTAssertEqual(store.panes.first?.tabs.map(\.id), [original.id, tab.id])
            XCTAssertEqual(store.panes.first?.activeSession.id, tab.id)
            let third = try XCTUnwrap(store.addCLITab(to: tab.id, start: false))
            XCTAssertEqual(third.name, "Codex 3")
            XCTAssertEqual(store.panes.count, 1)
            XCTAssertNotEqual(store.mcpURL(for: tab.id), store.mcpURL(for: original.id))
            XCTAssertFalse(store.runtime.values.contains { $0.isRunning })
        }
    }

    @MainActor
    func testTabSelectionPersistsForEachPaneAndSidebarFocusRevealsTabs() async throws {
        try await withStore { store, directory in
            let codex = store.addSession(cli(), start: false)
            let codexTab = try XCTUnwrap(store.addCLITab(to: codex.id, start: false))
            let claude = store.addSession(cli("Claude", profile: "claude"), start: false)
            let claudeTab = try XCTUnwrap(store.addCLITab(to: claude.id, start: false))
            store.selectTab(codex.id)
            store.focusedSessionID = claudeTab.id
            XCTAssertEqual(store.pane(containing: codexTab.id)?.activeSession.id, codex.id)
            XCTAssertEqual(store.pane(containing: claude.id)?.activeSession.id, claudeTab.id)
            store.saveNow()
            let restored = AppStore(stateURL: directory.appendingPathComponent("state.json"))
            defer { restored.shutdown() }
            XCTAssertEqual(restored.panes.map(\.id), [claude.paneID, codex.paneID])
            XCTAssertEqual(restored.panes.map { $0.activeSession.id }, [claudeTab.id, codex.id])
            XCTAssertEqual(restored.focusedSessionID, claudeTab.id)
            restored.maximizedSessionID = claudeTab.id
            restored.focusedSessionID = codexTab.id
            XCTAssertEqual(restored.pane(containing: codex.id)?.activeSession.id, codexTab.id)
            XCTAssertEqual(restored.maximizedSessionID, codexTab.id)
            restored.selectAdjacentTab(1)
            XCTAssertEqual(restored.focusedSessionID, codex.id)
            restored.selectAdjacentTab(-1)
            XCTAssertEqual(restored.focusedSessionID, codexTab.id)
        }
    }

    @MainActor
    func testLegacySessionsRemainSeparatePanes() async throws {
        try await withStore { store, directory in
            store.addSession(cli(), start: false)
            store.addSession(cli("Second Codex"), start: false)
            store.addSession(ManagedSession(name: "Browser", kind: .browser), start: false)
            store.saveNow()
            let url = directory.appendingPathComponent("state.json")
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            var sessions = try XCTUnwrap(json["sessions"] as? [[String: Any]])
            for index in sessions.indices { sessions[index].removeValue(forKey: "paneID") }
            json["sessions"] = sessions
            json.removeValue(forKey: "selectedPaneTabs")
            try JSONSerialization.data(withJSONObject: json).write(to: url)
            let restored = AppStore(stateURL: url)
            defer { restored.shutdown() }
            XCTAssertNil(restored.lastError)
            XCTAssertEqual(restored.panes.count, 3)
            XCTAssertTrue(restored.sessions.allSatisfy { $0.paneID == $0.id })
            XCTAssertTrue(restored.panes.allSatisfy { $0.tabs.count == 1 })
        }
    }

    @MainActor
    func testGeometryAndCanvasPackingOperateOnPanesInsteadOfTabs() async throws {
        try await withStore { store, _ in
            let codex = store.addSession(cli(), start: false)
            let tab = try XCTUnwrap(store.addCLITab(to: codex.id, start: false))
            let claude = store.addSession(cli("Claude", profile: "claude"), start: false)
            store.addCLITab(to: claude.id, start: false)
            store.setCanvasPosition(for: tab.id, PanePoint(x: 70, y: 80))
            store.setPaneSize(for: codex.id, PaneSize(width: 600, height: 400))
            XCTAssertEqual(store.session(codex.id)?.canvasPosition, store.session(tab.id)?.canvasPosition)
            XCTAssertEqual(store.session(codex.id)?.paneSize, store.session(tab.id)?.paneSize)
            store.selectTab(codex.id)
            XCTAssertEqual(store.session(codex.id)?.zIndex, store.session(tab.id)?.zIndex)
            XCTAssertGreaterThan(store.session(codex.id)?.zIndex ?? 0, store.session(claude.id)?.zIndex ?? 0)
            store.tidyCanvas(viewportWidth: 1200)
            XCTAssertEqual(store.session(claude.id)?.canvasPosition, PanePoint(x: 16, y: 16))
            store.canvasViewport = CGSize(width: 1200, height: 800)
            store.fillCanvas()
            let frames = CanvasLayout.frames(count: 2, viewport: store.canvasViewport)
            for (pane, frame) in zip(store.panes, frames) {
                XCTAssertTrue(pane.tabs.allSatisfy { $0.canvasPosition == PanePoint(x: frame.minX, y: frame.minY) })
                XCTAssertTrue(
                    pane.tabs.allSatisfy { $0.paneSize == PaneSize(width: frame.width, height: frame.height) })
            }
            let positions = store.sessions.map(\.canvasPosition)
            store.ensureCanvasPositions(viewportWidth: 1200)
            XCTAssertEqual(store.sessions.map(\.canvasPosition), positions)
            store.setPaneSize(for: tab.id, nil)
            XCTAssertNil(store.session(codex.id)?.paneSize)
            XCTAssertNil(store.session(tab.id)?.paneSize)
        }
    }

    @MainActor
    func testClosingTabsRetainsPaneIdentityAndSelectsNeighbor() async throws {
        try await withStore { store, _ in
            let first = store.addSession(cli(), start: false)
            let second = try XCTUnwrap(store.addCLITab(to: first.id, start: false))
            let third = try XCTUnwrap(store.addCLITab(to: first.id, start: false))
            let other = store.addSession(cli("Claude", profile: "claude"), start: false)
            store.selectTab(second.id)
            store.maximizedSessionID = second.id
            store.removeSession(first.id)
            XCTAssertEqual(store.focusedSessionID, second.id)
            XCTAssertEqual(store.pane(containing: second.id)?.id, first.paneID)
            store.createTask(title: "Owned by second tab", owner: second.id)
            store.removeSession(second.id)
            XCTAssertEqual(store.focusedSessionID, third.id)
            XCTAssertEqual(store.maximizedSessionID, third.id)
            XCTAssertEqual(store.pane(containing: third.id)?.activeSession.id, third.id)
            XCTAssertNil(store.tasks.first?.ownerSessionID)
            XCTAssertNil(store.runtime[second.id])
            store.removeSession(third.id)
            XCTAssertEqual(store.focusedSessionID, other.id)
            XCTAssertNil(store.maximizedSessionID)
            XCTAssertNil(store.selectedPaneTabs[first.paneID])
            XCTAssertEqual(store.panes.count, 1)
            store.removeSession(other.id)
            XCTAssertTrue(store.panes.isEmpty)
            XCTAssertNil(store.focusedSessionID)
        }
    }

    @MainActor
    func testInvalidSourcesAndReferencedWorktreeDeletionDoNotMutateSessions() async throws {
        try await withStore { store, directory in
            let browser = store.addSession(ManagedSession(name: "Browser", kind: .browser), start: false)
            let missing = store.addSession(cli("Missing", profile: "missing-profile"), start: false)
            XCTAssertNil(store.addCLITab(to: nil, start: false))
            XCTAssertNil(store.addCLITab(to: UUID(), start: false))
            XCTAssertNil(store.addCLITab(to: browser.id, start: false))
            XCTAssertNil(store.addCLITab(to: missing.id, start: false))
            XCTAssertEqual(store.sessions.count, 2)
            var source = cli()
            source.worktreeRepo = directory.path
            source.worktreePath = directory.appendingPathComponent("worktree").path
            store.addSession(source, start: false)
            let tab = try XCTUnwrap(store.addCLITab(to: source.id, start: false))
            store.removeSession(source.id, deleteWorktree: true)
            XCTAssertNotNil(store.lastError)
            XCTAssertNotNil(store.session(source.id))
            XCTAssertNotNil(store.session(tab.id))
        }
    }

    @MainActor
    func testSwitchingTerminalViewsKeepsHiddenPTYAndOutputUntilItsTabCloses() async throws {
        _ = NSApplication.shared
        try await withStore { store, directory in
            store.cliProfiles.append(
                CLIProfile(
                    id: "tabs-test", name: "Test shell",
                    command: "stty -echo; while IFS= read -r line; do printf 'received:%s\\n' \"$line\"; done",
                    supportsMCP: false))
            var session = cli("First shell", profile: "tabs-test")
            session.workingDirectory = directory.path
            store.addSession(session)
            let first = try XCTUnwrap(store.terminals.view(for: session.id))
            let hosting = NSHostingView(rootView: TerminalPaneView(session: session).environmentObject(store))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled],
                backing: .buffered, defer: false)
            window.contentView = hosting
            defer { window.contentView = nil }
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertNotNil(first.superview)
            let tab = try XCTUnwrap(store.addCLITab(to: session.id))
            let second = try XCTUnwrap(store.terminals.view(for: tab.id))
            XCTAssertFalse(first === second)
            hosting.rootView = TerminalPaneView(session: tab).environmentObject(store)
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertNil(first.superview, "The previous terminal must be detached from the selected tab")
            XCTAssertNotNil(second.superview)
            XCTAssertTrue(window.firstResponder === second)
            XCTAssertTrue(store.terminals.isRunning(session.id))
            XCTAssertTrue(store.terminals.isRunning(tab.id))
            let firstGeneration = store.runtime[session.id]?.generation
            store.terminals.send(id: session.id, text: "hidden-output\r")
            for _ in 0..<100 {
                if store.terminals.visibleLines(id: session.id).contains(where: {
                    $0.contains("received:hidden-output")
                }) {
                    break
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertTrue(
                store.terminals.visibleLines(id: session.id).contains { $0.contains("received:hidden-output") })
            XCTAssertFalse(store.terminals.visibleLines(id: tab.id).contains { $0.contains("received:hidden-output") })
            store.selectTab(session.id)
            hosting.rootView = TerminalPaneView(session: session).environmentObject(store)
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertTrue(store.terminals.view(for: session.id) === first)
            XCTAssertEqual(store.runtime[session.id]?.generation, firstGeneration)
            XCTAssertTrue(window.firstResponder === first)
            store.removeSession(tab.id)
            XCTAssertNil(store.terminals.view(for: tab.id))
            XCTAssertTrue(store.terminals.isRunning(session.id))
            XCTAssertTrue(store.terminals.view(for: session.id) === first)
        }
    }

    @MainActor
    func testCompanionBrowserTabRetainsPaneTabsAndSupportsAddCLITab() async throws {
        try await withStore { store, _ in
            let cliSession = store.addSession(cli("Agent"), start: false)
            let sibling = try XCTUnwrap(store.addCLITab(to: cliSession.id, start: false))
            var browserSession = ManagedSession(name: "Agent browser", kind: .browser)
            browserSession.paneID = cliSession.paneID
            browserSession.agentOwnerID = cliSession.id
            store.addSession(browserSession, start: false)

            for layout in [LayoutMode.canvas, .grid] {
                store.settings.layoutMode = layout
                for maximized in [false, true] {
                    store.maximizedSessionID = maximized ? cliSession.id : nil
                    for selected in [cliSession, browserSession, sibling, browserSession, cliSession] {
                        store.selectTab(selected.id)
                        let pane = try XCTUnwrap(store.pane(containing: selected.id))
                        XCTAssertEqual(pane.tabs.map(\.id), [cliSession.id, sibling.id, browserSession.id])
                        XCTAssertEqual(pane.activeSession.id, selected.id)
                        XCTAssertTrue(pane.showsTabBar)
                        XCTAssertEqual(store.panes.count, 1)
                        XCTAssertEqual(store.maximizedSessionID, maximized ? selected.id : nil)
                    }
                }
            }
            store.selectTab(browserSession.id)
            XCTAssertEqual(store.cliTabSource(for: browserSession.id)?.id, cliSession.id)

            let newCLITab = try XCTUnwrap(store.addCLITab(to: browserSession.id, start: false))
            XCTAssertEqual(newCLITab.paneID, cliSession.paneID)
            XCTAssertEqual(newCLITab.kind, .cli)
        }
    }

    func testStandaloneBrowserOmitsTabBarButBrowserGroupsKeepIt() {
        let browser = ManagedSession(name: "Browser", kind: .browser)
        var sibling = ManagedSession(name: "Another browser", kind: .browser)
        sibling.paneID = browser.paneID
        XCTAssertFalse(SessionPane.grouped([browser], selectedTabs: [:])[0].showsTabBar)
        for selected in [browser, sibling] {
            let pane = SessionPane.grouped([browser, sibling], selectedTabs: [browser.paneID: selected.id])[0]
            XCTAssertTrue(pane.showsTabBar)
        }
    }
}
