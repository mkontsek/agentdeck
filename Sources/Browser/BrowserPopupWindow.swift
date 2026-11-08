import AppKit
import WebKit

/// A transient native window owned by its opener's BrowserController, never a persisted session.
@MainActor
final class BrowserPopupWindow: NSObject, NSWindowDelegate {
    let controller: BrowserController
    let window: NSWindow
    var onClose: (@MainActor () -> Void)?
    private var isClosed = false

    init(controller: BrowserController, features: WKWindowFeatures) {
        self.controller = controller
        let available = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1024, height: 768)
        let size = NSSize(
            width: Self.dimension(features.width, fallback: 600, minimum: 320, maximum: available.width),
            height: Self.dimension(features.height, fallback: 700, minimum: 240, maximum: available.height))
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 320, height: 240)
        window.delegate = self
        window.title = "AgentDeck — New window"
        controller.webView.autoresizingMask = [.width, .height]
        window.contentView = controller.webView
        controller.onClose = { [weak self] in self?.close() }
        controller.onStateChange = { [weak self] _ in self?.updateTitle() }
        window.center()
    }

    func show() {
        // Background agents may open sign-in windows, but keyboard focus stays with the user's current window.
        window.orderFront(nil)
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        controller.dispose()
        window.delegate = nil
        window.contentView = nil
        window.close()
        let callback = onClose
        onClose = nil
        callback?()
    }

    func windowWillClose(_ notification: Notification) { close() }

    func windowDidBecomeKey(_ notification: Notification) { controller.webView.allowsKeyboardFocus = true }

    func windowDidResignKey(_ notification: Notification) { controller.webView.allowsKeyboardFocus = false }

    private func updateTitle() {
        guard let url = controller.webView.url, let scheme = url.scheme, let host = url.host else { return }
        let port = url.port.map { ":\($0)" } ?? ""
        // Show the committed origin, not a page-controlled title or OAuth query parameters.
        window.title = "AgentDeck — \(scheme)://\(host)\(port)"
    }

    private static func dimension(_ value: NSNumber?, fallback: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat
    {
        let requested = value.map { CGFloat($0.doubleValue) } ?? fallback
        return min(maximum, max(minimum, requested.isFinite ? requested : fallback))
    }
}

/// One limit covers the entire descendant tree of a session, including nested popups.
@MainActor
final class BrowserPopupBudget {
    static let limit = 8
    var count = 0
}
