import AppKit
import SwiftUI
import XCTest

@MainActor
final class GlassBallTests: XCTestCase {
    func testStatusPriorityAndPersistentOptIn() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("state.json")
        let store = AppStore(stateURL: url)
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        let parent = store.addSession(ManagedSession(name: "Parent", kind: .cli), start: false)
        var child = ManagedSession(name: "Worker", kind: .cli)
        child.parentSessionID = parent.id
        child = store.addSession(child, start: false, focus: false)
        let pane = try XCTUnwrap(store.pane(containing: child.id))
        XCTAssertFalse(store.collapsesToGlassBall(pane, hovered: false))
        store.settings.glassBallSubagents = true
        XCTAssertTrue(store.collapsesToGlassBall(pane, hovered: false))
        XCTAssertFalse(store.collapsesToGlassBall(pane, hovered: true))
        XCTAssertFalse(store.collapsesToGlassBall(try XCTUnwrap(store.pane(containing: parent.id)), hovered: false))
        store.runtime[child.id]?.status = .idle
        XCTAssertEqual(store.glassBallStatus(for: child), .idle, "Idle alone does not prove success")
        store.runtime[child.id]?.status = .working
        XCTAssertEqual(store.glassBallStatus(for: child), .working)
        store.tasks = [BoardTask(id: 1, title: "Fixture", ownerSessionID: child.id, status: .awaitingApproval)]
        XCTAssertEqual(store.glassBallStatus(for: child), .attention)
        store.tasks[0].status = .done
        XCTAssertEqual(store.glassBallStatus(for: child), .working, "New work takes priority over past success")
        store.runtime[child.id]?.status = .idle
        XCTAssertEqual(store.glassBallStatus(for: child), .finished)
        store.runtime[child.id]?.status = .error
        XCTAssertEqual(store.glassBallStatus(for: child), .attention)
        store.focusSession(child.id)
        XCTAssertFalse(store.collapsesToGlassBall(pane, hovered: false), "Typing target stays expanded")
        store.saveNow()
        let restored = AppStore(stateURL: url)
        defer { restored.shutdown() }
        XCTAssertTrue(restored.settings.glassBallSubagents)
        XCTAssertFalse(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).glassBallSubagents)
    }

    func testNativeHoverRetainsHostsAndFocusWhileCollapsedOutputSkipsPainting() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        store.settings.workspaceMode = .sessions
        var parent = ManagedSession(name: "Parent fixture", kind: .cli)
        parent.paneSize = PaneSize(width: 400, height: 400)
        parent.canvasPosition = PanePoint(x: 8, y: 8)
        parent = store.addSession(parent, start: false)
        var child = ManagedSession(name: "Worker fixture", kind: .cli)
        child.parentSessionID = parent.id
        child.paneSize = PaneSize(width: 850, height: 580)
        child.canvasPosition = PanePoint(x: 440, y: 20)
        child = store.addSession(child, start: false, focus: false)
        let parentTerminal = store.terminals.makeView(for: parent.id, font: store.font(for: parent))
        let terminal = store.terminals.makeView(for: child.id, font: store.font(for: child))
        for (session, view) in [(parent, parentTerminal), (child, terminal)] {
            store.runtime[session.id]?.isRunning = true
            view.suspendsRenderingWhenNotVisible = false
            view.startProcess(
                executable: "/bin/sh", args: ["-c", "stty raw -echo; printf READY; exec /bin/cat"],
                environment: ["TERM=xterm-256color", "PATH=/usr/bin:/bin"], currentDirectory: "/tmp")
        }
        let browser = try XCTUnwrap(store.agentBrowserController(for: child.id))
        browser.webView.loadHTMLString("<h1>Retained local browser</h1>", baseURL: nil)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1400, height: 850), styleMask: [.titled, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: PaneGridView().environmentObject(store))
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            store.shutdown()
            window.close()
            BrowserHost.deleteProfile(store.settings.sharedBrowserProfileID)
            try? FileManager.default.removeItem(at: directory)
        }
        for _ in 0..<1000 where terminal.diagnostics.bytesFed < 5 || terminal.diagnostics.renders == 0 {
            try await Task.sleep(for: .milliseconds(5))
        }
        store.focusSession(parent.id)
        let container = try XCTUnwrap(terminal.superview)
        let webContainer = try XCTUnwrap(browser.webView.superview)
        let originalSize = store.session(child.id)?.paneSize
        let originalPosition = store.session(child.id)?.canvasPosition
        store.settings.glassBallSubagents = true
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(terminal.isHidden && terminal.defersGlassBallDisplay)
        XCTAssertTrue(browser.webView.isHidden)
        XCTAssertTrue(window.firstResponder === parentTerminal)
        let hover = try XCTUnwrap(
            descendants(host).compactMap { $0 as? GlassBallHoverView }.first { $0.paneID == child.paneID })
        XCTAssertEqual(hover.bounds.size, GlassBallStatus.compactSize)
        XCTAssertEqual(store.canvasOverview.snapshot?.panes[child.paneID]?.size, GlassBallStatus.compactSize)
        let renders = terminal.diagnostics.renders
        let bytes = terminal.diagnostics.bytesFed
        let output = "\r\nhidden-Ω-output"
        for _ in 0..<20 { terminal.send(txt: output) }
        for _ in 0..<1000 where terminal.diagnostics.bytesFed < bytes + 20 * output.utf8.count {
            try await Task.sleep(for: .milliseconds(2))
        }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(terminal.diagnostics.bytesFed, bytes + 20 * output.utf8.count)
        XCTAssertEqual(terminal.diagnostics.renders, renders, "Collapsed terminal must not repaint under output")
        print(
            "GLASS_BALL collapsedBytes=\(terminal.diagnostics.bytesFed - bytes) collapsedRenders=\(terminal.diagnostics.renders - renders)"
        )
        let event = try XCTUnwrap(
            NSEvent.enterExitEvent(
                with: .mouseEntered, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                eventNumber: 1, trackingNumber: 0, userData: nil))
        hover.mouseEntered(with: event)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(terminal.isHidden || terminal.defersGlassBallDisplay)
        XCTAssertFalse(browser.webView.isHidden)
        XCTAssertTrue(terminal.superview === container)
        XCTAssertTrue(browser.webView.superview === webContainer)
        XCTAssertTrue(window.firstResponder === parentTerminal, "Hover must not change typing focus")
        XCTAssertEqual(store.focusedSessionID, parent.id)
        for _ in 0..<200 where terminal.diagnostics.renders == renders { try await Task.sleep(for: .milliseconds(5)) }
        print(
            "GLASS_BALL expandedRenders=\(terminal.diagnostics.renders - renders) canvasDeferred=\(terminal.defersCanvasDisplay) hidden=\(terminal.isHiddenOrHasHiddenAncestor) frame=\(terminal.convert(terminal.bounds, to: host)) visible=\(terminal.visibleRect)"
        )
        XCTAssertGreaterThan(terminal.diagnostics.renders, renders)
        XCTAssertTrue(store.terminals.visibleLines(id: child.id).joined().contains("hidden-Ω-output"))
        hover.mouseExited(with: event)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(terminal.isHidden)
        store.focusSession(child.id)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(terminal.isHidden)
        XCTAssertTrue(window.firstResponder === terminal, "Explicit selection opens and focuses a collapsed worker")
        hover.mouseExited(with: event)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(terminal.isHidden, "A focused typing window remains expanded after pointer exit")
        store.focusSession(parent.id)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(terminal.isHidden)
        store.settings.glassBallSubagents = false
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(terminal.isHidden || browser.webView.isHidden)
        XCTAssertEqual(store.session(child.id)?.paneSize, originalSize)
        XCTAssertEqual(store.session(child.id)?.canvasPosition, originalPosition)
        XCTAssertTrue(store.terminals.isRunning(child.id))
        XCTAssertTrue(window.firstResponder === parentTerminal)
    }

    func testStatusBallsRenderInBothThemesAndReducedMotion() async throws {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 580, height: 190), styleMask: [.titled], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        for dark in [false, true] {
            let host = NSHostingView(
                rootView: HStack(spacing: 16) {
                    GlassBallView(name: "Working agent", status: .working, reduceMotion: true, onOpen: {})
                    GlassBallView(name: "Needs attention", status: .attention, reduceMotion: true, onOpen: {})
                    GlassBallView(name: "Finished agent", status: .finished, reduceMotion: true, onOpen: {})
                    GlassBallView(name: "Idle agent", status: .idle, reduceMotion: true, onOpen: {})
                }.padding(20).preferredColorScheme(dark ? .dark : .light)
            )
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            try await Task.sleep(for: .milliseconds(150))
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: "/tmp/agentdeck-glass-balls-\(dark ? "dark" : "light").png"))
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
}
