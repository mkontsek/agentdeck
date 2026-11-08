import AppKit
import SwiftUI
import XCTest

final class ConnectedPaneRenderingTests: XCTestCase {
    @MainActor
    func testStartupFitsRestoredOffscreenWorkerOnFirstLayout() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = AppStore(stateURL: url)
        var parent = ManagedSession(name: "Parent", kind: .cli)
        parent.cliProfileID = "codex"
        parent.canvasPosition = PanePoint(x: 16, y: 16)
        source.addSession(parent, start: false)
        let worker = try source.delegateTask(
            from: parent.id, title: "Restored worker", instructions: "Fixture", start: false)
        source.setCanvasPosition(for: worker.id, PanePoint(x: 1800, y: 900))
        source.selectTab(worker.id)
        source.shutdown()
        let store = AppStore(stateURL: url)
        defer { store.shutdown() }
        XCTAssertEqual(store.paneRevealRevision, 0)
        store.prepareStartupLayout()
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 800, height: 500), styleMask: [.titled], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: PaneGridView().environmentObject(store))
        window.contentView = host
        window.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(400))
        let scroller = try XCTUnwrap(descendants(host).compactMap { $0 as? NSScrollView }.first)
        XCTAssertEqual(scroller.contentView.bounds.origin, .zero)
        XCTAssertTrue(store.paneFrames(in: host.bounds.size).values.allSatisfy { host.bounds.contains($0) })
        XCTAssertEqual(store.focusedSessionID, worker.id)
        XCTAssertEqual(store.pane(containing: worker.id)?.activeSession.id, worker.id)
    }

    @MainActor
    func testConnectedNativeWindowsMoveResizeMaximizeAndKeepHosts() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            BrowserHost.deleteProfile(store.settings.sharedBrowserProfileID)
            try? FileManager.default.removeItem(at: directory)
        }
        let profile = CLIProfile(
            id: "connected-fixture", name: "Fixture", command: "printf 'CONNECTED_READY\\n'; exec /bin/cat",
            supportsMCP: true)
        store.cliProfiles.append(profile)
        var parent = ManagedSession(name: "Main conversation", kind: .cli)
        parent.cliProfileID = profile.id
        parent.workingDirectory = directory.path
        parent.resumeLastConversation = false
        parent.paneSize = PaneSize(width: 360, height: 320)
        parent.canvasPosition = PanePoint(x: 16, y: 32)
        store.addSession(parent)
        let worker = try store.delegateTask(from: parent.id, title: "Verify windows", instructions: "Fixture")
        let controller = try XCTUnwrap(store.agentBrowserController(for: worker.id))
        let browser = try XCTUnwrap(store.agentBrowser(for: worker.id))
        controller.webView.loadHTMLString("<h1>Owned browser</h1><p>Isolated local fixture</p>", baseURL: nil)
        store.settings.workspaceMode = .sessions
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1280, height: 580), styleMask: [.titled, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: PaneGridView().environmentObject(store).preferredColorScheme(.dark))
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(400))
        for _ in 0..<100 {
            if [parent.id, worker.id].allSatisfy({
                store.terminals.visibleLines(id: $0).joined().contains("CONNECTED_READY")
            }),
                !controller.isLoading
            {
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        for id in [parent.id, worker.id] {
            XCTAssertTrue(store.terminals.visibleLines(id: id).joined().contains("CONNECTED_READY"))
        }
        let parentTerminal = try XCTUnwrap(store.terminals.view(for: parent.id))
        let workerTerminal = try XCTUnwrap(store.terminals.view(for: worker.id))
        let parentContainer = try XCTUnwrap(parentTerminal.superview)
        let workerContainer = try XCTUnwrap(workerTerminal.superview)
        XCTAssertEqual(store.session(browser.id)?.paneID, worker.paneID)
        XCTAssertEqual(store.focusedSessionID, parent.id)
        XCTAssertEqual(descendants(host).compactMap { $0 as? MiniWindowResizeView }.count, 2)
        XCTAssertEqual(store.paneConnections.map(\.kind), [.subagent])
        let dark = try save(host, name: "agentdeck-connected-dark")
        try assertConnectionPixels(dark, host: host, x: 400, y: 192, dark: true)

        let move = try XCTUnwrap(
            descendants(host).compactMap { $0 as? MiniWindowMoveView }
                .first { $0.accessibilityLabel() == "Move \(worker.name) window" })
        let start = try XCTUnwrap(store.session(worker.id)?.canvasPosition)
        try drag(move, in: window, from: CGPoint(x: 9, y: 9), by: CGSize(width: 20, height: 80))
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(store.session(worker.id)?.canvasPosition, PanePoint(x: start.x + 20, y: start.y + 80))
        XCTAssertEqual(store.session(parent.id)?.canvasPosition, parent.canvasPosition)
        XCTAssertEqual(store.session(browser.id)?.canvasPosition, store.session(worker.id)?.canvasPosition)
        XCTAssertEqual(store.focusedSessionID, worker.id)
        XCTAssertTrue(workerTerminal.superview === workerContainer)
        let elbow = try save(host, name: "agentdeck-connected-elbow-dark")
        try assertConnectionPixels(elbow, host: host, x: 392, y: 192, dark: true)
        let resize = try XCTUnwrap(
            descendants(host).compactMap { $0 as? MiniWindowResizeView }
                .first { $0.windowFrame.minX == start.x + 20 })
        try drag(
            resize, in: window, from: CGPoint(x: resize.bounds.width - 2, y: resize.bounds.height - 2),
            by: CGSize(width: 30, height: 0))
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(store.session(worker.id)?.paneSize?.width, 390)
        XCTAssertEqual(store.session(parent.id)?.paneSize?.width, 360)
        XCTAssertEqual(store.session(browser.id)?.paneSize?.width, 390)
        for id in [worker.id, browser.id, parent.id] {
            store.maximizedSessionID = id
            store.selectTab(id)
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertEqual(store.maximizedSessionID, id)
            XCTAssertTrue(parentTerminal.superview === parentContainer)
            XCTAssertTrue(store.terminals.view(for: worker.id) === workerTerminal)
            XCTAssertTrue(store.browsers.controllers[browser.id] === controller)
            if id == browser.id {
                XCTAssertTrue(controller.webView.window === window)
                XCTAssertEqual(
                    controller.webView.pageZoom,
                    store.textSize(for: try XCTUnwrap(store.session(id))) / PaneTextScale.browserReference)
                store.adjustFont(for: id, by: -1)
                try await Task.sleep(for: .milliseconds(80))
                XCTAssertEqual(
                    controller.webView.pageZoom,
                    store.textSize(for: try XCTUnwrap(store.session(id))) / PaneTextScale.browserReference)
            }
        }
        store.selectTab(worker.id)
        store.maximizedSessionID = nil
        store.settings.layoutMode = .grid
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(parentTerminal.superview === parentContainer)
        XCTAssertTrue(workerTerminal.window === window)
        store.settings.layoutMode = .canvas
        store.setCanvasPosition(for: worker.id, PanePoint(x: 1600, y: 900))
        try await Task.sleep(for: .milliseconds(300))
        store.selectTab(worker.id)
        try await Task.sleep(for: .milliseconds(300))
        let scroller = try XCTUnwrap(descendants(host).compactMap { $0 as? NSScrollView }.first)
        XCTAssertGreaterThan(scroller.contentView.bounds.origin.x, 500)
        XCTAssertGreaterThan(scroller.contentView.bounds.origin.y, 300)
        store.setCanvasPosition(for: worker.id, start)
        store.selectTab(parent.id)
        host.rootView = PaneGridView().environmentObject(store).preferredColorScheme(.light)
        try await Task.sleep(for: .milliseconds(300))
        try save(host, name: "agentdeck-connected-light-moved")
        // Reset just the moved geometry for the same connector contrast sample in light appearance.
        store.setCanvasPosition(for: worker.id, start)
        store.setPaneSize(for: worker.id, parent.paneSize)
        try await Task.sleep(for: .milliseconds(250))
        let light = try save(host, name: "agentdeck-connected-light")
        try assertConnectionPixels(light, host: host, x: 400, y: 192, dark: false)
        XCTAssertTrue(store.terminals.isRunning(parent.id))
        XCTAssertTrue(store.terminals.isRunning(worker.id))
        XCTAssertTrue(store.browsers.controllers[browser.id] === controller)
        XCTAssertTrue(parentTerminal.superview === parentContainer)
        XCTAssertTrue(workerTerminal.window === window)
        store.saveNow()
        let restored = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer { restored.shutdown() }
        XCTAssertEqual(restored.sessions.map(\.paneID), store.sessions.map(\.paneID))
        XCTAssertEqual(restored.sessions.map(\.canvasPosition), store.sessions.map(\.canvasPosition))
        XCTAssertEqual(restored.focusedSessionID, store.focusedSessionID)
    }

    @MainActor
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    @MainActor
    private func drag(_ view: NSView, in window: NSWindow, from point: CGPoint, by delta: CGSize) throws {
        let start = view.convert(point, to: nil)
        let end = CGPoint(x: start.x + delta.width, y: start.y - delta.height)
        func event(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(
                NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        view.mouseDown(with: try event(.leftMouseDown, start))
        view.mouseDragged(with: try event(.leftMouseDragged, end))
        view.mouseUp(with: try event(.leftMouseUp, end))
    }

    @MainActor
    @discardableResult
    private func save(_ host: NSView, name: String) throws -> NSBitmapImageRep {
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
            to: URL(fileURLWithPath: "/tmp/\(name).png"))
        return bitmap
    }

    @MainActor
    private func assertConnectionPixels(_ bitmap: NSBitmapImageRep, host: NSView, x: Double, y: Double, dark: Bool)
        throws
    {
        let sx = Double(bitmap.pixelsWide) / host.bounds.width
        let sy = Double(bitmap.pixelsHigh) / host.bounds.height
        let line = try XCTUnwrap(bitmap.colorAt(x: Int(x * sx), y: Int(y * sy))?.usingColorSpace(.deviceRGB))
        let nearby = try XCTUnwrap(bitmap.colorAt(x: Int(x * sx), y: Int((y + 6) * sy))?.usingColorSpace(.deviceRGB))
        let difference =
            abs(line.redComponent - nearby.redComponent) + abs(line.greenComponent - nearby.greenComponent)
            + abs(line.blueComponent - nearby.blueComponent)
        XCTAssertGreaterThan(difference, 0.25, "Connector must remain visible in \(dark ? "dark" : "light") mode")
    }
}
