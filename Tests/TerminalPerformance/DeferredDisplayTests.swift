import AppKit
import XCTest

@MainActor
final class DeferredDisplayTests: XCTestCase {
    func testDeferredPaintKeepsPTYBytesFocusAndCatchesUp() async throws {
        let host = TerminalHost()
        let id = UUID()
        let terminal = host.makeView(for: id, font: .monospacedSystemFont(ofSize: 11, weight: .regular))
        terminal.suspendsRenderingWhenNotVisible = false
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 640, height: 440), styleMask: [.titled], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = terminal
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(terminal)
        defer {
            terminal.defersCanvasDisplay = false
            host.dispose(id: id)
            window.close()
        }
        terminal.startProcess(
            executable: "/bin/sh", args: ["-c", "stty raw -echo; printf READY; exec /bin/cat"],
            environment: ["TERM=xterm-256color", "PATH=/usr/bin:/bin"], currentDirectory: "/tmp")
        for _ in 0..<1000 where terminal.diagnostics.bytesFed < 5 || terminal.diagnostics.renders == 0 {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(host.visibleLines(id: id).joined().contains("READY"))
        terminal.defersCanvasDisplay = true
        try await Task.sleep(for: .milliseconds(50))
        let draws = terminal.diagnostics.renders
        let before = terminal.diagnostics.bytesFed
        let message = " held-Ω-output"
        terminal.send(txt: message)
        for _ in 0..<1000 where terminal.diagnostics.bytesFed < before + message.utf8.count {
            try await Task.sleep(for: .milliseconds(2))
        }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(terminal.diagnostics.bytesFed, before + message.utf8.count)
        XCTAssertEqual(terminal.diagnostics.renders, draws, "Painting pauses while bytes continue to parse")
        XCTAssertTrue(window.firstResponder === terminal)
        XCTAssertTrue(host.visibleLines(id: id).joined().contains(message))
        terminal.defersCanvasDisplay = false
        for _ in 0..<1000 where terminal.diagnostics.renders == draws { try await Task.sleep(for: .milliseconds(2)) }
        XCTAssertGreaterThan(terminal.diagnostics.renders, draws, "Releasing the hold paints the newest screen")
        terminal.insertText("Z", replacementRange: NSRange(location: NSNotFound, length: 0))
        for _ in 0..<1000 where terminal.diagnostics.bytesFed < before + message.utf8.count + 1 {
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertTrue(host.visibleLines(id: id).joined().contains(message + "Z"))
        XCTAssertTrue(host.isRunning(id))
    }
}
