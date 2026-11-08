import AppKit
import SwiftUI

/// Only the bottom-right grip intercepts input. Other borders and header controls retain their normal targets.
struct MiniWindowResizeOverlay: NSViewRepresentable {
    let frame: CGRect
    var minimum = CGSize(width: 320, height: 200)
    var bounds: CGRect? = nil
    var onBegin: () -> Void = {}
    let onResize: (CGRect) -> Void
    var onReset: () -> Void = {}

    func makeNSView(context: Context) -> MiniWindowResizeView {
        let view = MiniWindowResizeView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: MiniWindowResizeView, context: Context) {
        view.windowFrame = frame
        view.minimum = minimum
        view.workspaceBounds = bounds
        view.onBegin = onBegin
        view.onResize = onResize
        view.onReset = onReset
    }
}

final class MiniWindowResizeView: NSView {
    var windowFrame = CGRect.zero
    var minimum = CGSize(width: 320, height: 200)
    var workspaceBounds: CGRect?
    var onBegin: () -> Void = {}
    var onResize: (CGRect) -> Void = { _ in }
    var onReset: () -> Void = {}
    private var drag: (edge: WindowResizeEdge, frame: CGRect, point: CGPoint)?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "Drag the bottom-right grip to resize · double-click it to reset"
        setAccessibilityLabel("Resize mini window")
    }

    required init?(coder: NSCoder) { nil }

    private func regions() -> [(WindowResizeEdge, CGRect)] {
        let grip: CGFloat = 28
        let width = bounds.width
        let height = bounds.height
        return [
            (
                .bottomRight,
                CGRect(
                    x: max(0, width - grip), y: max(0, height - grip), width: min(grip, width),
                    height: min(grip, height))
            )
        ]
    }

    func edge(at point: CGPoint) -> WindowResizeEdge? {
        guard bounds.contains(point) else { return nil }
        return regions().first { $0.1.contains(point) }?.0
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHiddenOrHasHiddenAncestor, alphaValue > 0,
            edge(at: convert(point, from: superview)) != nil
        else { return nil }
        return self
    }

    override func resetCursorRects() {
        for (edge, rect) in regions() { addCursorRect(rect, cursor: cursor(for: edge)) }
    }

    private func cursor(for edge: WindowResizeEdge) -> NSCursor {
        switch edge {
        case .left, .right: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        case .topLeft, .bottomRight: return Self.diagonalDown
        case .topRight, .bottomLeft: return Self.diagonalUp
        }
    }

    private static let diagonalDown = diagonalCursor("arrow.up.left.and.arrow.down.right")
    private static let diagonalUp = diagonalCursor("arrow.up.right.and.arrow.down.left")

    private static func diagonalCursor(_ symbol: String) -> NSCursor {
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) else { return .crosshair }
        return NSCursor(image: image, hotSpot: NSPoint(x: image.size.width / 2, y: image.size.height / 2))
    }

    override func draw(_ dirtyRect: NSRect) {
        let grip = CGRect(x: bounds.maxX - 25, y: bounds.maxY - 25, width: 22, height: 22)
        NSColor.windowBackgroundColor.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: grip, xRadius: 5, yRadius: 5).fill()
        NSColor.secondaryLabelColor.setStroke()
        let lines = NSBezierPath()
        lines.lineWidth = 1.5
        for inset: CGFloat in [6, 10, 14] {
            lines.move(to: CGPoint(x: grip.maxX - inset, y: grip.maxY - 5))
            lines.line(to: CGPoint(x: grip.maxX - 5, y: grip.maxY - inset))
        }
        lines.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        guard let edge = edge(at: convert(event.locationInWindow, from: nil)) else { return }
        if event.clickCount == 2 && edge == .bottomRight {
            onReset()
            return
        }
        drag = (edge, windowFrame, event.locationInWindow)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { onBegin() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        let translation = CGSize(
            width: event.locationInWindow.x - drag.point.x,
            height: drag.point.y - event.locationInWindow.y)
        let frame = WindowResizeGeometry.resize(
            drag.frame, edge: drag.edge, translation: translation, minimum: minimum, bounds: workspaceBounds)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { onResize(frame) }
    }

    override func mouseUp(with event: NSEvent) {
        if drag != nil { mouseDragged(with: event) }
        drag = nil
    }
}
