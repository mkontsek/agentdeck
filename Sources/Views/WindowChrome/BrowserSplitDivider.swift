import AppKit
import SwiftUI

struct BrowserSplitDivider: NSViewRepresentable {
    let ownerID: UUID
    let geometry: BrowserSplitGeometry
    let onPreview: (Double) -> Void
    let onFinish: (Double?) -> Void

    func makeNSView(context: Context) -> BrowserSplitDividerView {
        let view = BrowserSplitDividerView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: BrowserSplitDividerView, context: Context) {
        view.configure(ownerID: ownerID, geometry: geometry)
        view.onPreview = onPreview
        view.onFinish = onFinish
    }
}

/// Window coordinates stay stable while the divider itself moves under the pointer.
final class BrowserSplitDividerView: NSView {
    var onPreview: (Double) -> Void = { _ in }
    var onFinish: (Double?) -> Void = { _ in }
    private var ownerID: UUID?
    private var geometry = BrowserSplitGeometry(size: .zero, isHorizontal: true, fraction: 0.5)
    private var drag: (point: CGPoint, startFraction: Double, lastFraction: Double)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "Drag to resize terminal and browser · double-click for equal sizes"
    }

    required init?(coder: NSCoder) { nil }

    func configure(ownerID: UUID, geometry: BrowserSplitGeometry) {
        if self.ownerID != ownerID || self.geometry.size != geometry.size
            || self.geometry.isHorizontal != geometry.isHorizontal
        {
            drag = nil
        }
        if self.geometry.isHorizontal != geometry.isHorizontal { window?.invalidateCursorRects(for: self) }
        self.ownerID = ownerID
        self.geometry = geometry
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        drag = nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: geometry.isHorizontal ? .resizeLeftRight : .resizeUpDown)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        let line =
            geometry.isHorizontal
            ? CGRect(x: bounds.midX - 0.5, y: 0, width: 1, height: bounds.height)
            : CGRect(x: 0, y: bounds.midY - 0.5, width: bounds.width, height: 1)
        line.fill()
        NSColor.secondaryLabelColor.setFill()
        for offset in [-4.0, 0, 4] {
            let dot = CGRect(
                x: bounds.midX - 1 + (geometry.isHorizontal ? 0 : offset),
                y: bounds.midY - 1 + (geometry.isHorizontal ? offset : 0), width: 2, height: 2)
            NSBezierPath(ovalIn: dot).fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard window != nil, geometry.availableExtent > 0 else { return }
        if event.clickCount == 2 {
            drag = nil
            finish(BrowserSplitGeometry.defaultFraction)
            return
        }
        let fraction = geometry.displayedFraction
        drag = (event.locationInWindow, fraction, fraction)
    }

    override func mouseDragged(with event: NSEvent) {
        guard var drag, window != nil, geometry.availableExtent > 0 else { return }
        let delta =
            geometry.isHorizontal
            ? event.locationInWindow.x - drag.point.x : drag.point.y - event.locationInWindow.y
        let sizing = BrowserSplitGeometry(
            size: geometry.size, isHorizontal: geometry.isHorizontal,
            fraction: drag.startFraction + Double(delta / geometry.availableExtent))
        let fraction = sizing.displayedFraction
        guard fraction != drag.lastFraction else { return }
        drag.lastFraction = fraction
        self.drag = drag
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { onPreview(fraction) }
    }

    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        guard let drag else { return }
        self.drag = nil
        finish(drag.lastFraction == drag.startFraction ? nil : drag.lastFraction)
    }

    private func finish(_ fraction: Double?) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { onFinish(fraction) }
    }
}
