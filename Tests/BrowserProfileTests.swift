import AppKit
import WebKit
import XCTest

final class BrowserProfileTests: XCTestCase {
    func testLegacySessionsUseSharedProfileButRetainTheirSeparateProfile() throws {
        let oldID = UUID()
        let data = Data("{\"name\":\"Old browser\",\"kind\":\"browser\",\"browserProfileID\":\"\(oldID)\"}".utf8)
        var session = try JSONDecoder().decode(ManagedSession.self, from: data)
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(session.browserProfileMode, .shared)
        XCTAssertEqual(
            session.browserDataStoreID(sharedProfileID: settings.sharedBrowserProfileID),
            settings.sharedBrowserProfileID)
        XCTAssertEqual(session.browserProfileID, oldID)
        session.browserProfileMode = .isolated
        XCTAssertEqual(session.browserDataStoreID(sharedProfileID: settings.sharedBrowserProfileID), oldID)
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.sharedBrowserProfileID, settings.sharedBrowserProfileID)
    }

    @MainActor
    func testSharedCookiesSurvivePaneRemovalAndAppStoreRestoration() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let stateURL = directory.appendingPathComponent("state.json")
        let store = AppStore(stateURL: stateURL)
        var first = ManagedSession(name: "First", kind: .browser)
        first.url = "about:blank"
        var second = ManagedSession(name: "Second", kind: .browser)
        second.url = "about:blank"
        var separate = ManagedSession(name: "Separate", kind: .browser)
        separate.url = "about:blank"
        separate.browserProfileMode = .isolated
        defer {
            store.shutdown()
            BrowserHost.deleteProfile(store.settings.sharedBrowserProfileID)
            BrowserHost.deleteProfile(separate.browserProfileID)
            try? FileManager.default.removeItem(at: directory)
        }
        for session in [first, second, separate] { store.addSession(session) }
        let firstData = try dataStore(for: first.id, in: store)
        let secondData = try dataStore(for: second.id, in: store)
        let separateData = try dataStore(for: separate.id, in: store)
        XCTAssertTrue(firstData.isPersistent)
        XCTAssertEqual(firstData.identifier, secondData.identifier)
        XCTAssertNotEqual(firstData.identifier, separateData.identifier)
        let cookie = try XCTUnwrap(
            HTTPCookie(properties: [
                .domain: "agentdeck.test", .path: "/", .name: "shared-profile-test", .value: "signed-in",
                .expires: Date().addingTimeInterval(3600),
            ]))
        await firstData.httpCookieStore.setCookie(cookie)
        let sharedCookies = await secondData.httpCookieStore.allCookies()
        let separateCookies = await separateData.httpCookieStore.allCookies()
        XCTAssertTrue(sharedCookies.contains { $0.name == cookie.name && $0.value == cookie.value })
        XCTAssertFalse(separateCookies.contains { $0.name == cookie.name })

        store.removeSession(first.id, deleteBrowserProfile: true)
        let retainedCookies = await secondData.httpCookieStore.allCookies()
        XCTAssertTrue(retainedCookies.contains { $0.name == cookie.name })
        store.restartSession(second.id)
        let restartedData = try dataStore(for: second.id, in: store)
        XCTAssertEqual(restartedData.identifier, firstData.identifier)
        store.saveNow()
        store.shutdown()

        let restored = AppStore(stateURL: stateURL)
        defer { restored.shutdown() }
        restored.startSession(second.id)
        let restoredData = try dataStore(for: second.id, in: restored)
        XCTAssertEqual(restoredData.identifier, firstData.identifier)
        let restoredCookies = await restoredData.httpCookieStore.allCookies()
        XCTAssertTrue(restoredCookies.contains { $0.name == cookie.name && $0.value == cookie.value })
        await restoredData.httpCookieStore.deleteCookie(cookie)
    }

    @MainActor
    func testSwitchingProfilesReloadsOnlyRunningBrowserAndPreservesSeparateID() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        var browser = ManagedSession(name: "Browser", kind: .browser)
        browser.url = "about:blank"
        defer {
            store.shutdown()
            BrowserHost.deleteProfile(store.settings.sharedBrowserProfileID)
            BrowserHost.deleteProfile(browser.browserProfileID)
            try? FileManager.default.removeItem(at: directory)
        }
        store.addSession(browser)
        let first = try XCTUnwrap(store.browsers.controllers[browser.id])
        store.setBrowserProfileMode(.isolated, for: browser.id)
        XCTAssertFalse(store.browsers.controllers[browser.id] === first)
        XCTAssertEqual(try dataStore(for: browser.id, in: store).identifier, browser.browserProfileID)
        store.setBrowserProfileMode(.shared, for: browser.id)
        XCTAssertEqual(try dataStore(for: browser.id, in: store).identifier, store.settings.sharedBrowserProfileID)
        store.stopSession(browser.id)
        store.setBrowserProfileMode(.isolated, for: browser.id)
        XCTAssertNil(store.browsers.controllers[browser.id])
        XCTAssertEqual(store.session(browser.id)?.browserProfileID, browser.browserProfileID)
        store.saveNow()
        let restored = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer { restored.shutdown() }
        XCTAssertEqual(restored.session(browser.id)?.browserProfileMode, .isolated)
    }

    @MainActor
    private func dataStore(for id: UUID, in store: AppStore) throws -> WKWebsiteDataStore {
        try XCTUnwrap(store.browsers.controllers[id]?.webView.configuration.websiteDataStore)
    }
}
