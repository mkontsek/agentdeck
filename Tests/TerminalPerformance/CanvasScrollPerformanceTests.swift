import AppKit
import QuartzCore
import SwiftUI
import XCTest

@MainActor
final class CanvasScrollPerformanceTests: XCTestCase {
    func testBusyCanvasScrollKeepsInputAndOutput() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.titled], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        defer {
            store.shutdown()
            window.close()
            try? FileManager.default.removeItem(at: directory)
        }
        var terminals: [DeckTerminalView] = []
        for index in 0..<20 {
            var session = ManagedSession(name: "Scroll fixture \(index)", kind: .cli)
            session.paneSize = PaneSize(width: 400, height: 300)
            session.canvasPosition = PanePoint(x: Double(index % 5) * 420 + 16, y: Double(index / 5) * 320 + 16)
            session.fontSizeOverride = 11
            session = store.addSession(session, start: false, focus: false)
            store.runtime[session.id]?.isRunning = true
            let terminal = store.terminals.makeView(for: session.id, font: store.font(for: session))
            terminal.suspendsRenderingWhenNotVisible = false
            terminals.append(terminal)
            if index == 0 {
                terminal.startProcess(
                    executable: "/bin/sh", args: ["-c", "stty raw -echo; printf READY; exec /bin/cat"],
                    environment: ["TERM=xterm-256color", "PATH=/usr/bin:/bin"], currentDirectory: "/tmp")
            } else {
                let script =
                    "$|=1;for($n=0;$n<3000;$n++){print \"\\e[H\";for($r=0;$r<12;$r++){printf \"scroll %06d line %02d abcdefghijklmnop\\r\\n\",$n,$r;}select undef,undef,undef,0.005;}print \"FINAL_OUTPUT\";"
                terminal.startProcess(
                    executable: "/usr/bin/perl", args: ["-e", script],
                    environment: ["TERM=xterm-256color", "PATH=/usr/bin:/bin"], currentDirectory: "/tmp")
            }
        }
        store.settings.workspaceMode = .sessions
        store.focusedSessionID = store.sessions.first?.id
        let hosting = NSHostingView(rootView: PaneGridView().environmentObject(store))
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        let focused = try XCTUnwrap(terminals.first)
        try await Task.sleep(for: .seconds(1))
        XCTAssertTrue(window.makeFirstResponder(focused))
        let scroll = try XCTUnwrap(
            descendants(hosting).compactMap { $0 as? CanvasNavigationTarget }.first?.enclosingScrollView)
        if ProcessInfo.processInfo.environment["AGENTDECK_SCROLL_BASELINE"] == "1" {
            for observer in descendants(hosting).compactMap({ $0 as? CanvasScrollObservationView }) {
                observer.disconnect()
            }
        }
        let ids = store.sessions.map(\.id)
        for terminal in terminals { terminal.resetDiagnostics() }
        var samples: [Double] = []
        var inputMs: [Double] = []
        var peakScroll = 0.0
        print("SCROLL_FIXTURE_PID \(ProcessInfo.processInfo.processIdentifier)")
        for index in 0..<240 {
            let start = CACurrentMediaTime()
            let event = try XCTUnwrap(
                CGEvent(
                    scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                    wheel1: index < 120 ? -3 : 3, wheel2: index < 120 ? -4 : 4, wheel3: 0))
            let phase: NSEvent.Phase = index == 0 ? .began : .changed
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
            scroll.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: event)))
            let step = Double(index < 120 ? index : 239 - index)
            scroll.contentView.scroll(to: CGPoint(x: step * 4, y: step * 3))
            scroll.reflectScrolledClipView(scroll.contentView)
            peakScroll = max(peakScroll, scroll.contentView.bounds.minY)
            if index == 30, ProcessInfo.processInfo.environment["AGENTDECK_SCROLL_BASELINE"] != "1" {
                XCTAssertTrue(terminals.dropFirst().allSatisfy(\.defersCanvasDisplay))
                XCTAssertFalse(focused.defersCanvasDisplay)
            }
            if index % 12 == 0 {
                let inputStart = CACurrentMediaTime()
                let received = focused.diagnostics.bytesFed
                focused.insertText("X", replacementRange: NSRange(location: NSNotFound, length: 0))
                for _ in 0..<1000 where focused.diagnostics.bytesFed <= received {
                    try await Task.sleep(for: .milliseconds(1))
                }
                XCTAssertGreaterThan(focused.diagnostics.bytesFed, received)
                inputMs.append((CACurrentMediaTime() - inputStart) * 1000)
            }
            try await Task.sleep(for: .milliseconds(16))
            samples.append((CACurrentMediaTime() - start) * 1000)
        }
        let end = try XCTUnwrap(
            CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 0, wheel2: 0, wheel3: 0))
        end.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(NSEvent.Phase.ended.rawValue))
        scroll.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: end)))
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertGreaterThan(peakScroll, 10)
        XCTAssertTrue(window.firstResponder === focused)
        XCTAssertTrue(terminals.allSatisfy { $0.process.running })
        XCTAssertTrue(terminals.allSatisfy { !$0.isHidden })
        XCTAssertFalse(focused.defersCanvasDisplay)
        XCTAssertTrue(terminals.dropFirst().allSatisfy { $0.diagnostics.bytesFed > 1000 })
        XCTAssertTrue(store.terminals.visibleLines(id: ids[0]).joined().contains(String(repeating: "X", count: 20)))
        let sorted = samples.sorted()
        let inputSorted = inputMs.sorted()
        print(
            "SCROLL_PERF p95FrameMs=\(sorted[Int(Double(sorted.count - 1) * 0.95)]) p95InputMs=\(inputSorted[Int(Double(inputSorted.count - 1) * 0.95)]) renders=\(terminals.reduce(0) { $0 + $1.diagnostics.renders }) batches=\(terminals.reduce(0) { $0 + $1.diagnostics.batches }) scrollY=\(scroll.contentView.bounds.minY)"
        )
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
}
