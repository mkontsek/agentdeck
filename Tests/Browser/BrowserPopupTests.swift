import AppKit
import WebKit
import XCTest

@MainActor
final class BrowserPopupTests: XCTestCase {
    func testCrossOriginPopupMessagesOpenerClosesAndPreservesParent() async throws {
        _ = NSApplication.shared
        let parentServer = try PopupFixtureServer(
            page: """
                <!doctype html><title>Parent fixture</title><p id="marker">original parent</p>
                <script>
                window.received = '';
                window.addEventListener('message', event => {
                    if (event.source === window.child && event.origin === window.expectedOrigin) {
                        window.received = event.data;
                    }
                });
                </script>
                """)
        let parentPort = try await parentServer.start()
        let parentOrigin = "http://127.0.0.1:\(parentPort)"
        let childServer = try PopupFixtureServer(
            page: """
                <!doctype html><title>Child fixture</title><script>
                if (window.opener) {
                    window.opener.postMessage('fixture-sign-in-complete', '\(parentOrigin)');
                    window.close();
                }
                </script>
                """)
        let childPort = try await childServer.start()
        let host = BrowserHost()
        let profile = UUID()
        var session = ManagedSession(name: "Popup regression", kind: .browser)
        session.url = "about:blank"
        let parent = host.controller(for: session, sharedProfileID: profile)
        parent.ensureInWindow()
        defer {
            host.dispose(id: session.id)
            parentServer.stop()
            childServer.stop()
            BrowserHost.deleteProfile(profile)
        }
        let error = await parent.navigate(parentOrigin)
        XCTAssertNil(error)
        let childOrigin = "http://127.0.0.1:\(childPort)"
        _ = try await parent.webView.evaluateJavaScript(
            """
            window.expectedOrigin = '\(childOrigin)';
            window.child = window.open('\(childOrigin)/callback', 'fixture-oauth');
            void 0;
            """)
        try await waitUntil {
            (try? await parent.webView.evaluateJavaScript("window.received")) as? String == "fixture-sign-in-complete"
        }
        XCTAssertEqual(parent.webView.url?.absoluteString, parentOrigin + "/")
        let marker = try await parent.webView.evaluateJavaScript("document.getElementById('marker')?.textContent")
        XCTAssertEqual(marker as? String, "original parent")
        let closed = try await parent.webView.evaluateJavaScript("window.child.closed")
        XCTAssertEqual(closed as? Bool, true)
        XCTAssertTrue(parent.popupWindows.isEmpty)
    }

