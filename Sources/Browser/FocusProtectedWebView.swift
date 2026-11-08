import WebKit

/// Page autofocus and script-driven focus must not take keyboard input from another pane.
/// DOM focus still works for automation; only the selected, focused browser can become AppKit's responder.
final class FocusProtectedWebView: WKWebView {
    var allowsKeyboardFocus = false
    lazy var pageFit = BrowserPageFit(webView: self)

    override init(frame: NSRect, configuration: WKWebViewConfiguration) {
        BrowserFocusGuard.install()
        super.init(frame: frame, configuration: configuration)
    }

    required init?(coder: NSCoder) {
        BrowserFocusGuard.install()
        super.init(coder: coder)
    }

    /// Called only by an explicit pane selection; DOM automation never uses this grant.
    func requestKeyboardFocus() {
        guard let window else { return }
        allowsKeyboardFocus = true
        BrowserFocusGuard.withUserFocus(in: window) { _ = window.makeFirstResponder(self) }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = frame.width != newSize.width
        super.setFrameSize(newSize)
        if widthChanged { pageFit.requestFit() }
    }

    override var acceptsFirstResponder: Bool { allowsKeyboardFocus && super.acceptsFirstResponder }

    override func becomeFirstResponder() -> Bool {
        guard allowsKeyboardFocus else { return false }
        return super.becomeFirstResponder()
    }
}

/// Hidden automation needs a rendering window, but must never share the user's responder chain.
final class BrowserAutomationPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
