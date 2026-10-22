import AppKit
import SwiftUI

/// Consume an inactive pane's first click before its terminal or web page sees it.
struct PaneFocusOverlay: NSViewRepresentable {
    let onFocus: () -> Void

    func makeNSView(context: Context) -> FocusClickView {
        let view = FocusClickView()
        view.onFocus = onFocus
        return view
    }

    func updateNSView(_ view: FocusClickView, context: Context) {
        view.onFocus = onFocus
    }
}

final class FocusClickView: NSView {
    var onFocus: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { onFocus?() }
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
}
