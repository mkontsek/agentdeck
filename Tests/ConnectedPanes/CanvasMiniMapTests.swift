import AppKit
import Combine
import SwiftUI
import XCTest

@MainActor
final class CanvasMiniMapTests: XCTestCase {
    func testProjectionPreservesViewportProportionsAndRejectsInvalidGeometry() throws {
        let paneID = UUID()
        let bounds = CGRect(x: 0, y: 0, width: 2400, height: 1200)
        let viewport = CGRect(x: 600, y: 300, width: 800, height: 500)
        let pane = CGRect(x: 1800, y: 800, width: 400, height: 300)
        let snapshot = try XCTUnwrap(
            CanvasOverviewSnapshot(bounds: bounds, viewport: viewport, panes: [paneID: pane], focusedPaneID: paneID))
        for size in [CGSize(width: 180, height: 104), CGSize(width: 320, height: 104)] {
            let projection = try XCTUnwrap(CanvasOverviewProjection(bounds: snapshot.bounds, size: size))
            let canvas = projection.project(snapshot.bounds)
            let visible = projection.project(snapshot.viewport)
            XCTAssertTrue(CGRect(origin: .zero, size: size).insetBy(dx: 7, dy: 7).contains(canvas))
            XCTAssertEqual(canvas.width / canvas.height, 2, accuracy: 0.001)
            XCTAssertEqual((visible.minX - canvas.minX) / canvas.width, 0.25, accuracy: 0.001)
            XCTAssertEqual((visible.minY - canvas.minY) / canvas.height, 0.25, accuracy: 0.001)
            XCTAssertEqual(visible.width / canvas.width, 1.0 / 3, accuracy: 0.001)
            XCTAssertTrue(canvas.contains(projection.project(pane)))
        }
        XCTAssertNil(CanvasOverviewProjection(bounds: .zero, size: CGSize(width: 200, height: 104)))
        XCTAssertNil(CanvasOverviewProjection(bounds: bounds, size: .zero))
        XCTAssertNil(CanvasOverviewSnapshot(bounds: bounds, viewport: .null, panes: [:], focusedPaneID: nil))
        let filtered = try XCTUnwrap(
            CanvasOverviewSnapshot(
                bounds: bounds, viewport: viewport, panes: [paneID: .infinite], focusedPaneID: nil))
        XCTAssertTrue(filtered.panes.isEmpty)
        let bounced = try XCTUnwrap(
            CanvasOverviewSnapshot(
                bounds: bounds, viewport: CGRect(x: -20, y: -10, width: 800, height: 500), panes: [:],
                focusedPaneID: nil))
        XCTAssertEqual(bounced.bounds, bounds, "Overscroll must not change the map scale")
        XCTAssertEqual(bounced.viewport, CGRect(x: 0, y: 0, width: 780, height: 490))
    }

    func testReplacedObserverCannotPublishOrClearNewerMapAndIdenticalUpdatesAreSilent() throws {
        let state = CanvasOverviewState()
        let first = state.attach()
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let snapshot = try XCTUnwrap(
            CanvasOverviewSnapshot(bounds: bounds, viewport: bounds, panes: [:], focusedPaneID: nil))
        var publications = 0
        let subscription = state.objectWillChange.sink { publications += 1 }
        defer { subscription.cancel() }
        state.update(snapshot, from: first)
        state.update(snapshot, from: first)
        XCTAssertEqual(publications, 1)
        let replacement = state.attach()
        state.update(nil, from: first)
        state.detach(first)
        XCTAssertEqual(state.snapshot, snapshot)
        XCTAssertEqual(publications, 1)
        state.update(nil, from: replacement)
        XCTAssertNil(state.snapshot)
        state.detach(replacement)
        state.update(snapshot, from: replacement)
        XCTAssertNil(state.snapshot)
        XCTAssertEqual(publications, 2)
    }

