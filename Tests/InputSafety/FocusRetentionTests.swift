import AppKit
import SwiftUI
import WebKit
import XCTest

@MainActor
final class FocusRetentionTests: XCTestCase {
    func testPassiveRepresentationUpdatePreservesLaterEditorSelection() async throws {
        let window = makeWindow()
        defer { window.close() }
        let terminal = DeckTerminalView(frame: CGRect(x: 0, y: 0, width: 250, height: 200))
        let host = NSHostingView(
            rootView: TerminalRepresentable(
                terminal: terminal,
                font: .monospacedSystemFont(ofSize: 12, weight: .regular), focused: false, generation: 1))
        host.frame = terminal.frame
        window.contentView?.addSubview(host)
        let editor = NSTextView(frame: CGRect(x: 300, y: 0, width: 250, height: 200))
        window.contentView?.addSubview(editor)
        editor.string = "partial multiline\nΩ fixture"
        editor.setSelectedRange(NSRange(location: 2, length: 6))
        XCTAssertTrue(window.makeFirstResponder(editor))
        host.rootView = TerminalRepresentable(
            terminal: terminal,
            font: .monospacedSystemFont(ofSize: 13, weight: .regular), focused: true, generation: 1)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(window.firstResponder === editor)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 2, length: 6))
        XCTAssertEqual(editor.string, "partial multiline\nΩ fixture")
    }

    func testDelayedTerminalAttachmentCannotTakeAnExistingEditor() throws {
        let window = makeWindow()
        defer { window.close() }
        let editor = NSTextView(frame: CGRect(x: 0, y: 0, width: 200, height: 150))
        window.contentView?.addSubview(editor)
        editor.string = "partial žluťoučký\nsecond line"
        editor.setSelectedRange(NSRange(location: 4, length: 3))
        XCTAssertTrue(window.makeFirstResponder(editor))
        let container = TerminalContainerView(frame: CGRect(x: 220, y: 0, width: 200, height: 150))
        container.addSubview(DeckTerminalView(frame: container.bounds))
        container.focusWhenAttached = true
        window.contentView?.addSubview(container)
        XCTAssertTrue(window.firstResponder === editor, "A deferred mount must not steal typing focus")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 4, length: 3))
        XCTAssertEqual(editor.string, "partial žluťoučký\nsecond line")
    }

    func testVisibleInactiveWebKitCannotStealTerminalFocus() async throws {
        let window = makeWindow()
        defer { window.close() }
        let terminal = DeckTerminalView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        window.contentView?.addSubview(terminal)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let browser = FocusProtectedWebView(
            frame: CGRect(x: 300, y: 0, width: 300, height: 300), configuration: configuration)
        browser.allowsKeyboardFocus = false
        window.contentView?.addSubview(browser)
        XCTAssertTrue(window.makeFirstResponder(terminal))
        browser.loadHTMLString("<input id='q' autofocus><script>setInterval(()=>q.focus(),30)</script>", baseURL: nil)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(window.firstResponder === terminal, "Visible inactive page autofocus stole native focus")
        for _ in 0..<200 where browser.isLoading { try await Task.sleep(for: .milliseconds(10)) }
        let error: Error? = await withCheckedContinuation { continuation in
            browser.evaluateJavaScript(
                "document.getElementById('q').focus(); document.getElementById('q').value='fixture'; null"
            ) { _, error in
                continuation.resume(returning: error)
            }
        }
        XCTAssertNil(error)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(window.firstResponder === terminal, "DOM automation stole native focus")
        let editor = NSTextView(frame: CGRect(x: 0, y: 310, width: 300, height: 60))
        window.contentView?.addSubview(editor)
        editor.string = "partial Ω\nsecond line"
        editor.setSelectedRange(NSRange(location: 3, length: 4))
        XCTAssertTrue(window.makeFirstResponder(editor))
        browser.allowsKeyboardFocus = true
        XCTAssertFalse(window.makeFirstResponder(browser), "Even a selected page cannot take a separate text editor")
        XCTAssertTrue(window.firstResponder === editor)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 3, length: 4))
        editor.setMarkedText(
            "žluť", selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertFalse(window.makeFirstResponder(browser))
        XCTAssertTrue(editor.hasMarkedText(), "Focus rejection must not commit/cancel IME composition")
        XCTAssertTrue(window.firstResponder === editor)
        browser.requestKeyboardFocus()
        XCTAssertTrue(window.firstResponder === browser, "Explicit pane selection still focuses the browser")
        XCTAssertTrue(window.makeFirstResponder(editor))
        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: browser.convert(CGPoint(x: 60, y: 50), to: nil), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1))
        window.sendEvent(event)
        XCTAssertTrue(window.firstResponder === browser, "A real mouse event must keep the page interactive")
        let field = NSTextField(frame: CGRect(x: 0, y: 310, width: 200, height: 30))
        window.contentView?.addSubview(field)
        field.nextKeyView = browser
        XCTAssertTrue(window.makeFirstResponder(field))
        let tab = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48))
        window.sendEvent(tab)
        XCTAssertTrue(window.firstResponder === browser, "Native Tab navigation remains available")
        browser.stopLoading()
        browser.pageFit.cancel()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 640, height: 400), styleMask: [.titled], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = FlippedFocusFixtureView(frame: window.contentLayoutRect)
        window.orderFrontRegardless()
        return window
    }
}

private final class FlippedFocusFixtureView: NSView {
    override var isFlipped: Bool { true }
}
