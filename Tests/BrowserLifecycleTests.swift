import AppKit
import SwiftUI
import WebKit
import XCTest

final class BrowserLifecycleTests: XCTestCase {
    @MainActor
    func testBrowserStopRenderAndRestartRetainProfile() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        var session = ManagedSession(name: "Browser test", kind: .browser)
        session.browserProfileMode = .isolated
        session.url = "about:blank"
        defer {
            store.shutdown()
            BrowserHost.deleteProfile(session.browserProfileID)
            try? FileManager.default.removeItem(at: directory)
        }
        store.addSession(session)
        let first = try XCTUnwrap(store.browsers.controllers[session.id])
        XCTAssertTrue(first.webView.configuration.websiteDataStore.isPersistent)
        store.stopSession(session.id)
        XCTAssertNil(store.browsers.controllers[session.id])
        XCTAssertEqual(store.runtime[session.id]?.status, .exited)
        let view = NSHostingView(rootView: BrowserPaneView(session: session).environmentObject(store))
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(store.browsers.controllers[session.id], "Rendering a stopped pane restarted WebKit")
        store.restartSession(session.id)
        let restarted = try XCTUnwrap(store.browsers.controllers[session.id])
        XCTAssertFalse(first === restarted)
        XCTAssertEqual(store.session(session.id)?.browserProfileID, session.browserProfileID)
        restarted.webView.loadHTMLString("<html><body>AgentDeck browser smoke test</body></html>", baseURL: nil)
        var text = ""
        for _ in 0..<100 {
            text = (try? await restarted.webView.evaluateJavaScript("document.body.textContent")) as? String ?? ""
            if text == "AgentDeck browser smoke test" { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(text, "AgentDeck browser smoke test")
    }
}
