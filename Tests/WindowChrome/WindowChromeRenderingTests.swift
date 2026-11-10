import AppKit
import SwiftUI
import XCTest

final class WindowChromeRenderingTests: XCTestCase {
    @MainActor
    func testNativeDragResizesTiledTerminalAndUsageWithoutReplacingTerminal() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let monitor = CLIUsageMonitor { id in CLIUsageSnapshot(providerID: id, source: "Test fixture") }
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"), usageMonitor: monitor)
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        let profile = CLIProfile(id: "resize-test", name: "Local test", command: "exec /bin/cat", supportsMCP: false)
        store.cliProfiles.append(profile)
        var session = ManagedSession(name: "Resize fixture", kind: .cli)
        session.cliProfileID = profile.id
        session.workingDirectory = directory.path
        session.resumeLastConversation = false
        session = store.addSession(session)
        store.settings.workspaceMode = .sessions
        store.settings.layoutMode = .grid
        store.settings.usagePanelPosition = PanePoint(x: 650, y: 300)
        // Deliberately oversized saved dimensions reproduce a grip that previously had a large dead zone.
        store.settings.usagePanelSize = PaneSize(width: 1800, height: 1200)
        store.settings.showUsagePanel = false
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1100, height: 720), styleMask: [.titled, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "AgentDeck resize verification"
        let hosting = NSHostingView(rootView: ContentView().environmentObject(store).preferredColorScheme(.dark))
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(350))
        let terminal = try XCTUnwrap(store.terminals.view(for: session.id))
        XCTAssertTrue(store.terminals.isRunning(session.id))
        let container = terminal.superview
        let resize = try XCTUnwrap(descendants(hosting).compactMap { $0 as? MiniWindowResizeView }.first)
        let start = resize.windowFrame
        let point = CGPoint(x: resize.bounds.maxX - 10, y: resize.bounds.maxY - 10)
        XCTAssertTrue(hosting.hitTest(resize.convert(point, to: hosting.superview)) === resize)
        try drag(resize, in: window, from: point, by: CGSize(width: -100, height: 0))
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(store.settings.layoutMode, .canvas)
        XCTAssertEqual(store.session(session.id)?.paneSize?.width, start.width - 100)
        XCTAssertTrue(terminal.superview === container)
        XCTAssertTrue(descendants(hosting).contains { $0 === resize })
        store.settings.showUsagePanel = true
        try await Task.sleep(for: .milliseconds(350))
        let usage = try XCTUnwrap(
            descendants(hosting).compactMap { $0 as? MiniWindowResizeView }.first { $0.workspaceBounds != nil })
        // The panel enters with a native animation; wait for its real grip to be reachable.
        // Keep the hit-test assertion below so a genuinely covered/missing grip still fails.
        for _ in 0..<200 {
            hosting.layoutSubtreeIfNeeded()
            let grip = CGPoint(x: usage.bounds.maxX - 10, y: usage.bounds.maxY - 10)
            if hosting.hitTest(usage.convert(grip, to: hosting.superview)) === usage { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let displayed = usage.windowFrame
        let corner = CGPoint(x: usage.bounds.maxX - 10, y: usage.bounds.maxY - 10)
        XCTAssertTrue(hosting.hitTest(usage.convert(corner, to: hosting.superview)) === usage)
        try drag(usage, in: window, from: corner, by: CGSize(width: -100, height: -80))
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(store.settings.usagePanelSize.width, displayed.width - 100)
        XCTAssertEqual(store.settings.usagePanelSize.height, displayed.height - 80)
        let beforeLeft = usage.windowFrame
        try drag(usage, in: window, from: CGPoint(x: 2, y: usage.bounds.midY), by: CGSize(width: 50, height: 0))
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(store.settings.usagePanelPosition.x, beforeLeft.minX)
        XCTAssertEqual(store.settings.usagePanelSize.width, beforeLeft.width, "Non-grip edges no longer resize")
        XCTAssertTrue(terminal.superview === container)
        store.saveNow()
        XCTAssertTrue(store.terminals.isRunning(session.id))
        let restored = AppStore(stateURL: directory.appendingPathComponent("state.json"), usageMonitor: monitor)
        defer { restored.shutdown() }
        XCTAssertEqual(restored.settings.usagePanelSize, store.settings.usagePanelSize)
        XCTAssertEqual(restored.settings.usagePanelPosition, store.settings.usagePanelPosition)
        try savePreview(hosting, name: "agentdeck-resize-preview")
    }

    @MainActor
    func testDotsRenderInCanvasAndGridWithDarkAndLightContrast() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        // EmptyCanvasView leaves this sample area unobscured in both layout modes.
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 600, height: 400), styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        for scheme in [ColorScheme.dark, .light] {
            for layout in [LayoutMode.canvas, .grid] {
                store.settings.layoutMode = layout
                let hosting = NSHostingView(
                    rootView: PaneGridView().environmentObject(store).preferredColorScheme(scheme))
                window.contentView = hosting
                window.orderFrontRegardless()
                try await Task.sleep(for: .milliseconds(200))
                let bitmap = try savePreview(hosting, name: "agentdeck-dots-\(scheme)-\(layout)")
                let scaleX = CGFloat(bitmap.pixelsWide) / hosting.bounds.width
                let scaleY = CGFloat(bitmap.pixelsHigh) / hosting.bounds.height
                let dot = try XCTUnwrap(
                    bitmap.colorAt(x: Int(40 * scaleX), y: Int(40 * scaleY))?.usingColorSpace(.deviceRGB))
                let background = try XCTUnwrap(
                    bitmap.colorAt(x: Int(44 * scaleX), y: Int(44 * scaleY))?.usingColorSpace(.deviceRGB))
                if scheme == .dark {
                    XCTAssertGreaterThan(dot.redComponent - background.redComponent, 0.07, "\(layout)")
                } else {
                    XCTAssertGreaterThan(background.redComponent - dot.redComponent, 0.07, "\(layout)")
                }
            }
        }
    }

    @MainActor
    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }

    @MainActor
    private func drag(_ view: MiniWindowResizeView, in window: NSWindow, from point: CGPoint, by delta: CGSize) throws {
        let start = view.convert(point, to: nil)
        let end = CGPoint(x: start.x + delta.width, y: start.y - delta.height)
        func event(_ type: NSEvent.EventType, _ location: CGPoint) throws -> NSEvent {
            try XCTUnwrap(
                NSEvent.mouseEvent(
                    with: type, location: location, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        view.mouseDown(with: try event(.leftMouseDown, start))
        view.mouseDragged(with: try event(.leftMouseDragged, end))
        view.mouseUp(with: try event(.leftMouseUp, end))
    }

    @MainActor
    @discardableResult
    private func savePreview(_ hosting: NSView, name: String) throws -> NSBitmapImageRep {
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
            to: URL(fileURLWithPath: "/tmp/\(name).png"))
        return bitmap
    }
}