    func testPopupConfigurationCookiesAndIsolation() async throws {
        _ = NSApplication.shared
        let server = try PopupFixtureServer(page: "<!doctype html><title>Profile fixture</title><p>Profile fixture</p>")
        let port = try await server.start()
        let origin = "http://127.0.0.1:\(port)"
        let host = BrowserHost()
        let sharedProfile = UUID()
        var shared = ManagedSession(name: "Shared fixture", kind: .browser)
        shared.url = "about:blank"
        var isolated = ManagedSession(name: "Isolated fixture", kind: .browser)
        isolated.browserProfileMode = .isolated
        isolated.url = "about:blank"
        defer {
            for session in [shared, isolated] { host.dispose(id: session.id) }
            server.stop()
            BrowserHost.deleteProfile(sharedProfile)
            BrowserHost.deleteProfile(isolated.browserProfileID)
        }
        for (session, expectedProfile, marker) in [
            (shared, sharedProfile, "shared-fixture"),
            (isolated, isolated.browserProfileID, "isolated-fixture"),
        ] {
            let parent = host.controller(for: session, sharedProfileID: sharedProfile)
            parent.ensureInWindow()
            let configuration = parent.webView.configuration
            configuration.userContentController.addUserScript(
                WKUserScript(
                    source: "window.configurationMarker = '\(marker)'", injectionTime: .atDocumentStart,
                    forMainFrameOnly: true))
            let cookie = try XCTUnwrap(
                HTTPCookie(properties: [
                    .domain: "127.0.0.1", .path: "/", .name: "popup-profile", .value: marker,
                ]))
            await configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
            let error = await parent.navigate(origin)
            XCTAssertNil(error)
            _ = try await parent.webView.evaluateJavaScript("window.child = window.open('\(origin)/popup'); void 0")
            try await waitUntil { parent.popupWindows.count == 1 }
            let popup = try XCTUnwrap(parent.popupWindows.values.first)
            try await waitUntil {
                popup.controller.webView.url?.path == "/popup" && !popup.controller.webView.isLoading
            }
            let childConfig = popup.controller.webView.configuration
            XCTAssertEqual(childConfig.websiteDataStore.identifier, expectedProfile)
            XCTAssertTrue(childConfig.userContentController === configuration.userContentController)
            XCTAssertTrue(childConfig.processPool === configuration.processPool)
            XCTAssertEqual(popup.controller.webView.customUserAgent, parent.webView.customUserAgent)
            let injected = try await popup.controller.webView.evaluateJavaScript("window.configurationMarker")
            XCTAssertEqual(injected as? String, marker)
            let cookieText = try await popup.controller.webView.evaluateJavaScript("document.cookie")
            XCTAssertEqual(cookieText as? String, "popup-profile=\(marker)")
            XCTAssertEqual(popup.window.title, "AgentDeck — \(origin)")
            XCTAssertFalse(popup.window.isKeyWindow, "A script-created popup stole keyboard focus")
            if let image = await popup.controller.snapshot() {
                try image.write(
                    to: FileManager.default.temporaryDirectory.appendingPathComponent("agentdeck-popup-\(marker).png"))
            } else {
                XCTFail("Popup did not render")
            }
            popup.window.performClose(nil)
            XCTAssertTrue(parent.popupWindows.isEmpty)
            XCTAssertTrue(popup.controller.isClosed)
            XCTAssertNil(popup.controller.webView.uiDelegate)
            XCTAssertNil(popup.window.contentView)
            XCTAssertFalse(popup.window.isVisible)
            _ = try await parent.webView.evaluateJavaScript(
                "window.open('\(origin)/noopener', '_blank', 'noopener'); void 0")
            try await waitUntil { parent.popupWindows.count == 1 }
            let noOpener = try XCTUnwrap(parent.popupWindows.values.first)
            try await waitUntil {
                noOpener.controller.webView.url?.path == "/noopener" && !noOpener.controller.webView.isLoading
            }
            let disconnected = try await noOpener.controller.webView.evaluateJavaScript("window.opener === null")
            XCTAssertEqual(disconnected as? Bool, true, "WebKit's explicit noopener boundary must survive")
            noOpener.close()
        }
    }