    func testNativeMapTracksScrollResizeAndWindowsWithoutPublishingWorkspaceOrMovingFocus() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1040, height: 560), styleMask: [.titled, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer {
            window.close()
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        for index in 0..<12 {
            var session = ManagedSession(name: "Map window \(index + 1)", kind: .cli)
            session.canvasPosition = PanePoint(x: 16 + Double(index % 4) * 420, y: 16 + Double(index / 4) * 320)
            session.paneSize = PaneSize(width: 360, height: 280)
            store.addSession(session, start: false, focus: false)
        }
        let first = try XCTUnwrap(store.sessions.first)
        store.settings.workspaceMode = .sessions
        store.focusedSessionID = first.id
        store.runtime[first.id]?.isRunning = true
        let terminal = store.terminals.makeView(for: first.id, font: store.font(for: first))
        let host = NSHostingView(rootView: fixture(store, scheme: .dark))
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(window.makeFirstResponder(terminal))
        let observer = try XCTUnwrap(descendants(host).compactMap { $0 as? CanvasScrollObservationView }.first)
        let scroll = try XCTUnwrap(observer.enclosingScrollView)
        let original = try XCTUnwrap(store.canvasOverview.snapshot)
        XCTAssertEqual(original.panes.count, 12)
        XCTAssertEqual(original.focusedPaneID, first.paneID)
        var workspacePublications = 0
        var mapPublications = 0
        let workspaceSubscription = store.objectWillChange.sink { workspacePublications += 1 }
        let mapSubscription = store.canvasOverview.objectWillChange.sink { mapPublications += 1 }
        defer {
            workspaceSubscription.cancel()
            mapSubscription.cancel()
        }
        scroll.contentView.scroll(to: CGPoint(x: 600, y: 300))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await Task.sleep(for: .milliseconds(180))
        let scrolled = try XCTUnwrap(store.canvasOverview.snapshot)
        XCTAssertEqual(scrolled.viewport, scroll.documentVisibleRect.intersection(scrolled.bounds))
        XCTAssertGreaterThan(scrolled.viewport.minX, 100)
        XCTAssertGreaterThan(scrolled.viewport.minY, 100)
        XCTAssertEqual(scrolled.bounds, original.bounds)
        XCTAssertEqual(scrolled.panes, original.panes)
        XCTAssertGreaterThan(mapPublications, 0)
        XCTAssertEqual(workspacePublications, 0, "Scrolling must not invalidate all terminal panes")
        XCTAssertTrue(window.firstResponder === terminal)
        XCTAssertEqual(store.focusedSessionID, first.id)
        try save(host, name: "agentdeck-canvas-map-dark")

        let last = try XCTUnwrap(store.sessions.last)
        store.setCanvasPosition(for: last.id, PanePoint(x: 2100, y: 1100))
        store.setPaneSize(for: last.id, PaneSize(width: 500, height: 400))
        window.setContentSize(CGSize(width: 1240, height: 680))
        window.appearance = NSAppearance(named: .aqua)
        host.rootView = fixture(store, scheme: .light)
        try await Task.sleep(for: .milliseconds(400))
        let resized = try XCTUnwrap(store.canvasOverview.snapshot)
        XCTAssertEqual(resized.panes[last.paneID], CGRect(x: 2100, y: 1100, width: 500, height: 400))
        XCTAssertTrue(resized.bounds.contains(try XCTUnwrap(resized.panes[last.paneID])))
        XCTAssertEqual(resized.viewport, scroll.documentVisibleRect.intersection(resized.bounds))
        XCTAssertGreaterThan(resized.viewport.width, scrolled.viewport.width)
        XCTAssertTrue(window.firstResponder === terminal)
        try save(host, name: "agentdeck-canvas-map-light")

        store.maximizedSessionID = first.id
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(store.canvasOverview.snapshot?.panes.count, 1)
        XCTAssertEqual(store.canvasOverview.snapshot?.panes[first.paneID]?.origin, .zero)
        store.maximizedSessionID = nil
        store.removeSession(last.id)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(store.canvasOverview.snapshot?.panes.count, 11)
        XCTAssertNil(store.canvasOverview.snapshot?.panes[last.paneID])
        for id in store.sessions.map(\.id) { store.removeSession(id) }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(store.canvasOverview.snapshot?.panes.count, 0)
        window.contentView = nil
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(store.canvasOverview.snapshot, "Detached canvas must not leave a stale viewport")
    }

    private func fixture(_ store: AppStore, scheme: ColorScheme) -> some View {
        HStack(spacing: 0) {
            SidebarView().frame(width: 240)
            Divider()
            PaneGridView()
        }
        .environmentObject(store).preferredColorScheme(scheme)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    private func save(_ host: NSView, name: String) throws {
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
            to: URL(fileURLWithPath: "/tmp/\(name).png"))
    }
}
