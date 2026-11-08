import AppKit
import SwiftUI

struct MiniWindowMoveHandle: NSViewRepresentable {
    let name: String
    let onBegin: () -> Void
    let onMove: (CGSize) -> Void
    let onEnd: (CGSize) -> Void
    var movable = true
    var drawsGrip = true
    var onDoubleClick: () -> Void = {}

    func makeNSView(context: Context) -> MiniWindowMoveView {
        let view = MiniWindowMoveView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: MiniWindowMoveView, context: Context) {
        view.setAccessibilityLabel("Move \(name) window")
        view.onBegin = onBegin
        view.onMove = onMove
        view.onEnd = onEnd
        view.movable = movable
        view.drawsGrip = drawsGrip
        view.onDoubleClick = onDoubleClick
    }
}

final class MiniWindowMoveView: NSView {
    var onBegin: () -> Void = {}
    var onMove: (CGSize) -> Void = { _ in }
    var onEnd: (CGSize) -> Void = { _ in }
    var onDoubleClick: () -> Void = {}
    var movable = true
    var drawsGrip = true
    private var start: CGPoint?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() { addCursorRect(bounds, cursor: movable ? .openHand : .arrow) }

    override func draw(_ dirtyRect: NSRect) {
        guard drawsGrip else { return }
        NSColor.secondaryLabelColor.setStroke()
        let path = NSBezierPath()
        for y in [-3.0, 0, 3] {
            path.move(to: CGPoint(x: bounds.midX - 5, y: bounds.midY + y))
            path.line(to: CGPoint(x: bounds.midX + 5, y: bounds.midY + y))
        }
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            start = nil
            onDoubleClick()
            return
        }
        start = movable ? event.locationInWindow : nil
        onBegin()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        onMove(CGSize(width: event.locationInWindow.x - start.x, height: start.y - event.locationInWindow.y))
    }

    override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        self.start = nil
        onEnd(CGSize(width: event.locationInWindow.x - start.x, height: start.y - event.locationInWindow.y))
    }
}
