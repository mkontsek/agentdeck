import AppKit
import SwiftUI
import XCTest

final class InterfaceRegressionTests: XCTestCase {
    @MainActor
    func testTaskAndProfileEditorsKeepTextAreasInsideTheirWindow() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        try await inspect(
            TaskEditorSheet(task: BoardTask(id: 0, title: "")), store: store,
            size: CGSize(width: 600, height: 620), name: "agentdeck-task-dialog"
        ) { host in
            let editors = self.descendants(host).compactMap { $0 as? NSTextView }
            XCTAssertEqual(editors.count, 2)
            XCTAssertTrue(editors.allSatisfy { $0.bounds.width > 500 })
            XCTAssertLessThanOrEqual(host.fittingSize.width, 601)
        }
        try await inspect(
            ProfilesSettings(), store: store, size: CGSize(width: 780, height: 620), name: "agentdeck-profiles"
        ) { host in
            let editors = self.descendants(host).compactMap { $0 as? NSTextView }
            XCTAssertEqual(editors.count, 3)
            XCTAssertTrue(editors.allSatisfy { $0.bounds.width > 450 })
            XCTAssertLessThanOrEqual(host.fittingSize.width, 781)
        }
    }

    @MainActor
    func testMiniWindowTabsStackAndScrollVertically() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        var parent = ManagedSession(name: "Main conversation", kind: .cli)
        parent.cliProfileID = "codex"
        parent.workingDirectory = directory.path
        store.addSession(parent, start: false)
        for _ in 0..<4 { _ = store.addCLITab(to: parent.id, start: false) }
        store.selectTab(parent.id)
        var lastWorker: ManagedSession?
        for index in 1...20 {
            lastWorker = try store.delegateTask(
                from: parent.id, title: "Worker \(index) with a longer descriptive task name",
                instructions: "Fixture only", start: false)
        }
        let pane = try XCTUnwrap(store.pane(containing: parent.id))
        try await inspect(
            PaneTabBar(pane: pane), store: store, size: CGSize(width: 360, height: 92),
            name: "agentdeck-main-tabs-stacked"
        ) { host in
            let scroll = try XCTUnwrap(self.descendants(host).compactMap { $0 as? NSScrollView }.first)
            let document = try XCTUnwrap(scroll.documentView)
            XCTAssertGreaterThan(document.bounds.height, scroll.contentView.bounds.height)
            XCTAssertLessThanOrEqual(document.bounds.width, scroll.contentView.bounds.width + 1)
            XCTAssertLessThanOrEqual(host.fittingSize.width, 361)
        }
        let last = try XCTUnwrap(lastWorker)
        _ = store.terminals.makeView(for: parent.id, font: store.font(for: parent))
        try await inspect(
            PaneView(pane: pane, size: PaneSize(width: 440, height: 300), mode: .fixed), store: store,
            size: CGSize(width: 440, height: 300), name: "agentdeck-compact-stacked-tabs"
        ) { _ in
            let terminal = try XCTUnwrap(store.terminals.view(for: parent.id))
            XCTAssertGreaterThanOrEqual(terminal.bounds.height, 100)
        }
        store.removeSession(last.id)
        XCTAssertEqual(store.sessions.filter { $0.parentSessionID == parent.id }.count, 19)
        XCTAssertNotNil(store.session(parent.id))
    }

    @MainActor
    private func inspect<V: View>(
        _ view: V, store: AppStore, size: CGSize, name: String,
        checks: (NSView) throws -> Void
    ) async throws {
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: view.environmentObject(store).preferredColorScheme(.dark))
        window.contentView = host
        window.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(350))
        host.layoutSubtreeIfNeeded()
        try checks(host)
        try save(host, name: name)
    }

    @MainActor
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    @MainActor
    private func save(_ host: NSView, name: String) throws {
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent(name + ".png"))
    }
}
