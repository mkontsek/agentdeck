import AppKit
import SwiftUI
import Vision
import XCTest

@MainActor
final class SplitDemoRenderingTests: XCTestCase {
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

    func testDemoMasksLiveIdentifiersInLightAndDarkAndRestoresSession() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        store.settings.workspaceMode = .sessions
        var owner = ManagedSession(name: "CONFIDENTIAL CUSTOMER", kind: .cli)
        owner.paneSize = PaneSize(width: 650, height: 570)
        owner.canvasPosition = PanePoint(x: 16, y: 16)
        owner = store.addSession(owner, start: false)
        let terminal = store.terminals.makeView(for: owner.id, font: store.font(for: owner))
        store.runtime[owner.id]?.isRunning = true
        terminal.startProcess(
            executable: "/bin/sh", args: ["-c", "stty raw -echo; printf READY; exec /bin/cat"],
            environment: ["TERM=xterm-256color", "PATH=/usr/bin:/bin"], currentDirectory: "/tmp")
        let controller = try XCTUnwrap(store.agentBrowserController(for: owner.id))
        controller.webView.loadHTMLString("<h1>CONFIDENTIAL BROWSER</h1>", baseURL: nil)
        store.settings.showSidebar = true
        store.settings.showInspector = true
        store.settings.showBottomPanel = true
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
        try await Task.sleep(for: .milliseconds(500))
        let names = store.sessions.map(\.name)
        let ids = store.sessions.map(\.id)
        let position = store.session(owner.id)?.canvasPosition
        store.setDemoMode(true)
        for dark in [false, true] {
            host.rootView = ContentView().environmentObject(store).preferredColorScheme(dark ? .dark : .light)
            try await Task.sleep(for: .milliseconds(300))
            let bitmap = try snapshot(host, name: "agentdeck-demo-\(dark ? "dark" : "light")")
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .fast
            try VNImageRequestHandler(cgImage: try XCTUnwrap(bitmap.cgImage)).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            XCTAssertTrue(text.contains("Agent 1"), text)
            XCTAssertFalse(text.localizedCaseInsensitiveContains("CONFIDENTIAL"), text)
            XCTAssertFalse(text.contains(owner.id.uuidString), text)
        }
        XCTAssertFalse(controller.webView.allowsKeyboardFocus)
        XCTAssertFalse(window.firstResponder === terminal)
        let bytes = terminal.diagnostics.bytesFed
        terminal.send(txt: "demo-live-output")
        for _ in 0..<200 where terminal.diagnostics.bytesFed <= bytes { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertGreaterThan(terminal.diagnostics.bytesFed, bytes)
        store.setDemoMode(false)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(store.sessions.map(\.id), ids)
        XCTAssertEqual(store.sessions.map(\.name), names)
        XCTAssertEqual(store.session(owner.id)?.canvasPosition, position)
        XCTAssertTrue(store.terminals.isRunning(owner.id))
        XCTAssertTrue(window.firstResponder === terminal)
        XCTAssertTrue(store.settings.showSidebar && store.settings.showInspector && store.settings.showBottomPanel)
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
