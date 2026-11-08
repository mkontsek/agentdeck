import AppKit
import Combine
import QuartzCore
import SwiftTerm
import SwiftUI
import WebKit
import XCTest

@MainActor
final class TerminalLatencyTests: XCTestCase {
    func testNativeTerminalLatencyUnderTwentyPTYsAndBrowsers() async throws {
        try await measureNativePath()
    }

    private func measureNativePath() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        let host = store.terminals
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1500, height: 1000), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "AgentDeck isolated terminal performance fixture"
        let root = NSView(frame: window.contentLayoutRect)
        window.contentView = root
        var ids: [UUID] = []
        var browsers: [WKWebView] = []
        defer {
            for id in ids { host.dispose(id: id) }
            for browser in browsers {
                browser.stopLoading()
                browser.removeFromSuperview()
            }
            window.close()
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        // No provider, startup files, network, persisted browser profile, or user terminal is used.
        for index in 0..<20 {
            var session = ManagedSession(name: "Fixture", kind: .cli)
            session.autoStart = false
            session = store.addSession(session, start: false)
            let id = session.id
            store.runtime[id]?.isRunning = true
            ids.append(id)
            let view = host.makeView(for: id, font: .monospacedSystemFont(ofSize: 10, weight: .regular))
            view.frame = NSRect(x: (index % 5) * 300, y: 200 + (index / 5) * 200, width: 300, height: 200)

            view.suspendsRenderingWhenNotVisible = false
        }
        for index in 0..<2 {
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent()
            let browser = WKWebView(frame: NSRect(x: index * 750, y: 0, width: 750, height: 190), configuration: config)
            root.addSubview(browser)
            browser.loadHTMLString(
                "<style>body{background:#223;color:white}</style><p>Local animation fixture</p><progress id='p'></progress><script>let n=0;setInterval(()=>p.value=(++n%100)/100,16)</script>",
                baseURL: nil)
            browsers.append(browser)
        }
        store.settings.workspaceMode = .sessions
        store.settings.layoutMode = .grid
        store.settings.gridColumns = 5
        store.settings.showUsagePanel = false
        store.focusedSessionID = ids[0]
        let hosting = NSHostingView(rootView: PaneGridView().environmentObject(store))
        hosting.frame = NSRect(x: 0, y: 200, width: 1500, height: 800)
        root.addSubview(hosting)
        window.orderFrontRegardless()
        let focused = try XCTUnwrap(host.view(for: ids[0]))
        window.makeFirstResponder(focused)
        for id in ids {
            let view = try XCTUnwrap(host.view(for: id))
            let script: String
            if id == ids[0] {
                script = "stty raw -echo; printf READY; exec /bin/cat"
                view.startProcess(
                    executable: "/bin/sh", args: ["-c", script],
                    environment: ["TERM=xterm-256color", "PATH=/usr/bin:/bin"], currentDirectory: "/tmp")
            } else {
                // 100 screen updates/sec per terminal, bounded lifetime even if the test fails.
                script =
                    "$|=1; for($n=0;$n<2000;$n++){print \"\\e]0;Fixture title\\a\\e]7501;state=working:msg=V29ya2luZw\\a\\e[H\"; for($r=0;$r<10;$r++){printf \"fixture %06d row %02d abcdefghijklmn\\r\\n\",$n,$r;} select undef,undef,undef,0.01;}"
                view.startProcess(
                    executable: "/usr/bin/perl", args: ["-e", script],
                    environment: ["TERM=xterm-256color", "PATH=/usr/bin:/bin"], currentDirectory: "/tmp")
            }
        }
        try await until { host.visibleLines(id: ids[0]).joined().contains("READY") }
        try await Task.sleep(for: .seconds(1))
        if ProcessInfo.processInfo.environment["AGENTDECK_SCROLL_BASELINE"] == "1" {
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            for observer in descendants(hosting).compactMap({ $0 as? CanvasScrollObservationView }) {
                observer.disconnect()
            }
        }
        for id in ids { host.view(for: id)?.resetDiagnostics() }
        var storeChanges = 0
        let observation = store.objectWillChange.sink { storeChanges += 1 }
        var callbackCount = 0
        host.onOutput = { _ in callbackCount += 1 }
        var parsedMs: [Double] = []
        var renderedMs: [Double] = []
        var keyCallMs: [Double] = []
        var mainDelayMs: [Double] = []
        var expected = "READY"
        let start = CACurrentMediaTime()
        for index in 0..<80 {
            if index % 20 == 0 {
                focused.send(txt: "\r\n")
                expected = ""
                try await Task.sleep(for: .milliseconds(10))
            }
            let character = String(UnicodeScalar(97 + index % 26)!)
            expected += character
            let renders = focused.diagnostics.renders
            let t = CACurrentMediaTime()
            let event = try XCTUnwrap(
                NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [], timestamp: t,
                    windowNumber: window.windowNumber, context: nil, characters: character,
                    charactersIgnoringModifiers: character, isARepeat: false, keyCode: 0))
            focused.keyDown(with: event)
            if ProcessInfo.processInfo.environment["AGENTDECK_SCROLL_BASELINE"] != "1" {
                XCTAssertFalse(focused.defersCanvasDisplay)
                XCTAssertTrue(
                    host.views.values.filter { $0 !== focused }.allSatisfy(\.defersCanvasDisplay),
                    "Typing keeps the foreground live and defers background painting")
            }
            keyCallMs.append((CACurrentMediaTime() - t) * 1000)
            try await until { host.visibleLines(id: ids[0]).contains(expected) }
            parsedMs.append((CACurrentMediaTime() - t) * 1000)
            try await until { focused.diagnostics.renders > renders }
            renderedMs.append((CACurrentMediaTime() - t) * 1000)
            let wake = CACurrentMediaTime()
            try await Task.sleep(for: .milliseconds(10))
            mainDelayMs.append(max(0, (CACurrentMediaTime() - wake) * 1000 - 10))
        }
        XCTAssertLessThan(storeChanges, 20, "Stable terminal metadata must not continuously invalidate the canvas")
        XCTAssertTrue(window.firstResponder === focused)
        XCTAssertTrue(host.visibleLines(id: ids[0]).contains(expected))
        let totals = ids.compactMap { host.view(for: $0)?.diagnostics }
        let report: [String: Any] = [
            "storeChanges": storeChanges, "metal": focused.isUsingMetalRenderer,
            "seconds": CACurrentMediaTime() - start,
            "terminals": ids.count,
            "browserPanes": browsers.count, "keyCallMs": summary(keyCallMs),
            "keyToParsedMs": summary(parsedMs), "keyToRenderObservedMs": summary(renderedMs),
            "mainWakeDelayMs": summary(mainDelayMs), "outputCallbacks": callbackCount,
            "bytes": totals.reduce(0) { $0 + $1.bytesFed }, "batches": totals.reduce(0) { $0 + $1.batches },
            "renders": totals.reduce(0) { $0 + $1.renders },
            "renderLoopFrames": totals.reduce(0) { $0 + $1.renderLoopFrames },
        ]
        let bitmap = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
        root.cacheDisplay(in: root.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "Native terminal performance fixture"
        attachment.lifetime = .keepAlways
        add(attachment)
        try png.write(to: URL(fileURLWithPath: "/tmp/agentdeck-task81-performance.png"))
        withExtendedLifetime(observation) {}
        print(
            "TERMINAL_PERF "
                + String(
                    decoding: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), as: UTF8.self)
        )
    }

    private func summary(_ samples: [Double]) -> [String: Double] {
        let sorted = samples.sorted()
        return [
            "p50": sorted[sorted.count / 2], "p95": sorted[Int(Double(sorted.count - 1) * 0.95)],
            "max": sorted.last ?? 0,
        ]
    }

    private func until(_ condition: () -> Bool) async throws {
        let deadline = CACurrentMediaTime() + 5
        while !condition(), CACurrentMediaTime() < deadline { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertTrue(condition(), "Native terminal fixture timed out")
    }
}
