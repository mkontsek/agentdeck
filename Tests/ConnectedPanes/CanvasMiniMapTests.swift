import AppKit
import Combine
import SwiftUI
import XCTest

@MainActor
final class CanvasMiniMapTests: XCTestCase {
    func testMapDragSurvivesViewportClippingAndFractionalScrollRounding() throws {
        let state = CanvasOverviewState()
        let canvas = CGRect(x: 0, y: 0, width: 2000, height: 1000)
        let initial = try XCTUnwrap(
            CanvasOverviewSnapshot(
                bounds: canvas,
                viewport: CGRect(x: -8, y: -4, width: 500, height: 400), panes: [:], focusedPaneID: nil))
        var destinations: [CGPoint] = []
        let source = state.attach { destinations.append($0) }
        state.update(initial, from: source)
        let map = CanvasMiniMapInputView(frame: CGRect(x: 0, y: 0, width: 240, height: 104))
        let window = NSWindow(contentRect: map.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = map
        defer { window.close() }
        map.configure(overview: state, snapshot: initial)
        let projection = try XCTUnwrap(CanvasOverviewProjection(bounds: canvas, size: map.bounds.size))
        let rect = projection.project(initial.viewport)
        let point = map.convert(CGPoint(x: rect.midX, y: rect.midY), to: nil)
        map.mouseDown(with: try mouse(.leftMouseDown, at: point, window: window))
        for step in 1...12 {
            map.mouseDragged(
                with: try mouse(
                    .leftMouseDragged,
                    at: CGPoint(x: point.x + CGFloat(step) * 2, y: point.y - CGFloat(step)), window: window))
            let update = try XCTUnwrap(
                CanvasOverviewSnapshot(
                    bounds: canvas,
                    viewport: CGRect(
                        x: CGFloat(step) * 20, y: CGFloat(step) * 10,
                        width: 500 + (step.isMultiple(of: 2) ? 0.0000001 : 0), height: 400),
                    panes: [:], focusedPaneID: nil))
            state.update(update, from: source)
            map.configure(overview: state, snapshot: update)
        }
        XCTAssertEqual(
            destinations.count, 12, "A pan's own clipped/rounded viewport updates must not release its gesture")
        if let first = destinations.first, let last = destinations.last {
            XCTAssertGreaterThan(last.x, first.x + 100)
            XCTAssertGreaterThan(last.y, first.y + 50)
        }
    }

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
            let projected = projection.project(viewport).origin
            XCTAssertEqual(projection.unproject(projected)?.x ?? -1, viewport.minX, accuracy: 0.001)
            XCTAssertEqual(projection.unproject(projected)?.y ?? -1, viewport.minY, accuracy: 0.001)
            XCTAssertNil(projection.unproject(CGPoint(x: CGFloat.infinity, y: 0)))
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
        let surface = NSView(frame: window.contentLayoutRect)
        host.frame = surface.bounds
        host.autoresizingMask = [.width, .height]
        surface.addSubview(host)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = surface
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
        let map = try XCTUnwrap(descendants(host).compactMap { $0 as? CanvasMiniMapInputView }.first)
        let projection = try XCTUnwrap(CanvasOverviewProjection(bounds: original.bounds, size: map.bounds.size))
        let viewRect = projection.project(original.viewport)
        let start = map.convert(CGPoint(x: viewRect.midX, y: viewRect.midY), to: nil)
        XCTAssertTrue(host.hitTest(surface.convert(start, from: nil)) === map)
        let editor = NSTextView(frame: CGRect(x: 300, y: 20, width: 180, height: 40))
        surface.addSubview(editor)
        editor.string = "Partial Ω\nmap fixture"
        editor.setSelectedRange(NSRange(location: 2, length: 5))
        editor.setMarkedText(
            "žluť", selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        let draft = editor.string
        let selection = editor.selectedRange()
        XCTAssertTrue(window.makeFirstResponder(editor))
        window.sendEvent(try mouse(.leftMouseDown, at: start, window: window))
        XCTAssertEqual(
            scroll.documentVisibleRect.origin, original.viewport.origin, "Grabbing the viewport must not jump")
        for step in 1...12 {
            let delta = CGPoint(x: CGFloat(step) * 2.5, y: -CGFloat(step) * 1.5)
            window.sendEvent(
                try mouse(.leftMouseDragged, at: CGPoint(x: start.x + delta.x, y: start.y + delta.y), window: window))
            try await Task.sleep(for: .milliseconds(30))
        }
        window.sendEvent(try mouse(.leftMouseUp, at: CGPoint(x: start.x + 30, y: start.y - 18), window: window))
        try await Task.sleep(for: .milliseconds(180))
        let scrolled = try XCTUnwrap(store.canvasOverview.snapshot)
        XCTAssertEqual(scrolled.viewport, scroll.documentVisibleRect.intersection(scrolled.bounds))
        XCTAssertGreaterThan(scrolled.viewport.minX, 100)
        XCTAssertGreaterThan(scrolled.viewport.minY, 100)
        XCTAssertEqual(scrolled.bounds, original.bounds)
        XCTAssertEqual(scrolled.panes, original.panes)
        XCTAssertGreaterThan(mapPublications, 0)
        XCTAssertEqual(workspacePublications, 0, "Scrolling must not invalidate all terminal panes")
        XCTAssertTrue(window.firstResponder === editor)
        XCTAssertEqual(editor.string, draft)
        XCTAssertEqual(editor.selectedRange(), selection)
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertEqual(store.focusedSessionID, first.id)
        editor.removeFromSuperview()
        XCTAssertTrue(window.makeFirstResponder(terminal))
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

        // Clicking outside the viewport centers navigation and clamps to the actual scrollable document.
        let edge = map.convert(CGPoint(x: map.bounds.maxX - 2, y: map.bounds.maxY - 2), to: nil)
        window.sendEvent(try mouse(.leftMouseDown, at: edge, window: window))
        window.sendEvent(try mouse(.leftMouseUp, at: edge, window: window))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertGreaterThan(scroll.documentVisibleRect.minX, resized.viewport.minX)
        XCTAssertGreaterThanOrEqual(scroll.documentVisibleRect.minY, 0)
        let documentBounds = try XCTUnwrap(scroll.documentView?.bounds)
        XCTAssertLessThanOrEqual(scroll.documentVisibleRect.maxX, documentBounds.maxX + 1)
        XCTAssertLessThanOrEqual(scroll.documentVisibleRect.maxY, documentBounds.maxY + 1)
        XCTAssertTrue(window.firstResponder === terminal)

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

    func testMapRejectsStaleAttachmentAndGeometryChangesDuringDrag() throws {
        let state = CanvasOverviewState()
        let snapshot = try XCTUnwrap(
            CanvasOverviewSnapshot(
                bounds: CGRect(x: 0, y: 0, width: 2000, height: 1000),
                viewport: CGRect(x: 0, y: 0, width: 500, height: 400), panes: [:], focusedPaneID: nil))
        var originalCalls = 0
        var replacementCalls = 0
        let first = state.attach { _ in originalCalls += 1 }
        state.update(snapshot, from: first)
        let map = CanvasMiniMapInputView(frame: CGRect(x: 0, y: 0, width: 240, height: 104))
        map.configure(overview: state, snapshot: snapshot)
        let window = NSWindow(contentRect: map.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = map
        defer { window.close() }
        let projection = try XCTUnwrap(CanvasOverviewProjection(bounds: snapshot.bounds, size: map.bounds.size))
        let rect = projection.project(snapshot.viewport)
        let point = map.convert(CGPoint(x: rect.midX, y: rect.midY), to: nil)
        map.mouseDown(with: try mouse(.leftMouseDown, at: point, window: window))
        let second = state.attach { _ in replacementCalls += 1 }
        state.moveViewport(to: .zero, from: first)
        XCTAssertNil(state.navigationID, "Replacement cannot navigate using an older snapshot")
        state.update(snapshot, from: second)
        map.mouseDragged(with: try mouse(.leftMouseDragged, at: CGPoint(x: point.x + 30, y: point.y), window: window))
        XCTAssertEqual(originalCalls, 0)
        XCTAssertEqual(replacementCalls, 0)
        // Equal geometry need not republish the map; a fresh gesture must still bind to the replacement.
        map.mouseDown(with: try mouse(.leftMouseDown, at: point, window: window))
        map.mouseDragged(with: try mouse(.leftMouseDragged, at: CGPoint(x: point.x + 30, y: point.y), window: window))
        XCTAssertEqual(replacementCalls, 1)
        replacementCalls = 0
        map.configure(overview: state, snapshot: snapshot)
        map.mouseDown(with: try mouse(.leftMouseDown, at: point, window: window))
        map.setFrameSize(CGSize(width: 300, height: 104))
        map.mouseDragged(with: try mouse(.leftMouseDragged, at: CGPoint(x: point.x + 30, y: point.y), window: window))
        XCTAssertEqual(replacementCalls, 0)
        map.setFrameSize(CGSize(width: 240, height: 104))
        map.mouseDown(with: try mouse(.leftMouseDown, at: point, window: window))
        let resized = try XCTUnwrap(
            CanvasOverviewSnapshot(
                bounds: CGRect(x: 0, y: 0, width: 2200, height: 1000),
                viewport: snapshot.viewport, panes: [:], focusedPaneID: nil))
        state.update(resized, from: second)
        map.mouseDragged(with: try mouse(.leftMouseDragged, at: CGPoint(x: point.x + 30, y: point.y), window: window))
        XCTAssertEqual(replacementCalls, 0, "79-M1: live geometry changed before representable update must cancel drag")
        replacementCalls = 0
        state.detach(second)
        state.moveViewport(to: .zero, from: second)
        XCTAssertEqual(replacementCalls, 0)
    }

    private func mouse(_ type: NSEvent.EventType, at point: CGPoint, window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    }

    private func save(_ host: NSView, name: String) throws {
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
            to: URL(fileURLWithPath: "/tmp/\(name).png"))
    }
}
