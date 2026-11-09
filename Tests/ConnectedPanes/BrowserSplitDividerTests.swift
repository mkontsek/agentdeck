import AppKit
import Combine
import SwiftUI
import XCTest

@MainActor
final class BrowserSplitDividerTests: XCTestCase {
    func testGeometryKeepsBothSidesUsableAcrossAxesAndInvalidSizes() {
        let wide = BrowserSplitGeometry(size: CGSize(width: 1000, height: 400), isHorizontal: true, fraction: 0.7)
        XCTAssertEqual(wide.firstSize.width, 694.4, accuracy: 0.01)
        XCTAssertEqual(wide.firstSize.width + wide.dividerExtent + wide.secondSize.width, 1000)
        let stacked = BrowserSplitGeometry(size: CGSize(width: 400, height: 800), isHorizontal: false, fraction: 0.9)
        XCTAssertEqual(stacked.secondSize.height, 120)
        XCTAssertEqual(stacked.dividerFrame.minY, stacked.firstSize.height)
        let tiny = BrowserSplitGeometry(size: CGSize(width: 100, height: 80), isHorizontal: true, fraction: 0.1)
        XCTAssertEqual(tiny.firstSize.width, 46)
        XCTAssertEqual(tiny.secondSize.width, 46)
        let invalid = BrowserSplitGeometry(
            size: CGSize(width: CGFloat.infinity, height: -1), isHorizontal: true, fraction: .nan)
        XCTAssertEqual(invalid.size, .zero)
        XCTAssertEqual(invalid.displayedFraction, 0.5)
    }