    func testBlankPopupPostBodyNestedCleanupAndRestart() async throws {
        _ = NSApplication.shared
        let server = try PopupFixtureServer(
            page: "<!doctype html><title>Lifecycle fixture</title><p>Keep parent</p>", stalledPaths: ["/hang"])
        let port = try await server.start()
        let origin = "http://127.0.0.1:\(port)"
        let host = BrowserHost()
        let profile = UUID()
        var session = ManagedSession(name: "Lifecycle fixture", kind: .browser)
        session.url = "about:blank"
        defer {
            host.dispose(id: session.id)
            server.stop()
            BrowserHost.deleteProfile(profile)
        }
        let parent = host.controller(for: session, sharedProfileID: profile)
        parent.ensureInWindow()
        let error = await parent.navigate(origin)
        XCTAssertNil(error)
        _ = try await parent.webView.evaluateJavaScript("window.child = window.open('', 'post-target'); void 0")
        try await waitUntil { parent.popupWindows.count == 1 }
        let popup = try XCTUnwrap(parent.popupWindows.values.first)
        _ = try await parent.webView.evaluateJavaScript(
            """
            const form = document.createElement('form');
            form.method = 'POST'; form.action = '\(origin)/post'; form.target = 'post-target';
            const input = document.createElement('input');
            input.name = 'fixture'; input.value = 'body-preserved';
            form.append(input); document.body.append(form); form.submit(); void 0;
            """)
        try await waitUntil {
            server.requests.contains { $0.hasPrefix("POST /post ") && $0.hasSuffix("fixture=body-preserved") }
        }
        try await waitUntil { popup.controller.webView.url?.path == "/post" && !popup.controller.webView.isLoading }
        XCTAssertEqual(parent.popupWindows.count, 1, "Named window should be reused")
        XCTAssertEqual(parent.webView.url?.absoluteString, origin + "/")
        _ = try await parent.webView.evaluateJavaScript(
            "form.target = '_blank'; input.value = 'new-window-body'; form.submit(); void 0")
        try await waitUntil {
            parent.popupWindows.count == 2
                && server.requests.contains { $0.hasPrefix("POST /post ") && $0.hasSuffix("fixture=new-window-body") }
        }
        _ = try await popup.controller.webView.evaluateJavaScript("window.open('\(origin)/nested'); void 0")
        try await waitUntil { popup.controller.popupWindows.count == 1 }
        let nested = try XCTUnwrap(popup.controller.popupWindows.values.first)
        let pending = Task { @MainActor in await popup.controller.navigate(origin + "/hang", timeoutSeconds: 30) }
        try await waitUntil { server.requests.contains { $0.hasPrefix("GET /hang ") } }
        host.dispose(id: session.id)
        let canceled = await pending.value
        XCTAssertEqual(canceled, "browser closed")
        XCTAssertTrue(parent.popupWindows.isEmpty)
        XCTAssertTrue(popup.controller.isClosed)
        XCTAssertTrue(nested.controller.isClosed)
        XCTAssertFalse(popup.window.isVisible)
        XCTAssertFalse(nested.window.isVisible)
        XCTAssertNil(popup.controller.webView.navigationDelegate)
        let restarted = host.controller(for: session, sharedProfileID: profile)
        XCTAssertFalse(restarted === parent)
        XCTAssertTrue(restarted.popupWindows.isEmpty)
        XCTAssertEqual(restarted.webView.configuration.websiteDataStore.identifier, profile)
        popup.close()  // A late close from the previous generation cannot remove the new parent.
        XCTAssertTrue(host.controllers[session.id] === restarted)
    }

    func testPopupRejectsNativeAndScriptSchemesWithoutChangingParent() async throws {
        _ = NSApplication.shared
        let host = BrowserHost()
        let profile = UUID()
        var session = ManagedSession(name: "Navigation fixture", kind: .browser)
        session.url = "about:blank"
        let parent = host.controller(for: session, sharedProfileID: profile)
        parent.ensureInWindow()
        defer {
            host.dispose(id: session.id)
            BrowserHost.deleteProfile(profile)
        }
        let error = await parent.navigate("about:blank")
        XCTAssertNil(error)
        for url in [
            "file:///tmp/task78-must-not-load", "javascript:document.title='unsafe'", "agentdeck:unsafe",
            "data:text/html,unsafe",
        ] {
            XCTAssertFalse(BrowserController.allowsPopupURL(URL(string: url)))
        }
        _ = try await parent.webView.evaluateJavaScript("window.open('file:///tmp/task78-must-not-load'); void 0")
        XCTAssertTrue(parent.popupWindows.isEmpty)
        XCTAssertEqual(parent.webView.url?.absoluteString, "about:blank")
        _ = try await parent.webView.evaluateJavaScript("window.open('about:blank'); void 0")
        try await waitUntil { parent.popupWindows.count == 1 }
        let popup = try XCTUnwrap(parent.popupWindows.values.first)
        let navigationError = await popup.controller.navigate("file:///tmp/task78-must-not-load", timeoutSeconds: 2)
        XCTAssertNotNil(navigationError)
        XCTAssertNotEqual(popup.controller.webView.url?.scheme, "file")
    }

    private func waitUntil(file: StaticString = #filePath, line: UInt = #line, _ condition: () async throws -> Bool)
        async throws
    {
        for _ in 0..<100 {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Timed out waiting for native popup behavior", file: file, line: line)
        throw CancellationError()
    }
}
