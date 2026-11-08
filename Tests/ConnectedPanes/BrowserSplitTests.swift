import XCTest

@MainActor
final class BrowserSplitTests: XCTestCase {
    func testDefaultSplitTracksExactOwnerAndPersistsOptOut() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("state.json")
        let store = AppStore(stateURL: url)
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        let a = store.addSession(ManagedSession(name: "A", kind: .cli), start: false)
        var b = ManagedSession(name: "B", kind: .cli)
        b.paneID = a.paneID
        b = store.addSession(b, start: false)
        var browserIDs: [UUID: [UUID]] = [:]
        for owner in [a, b] {
            for number in 0..<2 {
                var tab = ManagedSession(name: "Browser \(number)", kind: .browser)
                tab.agentOwnerID = owner.id
                tab = store.addSession(tab, start: false, focus: false)
                browserIDs[owner.id, default: []].append(tab.id)
            }
        }
        let secondA = try XCTUnwrap(browserIDs[a.id]?.last)
        store.selectTab(secondA)
        XCTAssertEqual(
            store.visibleSessions(in: try XCTUnwrap(store.pane(containing: a.id))).map(\.id), [a.id, secondA])
        store.selectTab(a.id)
        XCTAssertEqual(
            store.visibleSessions(in: try XCTUnwrap(store.pane(containing: a.id))).map(\.id), [a.id, secondA])
        store.selectTab(b.id)
        XCTAssertEqual(
            store.visibleSessions(in: try XCTUnwrap(store.pane(containing: b.id))).map(\.id),
            [b.id, try XCTUnwrap(browserIDs[b.id]?.first)])
        store.setBrowserSplit(for: b, enabled: false)
        XCTAssertEqual(store.visibleSessions(in: try XCTUnwrap(store.pane(containing: b.id))).map(\.id), [b.id])
        store.saveNow()
        let restored = AppStore(stateURL: url)
        defer { restored.shutdown() }
        XCTAssertEqual(restored.session(b.id)?.browserSplitEnabled, false)
        XCTAssertEqual(restored.session(a.id)?.browserSplitEnabled, true)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(a)) as? [String: Any])
        legacy.removeValue(forKey: "browserSplitEnabled")
        XCTAssertTrue(
            try JSONDecoder().decode(ManagedSession.self, from: JSONSerialization.data(withJSONObject: legacy))
                .browserSplitEnabled)
    }
}