    func testRatiosPersistPerOwnerAndDecodeLegacyOrMalformedValues() throws {
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
        let browser = store.addSession(ManagedSession(name: "Browser", kind: .browser), start: false)
        store.setBrowserSplitFraction(for: a.id, 0.7)
        store.setBrowserSplitFraction(for: b.id, 0.3)
        store.setBrowserSplitFraction(for: a.id, .nan)
        store.setBrowserSplitFraction(for: browser.id, 0.8)
        store.setBrowserSplitFraction(for: UUID(), 0.8)
        XCTAssertEqual(store.session(browser.id)?.browserSplitFraction, 0.5)
        store.saveNow()
        let restored = AppStore(stateURL: url)
        defer { restored.shutdown() }
        XCTAssertEqual(restored.session(a.id)?.browserSplitFraction, 0.7)
        XCTAssertEqual(restored.session(b.id)?.browserSplitFraction, 0.3)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(a)) as? [String: Any])
        for (value, expected) in [(nil, 0.5), ("invalid" as Any?, 0.5), (-4 as Any?, 0.1), (4 as Any?, 0.9)] {
            json["browserSplitFraction"] = value
            let decoded = try JSONDecoder().decode(
                ManagedSession.self, from: JSONSerialization.data(withJSONObject: json))
            XCTAssertEqual(decoded.browserSplitFraction, expected)
        }
    }

    func testNativeGestureCancelsOnOwnerAxisSizeOrAttachmentChange() throws {
        let window = makeWindow()
        defer { window.close() }
        let divider = BrowserSplitDividerView(frame: CGRect(x: 300, y: 0, width: 8, height: 400))
        window.contentView?.addSubview(divider)
        let editor = NSTextView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        window.contentView?.addSubview(editor)
        editor.string = "partial Unicode Ω\nfixture"
        editor.setSelectedRange(NSRange(location: 2, length: 5))
        editor.setMarkedText(
            "žluť", selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(window.makeFirstResponder(editor))
        let text = editor.string
        let selection = editor.selectedRange()
        let ownerID = UUID()
        let size = CGSize(width: 800, height: 500)
        let original = BrowserSplitGeometry(size: size, isHorizontal: true, fraction: 0.5)
        var commits: [Double?] = []
        var previews: [Double] = []
        divider.onFinish = { commits.append($0) }
        divider.onPreview = { previews.append($0) }
        for mutation in 0..<4 {
            divider.configure(ownerID: ownerID, geometry: original)
            divider.mouseDown(with: try mouse(.leftMouseDown, at: CGPoint(x: 304, y: 250), window: window))
            divider.mouseDragged(with: try mouse(.leftMouseDragged, at: CGPoint(x: 400, y: 250), window: window))
            switch mutation {
            case 0: divider.configure(ownerID: UUID(), geometry: original)
            case 1:
                divider.configure(
                    ownerID: ownerID, geometry: BrowserSplitGeometry(size: size, isHorizontal: false, fraction: 0.5))
            case 2:
                divider.configure(
                    ownerID: ownerID,
                    geometry: BrowserSplitGeometry(
                        size: CGSize(width: 900, height: 500), isHorizontal: true, fraction: 0.5))
            default:
                divider.removeFromSuperview()
                window.contentView?.addSubview(divider)
            }
            divider.mouseUp(with: try mouse(.leftMouseUp, at: CGPoint(x: 400, y: 250), window: window))
        }
        XCTAssertEqual(previews.count, 4)
        XCTAssertTrue(commits.isEmpty, "Obsolete gestures must not save a split")
        divider.configure(
            ownerID: ownerID, geometry: BrowserSplitGeometry(size: size, isHorizontal: false, fraction: 0.5))
        divider.mouseDown(with: try mouse(.leftMouseDown, at: CGPoint(x: 304, y: 250), window: window))
        divider.mouseUp(with: try mouse(.leftMouseUp, at: CGPoint(x: 304, y: 200), window: window))
        XCTAssertGreaterThan(try XCTUnwrap(commits.last ?? nil), 0.5, "Dragging down expands the top terminal")
        divider.mouseDown(with: try mouse(.leftMouseDown, at: CGPoint(x: 304, y: 200), window: window, clicks: 2))
        XCTAssertEqual(commits.last ?? nil, 0.5)
        XCTAssertTrue(window.firstResponder === editor)
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertEqual(editor.string, text)
        XCTAssertEqual(editor.selectedRange(), selection)
    }

    func testRealMouseDragResizesLiveSplitWithoutGlobalUpdatesOrFocusLoss() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        store.settings.workspaceMode = .sessions
        var owner = ManagedSession(name: "Divider fixture", kind: .cli)
        owner.paneSize = PaneSize(width: 1000, height: 600)
        owner.canvasPosition = PanePoint(x: 30, y: 30)
        owner = store.addSession(owner, start: false)
        let terminal = store.terminals.makeView(for: owner.id, font: store.font(for: owner))
        store.runtime[owner.id]?.isRunning = true
        terminal.startProcess(
            executable: "/bin/sh", args: ["-c", "stty raw -echo; printf READY; exec /bin/cat"],
            environment: ["TERM=xterm-256color", "PATH=/usr/bin:/bin"], currentDirectory: "/tmp")
        let browser = try XCTUnwrap(store.agentBrowserController(for: owner.id))
        browser.webView.loadHTMLString(
            "<h1>Local divider fixture</h1><textarea>partial Ω fixture</textarea>", baseURL: nil)
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
        try await Task.sleep(for: .milliseconds(700))
        for _ in 0..<200 where browser.webView.isLoading { try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(200))
        let terminalContainer = try XCTUnwrap(terminal.superview)
        let browserContainer = try XCTUnwrap(browser.webView.superview)
        let divider = try XCTUnwrap(descendants(host).compactMap { $0 as? BrowserSplitDividerView }.first)
        XCTAssertEqual(divider.bounds.width, 8, accuracy: 0.1)
        let start = divider.convert(CGPoint(x: 4, y: divider.bounds.midY), to: nil)
        XCTAssertTrue(
            host.hitTest(host.convert(start, from: nil)) === divider, "The native gutter must receive pointer events")
        XCTAssertTrue(window.makeFirstResponder(terminal))
        let originalWidth = terminal.bounds.width
        let originalBrowserWidth = browser.webView.bounds.width
        var publications = 0
        let subscription = store.objectWillChange.sink { publications += 1 }
        defer { subscription.cancel() }
        window.sendEvent(try mouse(.leftMouseDown, at: start, window: window))
        for dx in [40.0, 80, 120] {
            window.sendEvent(try mouse(.leftMouseDragged, at: CGPoint(x: start.x + dx, y: start.y), window: window))
            try await Task.sleep(for: .milliseconds(80))
        }
        XCTAssertGreaterThan(terminal.bounds.width, originalWidth + 100)
        XCTAssertLessThan(browser.webView.bounds.width, originalBrowserWidth - 100)
        XCTAssertEqual(store.session(owner.id)?.browserSplitFraction, 0.5, "Preview must not persist mid-drag")
        XCTAssertEqual(publications, 0, "Mouse movement should not invalidate all terminal panes")
        XCTAssertTrue(window.firstResponder === terminal)
        window.sendEvent(try mouse(.leftMouseUp, at: CGPoint(x: start.x + 120, y: start.y), window: window))
        try await Task.sleep(for: .milliseconds(150))
        let savedFraction = try XCTUnwrap(store.session(owner.id)?.browserSplitFraction)
        XCTAssertGreaterThan(savedFraction, 0.6)
        XCTAssertEqual(publications, 1, "Release commits exactly once")
        XCTAssertTrue(terminal.superview === terminalContainer)
        XCTAssertTrue(browser.webView.superview === browserContainer)
        XCTAssertTrue(window.firstResponder === terminal)
        XCTAssertTrue(store.terminals.isRunning(owner.id))
        for dark in [false, true] {
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            try await Task.sleep(for: .milliseconds(100))
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: "/tmp/agentdeck-browser-divider-\(dark ? "dark" : "light").png"))
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        store.saveNow()
        let restored = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer { restored.shutdown() }
        XCTAssertEqual(restored.session(owner.id)?.browserSplitFraction, savedFraction)
        store.setPaneSize(for: owner.id, PaneSize(width: 600, height: 750))
        try await Task.sleep(for: .milliseconds(200))
        let stacked = try XCTUnwrap(descendants(host).compactMap { $0 as? BrowserSplitDividerView }.first)
        XCTAssertEqual(stacked.bounds.height, 8, accuracy: 0.1)
        XCTAssertTrue(terminal.superview === terminalContainer, "Axis changes retain the native terminal")
        XCTAssertTrue(browser.webView.superview === browserContainer)
        XCTAssertTrue(window.firstResponder === terminal)
        XCTAssertEqual(store.session(owner.id)?.browserSplitFraction, savedFraction)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1200, height: 900), styleMask: [.titled, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    private func mouse(_ type: NSEvent.EventType, at point: CGPoint, window: NSWindow, clicks: Int = 1) throws
        -> NSEvent
    {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: clicks, pressure: 1))
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
}
