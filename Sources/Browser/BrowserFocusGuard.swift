import AppKit
import ObjectiveC

/// WebKit asks NSWindow for focus before WKWebView can reject it. AppKit has already resigned the
/// previous editor by then. Reject at that boundary, without ever resigning/restoring the editor.
/// The interception is limited to this app's FocusProtectedWebView targets; other windows/views
/// follow AppKit unchanged. No text, selection, clipboard or timing heuristic is involved.
@MainActor
enum BrowserFocusGuard {
    private static var userFocusWindows: [ObjectIdentifier: Int] = [:]
    private static let installation: Void = {
        exchange(#selector(NSWindow.makeFirstResponder(_:)), #selector(NSWindow.agentDeckMakeFirstResponder(_:)))
        exchange(#selector(NSWindow.sendEvent(_:)), #selector(NSWindow.agentDeckSendEvent(_:)))
    }()

    static func install() { _ = installation }

    private static func exchange(_ original: Selector, _ replacement: Selector) {
        guard let first = class_getInstanceMethod(NSWindow.self, original),
            let second = class_getInstanceMethod(NSWindow.self, replacement)
        else { preconditionFailure("Required AppKit responder boundary is unavailable") }
        method_exchangeImplementations(first, second)
    }

    static func browser(containing responder: NSResponder?) -> FocusProtectedWebView? {
        var view = responder as? NSView
        while let current = view {
            if let browser = current as? FocusProtectedWebView { return browser }
            view = current.superview
        }
        return nil
    }

    static func permits(_ responder: NSResponder?, in window: NSWindow) -> Bool {
        guard let target = browser(containing: responder) else { return true }
        guard target.allowsKeyboardFocus else { return false }
        return browser(containing: window.firstResponder) === target
            || userFocusWindows[ObjectIdentifier(window), default: 0] > 0
    }

    static func withUserFocus<T>(in window: NSWindow, _ action: () -> T) -> T {
        let id = ObjectIdentifier(window)
        userFocusWindows[id, default: 0] += 1
        defer {
            let remaining = userFocusWindows[id, default: 1] - 1
            userFocusWindows[id] = remaining == 0 ? nil : remaining
        }
        return action()
    }

    static func clickedBrowser(_ event: NSEvent, in window: NSWindow) -> FocusProtectedWebView? {
        guard event.type == .leftMouseDown, let content = window.contentView else { return nil }
        // hitTest takes the receiver's *superview* coordinates, including a flipped NSHostingView.
        let point = content.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
        return browser(containing: content.hitTest(point))
    }
}

extension NSWindow {
    @objc fileprivate dynamic func agentDeckMakeFirstResponder(_ responder: NSResponder?) -> Bool {
        guard BrowserFocusGuard.permits(responder, in: self) else { return false }
        return agentDeckMakeFirstResponder(responder)  // Original implementation after exchange.
    }

    @objc fileprivate dynamic func agentDeckSendEvent(_ event: NSEvent) {
        if let browser = BrowserFocusGuard.clickedBrowser(event, in: self), browser.allowsKeyboardFocus {
            // WebKit can ask asynchronously after mouse dispatch. Grant the real click now, not
            // an open-ended permission that a later script could use to take another editor.
            browser.requestKeyboardFocus()
            agentDeckSendEvent(event)
        } else if event.type == .keyDown && event.keyCode == 48 {
            BrowserFocusGuard.withUserFocus(in: self) { agentDeckSendEvent(event) }
        } else {
            agentDeckSendEvent(event)
        }
    }
}
