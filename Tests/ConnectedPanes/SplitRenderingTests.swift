import AppKit
import SwiftUI
import XCTest

@MainActor
final class SplitRenderingTests: XCTestCase {
    func testSplitFocusAndNativeDoubleClickRestoreKeepHosts() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        store.settings.workspaceMode = .sessions
        var owner = ManagedSession(name: "Split fixture", kind: .cli)
        owner.paneSize = PaneSize(width: 850, height: 580)
        owner.canvasPosition = PanePoint(x: 70, y: 50)
        owner = store.addSession(owner, start: false)
        let terminal = store.terminals.makeView(for: owner.id, font: store.font(for: owner))
        store.runtime[owner.id]?.isRunning = true
        terminal.startProcess(
            executable: "/bin/sh", args: ["-c", "stty raw -echo; printf READY; exec /bin/cat"],
            environment: ["TERM=xterm-256color", "PATH=/usr/bin:/bin"], currentDirectory: "/tmp")
        let controller = try XCTUnwrap(store.agentBrowserController(for: owner.id))
        let browser = try XCTUnwrap(store.agentBrowser(for: owner.id))
        controller.webView.loadHTMLString("<h1>Split browser</h1>", baseURL: nil)
        let window = makeWindow()
        let host = NSHostingView(rootView: PaneGridView().environmentObject(store))
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            store.shutdown()
            window.close()
            BrowserHost.deleteProfile(store.settings.sharedBrowserProfileID)
            try? FileManager.default.removeItem(at: directory)
        }
        try await Task.sleep(for: .milliseconds(500))
        let container = try XCTUnwrap(terminal.superview)
        XCTAssertTrue(controller.webView.window === window, "Browser is visible by default beside the terminal")
        XCTAssertGreaterThan(terminal.bounds.width, 200)
        XCTAssertGreaterThan(controller.webView.bounds.width, 200)
        store.selectTab(browser.id)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(terminal.superview === container)
        XCTAssertTrue(controller.webView.allowsKeyboardFocus)
        store.selectTab(owner.id)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(window.firstResponder === terminal)
        let originalPosition = store.session(owner.id)?.canvasPosition
        let originalSize = store.session(owner.id)?.paneSize
        for expanding in [true, false] {
            let title = try XCTUnwrap(descendants(host).compactMap { $0 as? MiniWindowMoveView }.first)
            let point = title.convert(CGPoint(x: title.bounds.midX, y: title.bounds.midY), to: nil)
            let event = try XCTUnwrap(
                NSEvent.mouseEvent(
                    with: .leftMouseDown, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                    eventNumber: 1, clickCount: 2, pressure: 1))
            title.mouseDown(with: event)
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertEqual(store.maximizedSessionID != nil, expanding)
            XCTAssertEqual(store.session(owner.id)?.canvasPosition, originalPosition)
            XCTAssertEqual(store.session(owner.id)?.paneSize, originalSize)
            if expanding { XCTAssertEqual(store.paneFrames(in: host.bounds.size)[owner.paneID], host.bounds) }
            XCTAssertTrue(terminal.superview === container)
            XCTAssertTrue(store.browsers.controllers[browser.id] === controller)
        }
        XCTAssertTrue(store.terminals.isRunning(owner.id))
        XCTAssertTrue(window.firstResponder === terminal)
        try snapshot(host, name: "agentdeck-split-restored")
    }

    func testWorkspacePanelsAndThemesKeepLiveSplitContentAndFocus() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        store.settings.workspaceMode = .sessions
        store.settings.showSidebar = false
        store.settings.showInspector = false
        store.settings.showBottomPanel = false
        store.settings.showUsagePanel = false
        var owner = ManagedSession(name: "Live split fixture", kind: .cli)
        owner.paneSize = PaneSize(width: 650, height: 450)
        owner.canvasPosition = PanePoint(x: 16, y: 16)
        owner = store.addSession(owner, start: false)
        let terminal = store.terminals.makeView(for: owner.id, font: store.font(for: owner))
        store.runtime[owner.id]?.isRunning = true
        terminal.startProcess(
            executable: "/bin/sh", args: ["-c", "stty raw -echo; printf READY; exec /bin/cat"],
            environment: ["TERM=xterm-256color", "PATH=/usr/bin:/bin"], currentDirectory: "/tmp")
        let controller = try XCTUnwrap(store.agentBrowserController(for: owner.id))
        let browser = try XCTUnwrap(store.agentBrowser(for: owner.id))
        controller.webView.loadHTMLString("<h1>Live browser fixture</h1>", baseURL: nil)
        let window = makeWindow()
        let host = NSHostingView(rootView: ContentView().environmentObject(store).preferredColorScheme(.light))
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            store.shutdown()
            window.close()
            BrowserHost.deleteProfile(store.settings.sharedBrowserProfileID)
            try? FileManager.default.removeItem(at: directory)
        }
        for _ in 0..<200 where !store.terminals.visibleLines(id: owner.id).joined().contains("READY") {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(store.terminals.visibleLines(id: owner.id).joined().contains("READY"))
        try await Task.sleep(for: .milliseconds(350))
        let container = try XCTUnwrap(terminal.superview)
        let browserContainer = try XCTUnwrap(controller.webView.superview)
        let ids = store.sessions.map(\.id)
        let position = store.session(owner.id)?.canvasPosition
        let size = store.session(owner.id)?.paneSize
        for dark in [false, true] {
            host.rootView = ContentView().environmentObject(store).preferredColorScheme(dark ? .dark : .light)
            store.settings.showSidebar = dark
            store.settings.showInspector = dark
            store.settings.showBottomPanel = dark
            try await Task.sleep(for: .milliseconds(350))
            store.selectTab(browser.id)
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertTrue(controller.webView.allowsKeyboardFocus)
            store.selectTab(owner.id)
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertTrue(window.firstResponder === terminal)
            XCTAssertFalse(terminal.isHidden)
            XCTAssertFalse(controller.webView.isHidden)
            try snapshot(host, name: "agentdeck-live-split-\(dark ? "dark" : "light")")

            store.settings.workspaceMode = .board
            try await Task.sleep(for: .milliseconds(350))
            XCTAssertFalse(window.firstResponder === terminal)
            XCTAssertFalse(controller.webView.allowsKeyboardFocus)
            store.focusSession(owner.id)
            XCTAssertFalse(window.firstResponder === terminal, "Board selection must not focus hidden native content")
            let output = "WORKSPACE_OUTPUT_\(dark)"
            terminal.send(txt: output)
            for _ in 0..<200 where !store.terminals.visibleLines(id: owner.id).joined().contains(output) {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertTrue(store.terminals.visibleLines(id: owner.id).joined().contains(output))

            store.settings.workspaceMode = .sessions
            try await Task.sleep(for: .milliseconds(350))
            store.focusSession(owner.id)
            XCTAssertTrue(window.firstResponder === terminal)
            XCTAssertTrue(terminal.superview === container)
            XCTAssertTrue(controller.webView.superview === browserContainer)
            XCTAssertTrue(store.browsers.controllers[browser.id] === controller)
            XCTAssertTrue(store.terminals.isRunning(owner.id))
            XCTAssertEqual(store.sessions.map(\.id), ids)
            XCTAssertEqual(store.session(owner.id)?.canvasPosition, position)
            XCTAssertEqual(store.session(owner.id)?.paneSize, size)
            XCTAssertEqual(store.settings.showSidebar, dark)
            XCTAssertEqual(store.settings.showInspector, dark)
            XCTAssertEqual(store.settings.showBottomPanel, dark)
        }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1300, height: 850), styleMask: [.titled, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    @discardableResult
    private func snapshot(_ view: NSView, name: String) throws -> NSBitmapImageRep {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: "/tmp/\(name).png"))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return bitmap
    }
}
