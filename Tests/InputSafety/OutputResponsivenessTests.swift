import AppKit
import Combine
import QuartzCore
import SwiftUI
import XCTest

@MainActor
final class OutputResponsivenessTests: XCTestCase {
    func testChangingProviderMetadataDoesNotBlockNativeOutput() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        store.settings.workspaceMode = .sessions
        store.settings.showUsagePanel = false
        store.settings.layoutMode = .grid
        store.settings.gridColumns = 5
        for index in 0..<20 {
            let session = store.addSession(
                ManagedSession(name: "Output \(index)", kind: .cli), start: false, focus: false)
            store.runtime[session.id]?.isRunning = true
            _ = store.terminals.makeView(for: session.id, font: store.font(for: session))
        }
        let first = try XCTUnwrap(store.sessions.first)
        store.focusedSessionID = first.id
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1400, height: 900),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PaneGridView().environmentObject(store))
        window.orderFrontRegardless()
        defer {
            store.shutdown()
            window.close()
            try? FileManager.default.removeItem(at: directory)
        }
        let focused = try XCTUnwrap(store.terminals.view(for: first.id))
        window.makeFirstResponder(focused)
        for session in store.sessions {
            let terminal = try XCTUnwrap(store.terminals.view(for: session.id))
            terminal.suspendsRenderingWhenNotVisible = false
            if session.id == first.id {
                terminal.startProcess(
                    executable: "/bin/sh", args: ["-c", "stty raw -echo; printf READY; exec /bin/cat"],
                    environment: ["TERM=xterm-256color", "PATH=/usr/bin:/bin"], currentDirectory: "/tmp")
            } else {
                let script =
                    "$|=1; for($n=0;$n<1000;$n++){print \"\\e]0;Progress $n\\a\\e[Hframe $n\\r\\n\"; select undef,undef,undef,0.02;}"
                terminal.startProcess(
                    executable: "/usr/bin/perl", args: ["-e", script],
                    environment: ["TERM=xterm-256color", "PATH=/usr/bin:/bin"], currentDirectory: "/tmp")
            }
        }
        for _ in 0..<500 where !store.terminals.visibleLines(id: first.id).joined().contains("READY") {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(store.terminals.visibleLines(id: first.id).joined().contains("READY"))
        var publications = 0
        let observation = store.objectWillChange.sink { publications += 1 }
        var samples: [Double] = []
        for _ in 0..<40 {
            let beforeBytes = focused.diagnostics.bytesFed
            let beforeRender = focused.diagnostics.renders
            let started = CACurrentMediaTime()
            // This measures asynchronous output while the user is reading, not the typing optimization.
            focused.send(txt: "read-Ω\r\n")
            while (focused.diagnostics.bytesFed <= beforeBytes || focused.diagnostics.renders <= beforeRender)
                && CACurrentMediaTime() - started < 2
            {
                try await Task.sleep(for: .milliseconds(1))
            }
            XCTAssertGreaterThan(focused.diagnostics.bytesFed, beforeBytes)
            XCTAssertGreaterThan(focused.diagnostics.renders, beforeRender)
            samples.append((CACurrentMediaTime() - started) * 1000)
            try await Task.sleep(for: .milliseconds(20))
        }
        samples.sort()
        print(
            "OUTPUT_RESPONSIVENESS p50_ms=\(samples[20]) p95_ms=\(samples[37]) max_ms=\(samples.last ?? 0) publications=\(publications)"
        )
        XCTAssertLessThan(publications, 100, "Changing provider titles must be coalesced across sessions")
        XCTAssertTrue(window.firstResponder === focused)
        withExtendedLifetime(observation) {}
    }
}
