import AppKit
import XCTest

final class BrowserAutomationTests: XCTestCase {
    @MainActor
    func testPrivateBrowserToolsDriveOnlyTheCallersCompanionTab() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        // WebKit needs a visible window to lay out and snapshot; the controller parks hidden views inside it.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480), styleMask: [.titled], backing: .buffered,
            defer: false)
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        let agent = store.addSession(ManagedSession(name: "Agent", kind: .cli), start: false)
        let other = store.addSession(ManagedSession(name: "Other", kind: .cli), start: false)
        store.focusedSessionID = agent.id

        let html = """
            <h1 id="t">Hello</h1><button onclick="document.getElementById('t').textContent='Clicked'">Press</button>
            <form onsubmit="event.preventDefault(); document.title='submitted:' + document.getElementById('q').value">
            <input id="q" name="q"></form>
            """
        let encoded = html.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let nav = await store.invokeTool(
            name: "browser_navigate", args: ["url": "data:text/html," + encoded, "wait_ms": 100], caller: agent.id)
        XCTAssertFalse(nav.isError, nav.text)
        XCTAssertTrue(nav.text.contains("Hello"), nav.text)

        let companion = try XCTUnwrap(store.agentBrowser(for: agent.id))
        XCTAssertEqual(companion.paneID, agent.paneID, "companion lives in the agent's pane")
        XCTAssertEqual(companion.browserProfileMode, .isolated)
        XCTAssertEqual(store.focusedSessionID, agent.id, "opening the browser must not steal focus")
        XCTAssertEqual(store.selectedPaneTabs[agent.paneID], agent.id, "terminal tab stays in front")
        XCTAssertNil(store.agentBrowser(for: other.id), "other sessions get their own browser only on use")
        store.setBrowserProfileMode(.shared, for: companion.id)
        XCTAssertEqual(store.session(companion.id)?.browserProfileMode, .isolated, "companions stay isolated")
        XCTAssertNotNil(store.lastError)
        store.lastError = nil
        XCTAssertTrue(store.toolDefinitions(caller: agent.id).contains { ($0["name"] as? String) == "browser_read" })
        XCTAssertFalse(store.contextSummary(for: agent).contains(companion.name))

        let read = await store.invokeTool(name: "browser_read", args: [:], caller: agent.id)
        XCTAssertFalse(read.isError, read.text)
        XCTAssertTrue(read.text.contains("Press"), read.text)

        let click = await store.invokeTool(
            name: "browser_click", args: ["text": "press", "wait_ms": 50], caller: agent.id)
        XCTAssertFalse(click.isError, click.text)
        let after = await store.invokeTool(
            name: "browser_eval", args: ["script": "document.getElementById('t').textContent"], caller: agent.id)
        XCTAssertEqual(after.text, "Clicked")

        let typed = await store.invokeTool(
            name: "browser_type", args: ["selector": "#q", "text": "needle", "submit": true, "wait_ms": 50],
            caller: agent.id)
        XCTAssertFalse(typed.isError, typed.text)
        XCTAssertTrue(typed.text.contains("submitted:needle"), typed.text)

        let missing = await store.invokeTool(name: "browser_click", args: ["selector": "#nope"], caller: agent.id)
        XCTAssertTrue(missing.isError)
        let notCLI = await store.invokeTool(name: "browser_read", args: [:], caller: companion.id)
        XCTAssertTrue(notCLI.isError)

        let shot = await store.invokeTool(name: "browser_screenshot", args: [:], caller: agent.id)
        XCTAssertFalse(shot.isError, shot.text)
        XCTAssertEqual(shot.content.first?["type"] as? String, "image")
        XCTAssertGreaterThan((shot.content.first?["data"] as? String)?.count ?? 0, 100)

        store.removeSession(agent.id)
        XCTAssertNil(store.session(companion.id), "companion is removed with its owner")
    }
}
