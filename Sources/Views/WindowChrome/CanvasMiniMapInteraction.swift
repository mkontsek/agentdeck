import AppKit
import SwiftUI

struct CanvasMiniMapInteraction: NSViewRepresentable {
    let overview: CanvasOverviewState
    let snapshot: CanvasOverviewSnapshot?

    func makeNSView(context: Context) -> CanvasMiniMapInputView {
        let view = CanvasMiniMapInputView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: CanvasMiniMapInputView, context: Context) {
        view.configure(overview: overview, snapshot: snapshot)
    }
}

/// The map receives pointer events without becoming the keyboard responder.
final class CanvasMiniMapInputView: NSView {
    private weak var overview: CanvasOverviewState?
    private var snapshot: CanvasOverviewSnapshot?
    private struct Drag {
        let sourceID: UUID
        let canvasBounds: CGRect
        let viewportSize: CGSize
        let mapSize: CGSize
        let projection: CanvasOverviewProjection
        let anchor: CGPoint
    }
    private var drag: Drag?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func configure(overview: CanvasOverviewState, snapshot: CanvasOverviewSnapshot?) {
        if self.overview !== overview || self.snapshot?.bounds != snapshot?.bounds
            || self.snapshot?.viewport.size != snapshot?.viewport.size
        {
            drag = nil
        }
        self.overview = overview
        self.snapshot = snapshot
        window?.invalidateCursorRects(for: self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        drag = nil
    }

    override func resetCursorRects() {
        guard overview?.navigationID != nil, let snapshot,
            let projection = CanvasOverviewProjection(bounds: snapshot.bounds, size: bounds.size)
        else { return }
        addCursorRect(bounds, cursor: drag == nil ? .pointingHand : .closedHand)
        addCursorRect(projection.project(snapshot.viewport), cursor: drag == nil ? .openHand : .closedHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard window != nil, let sourceID = overview?.navigationID, let snapshot, snapshot == overview?.snapshot,
            let projection = CanvasOverviewProjection(bounds: snapshot.bounds, size: bounds.size)
        else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let canvasPoint = projection.unproject(point) else { return }
        let inside = projection.project(snapshot.viewport).contains(point)
        let anchor =
            inside
            ? CGPoint(x: canvasPoint.x - snapshot.viewport.minX, y: canvasPoint.y - snapshot.viewport.minY)
            : CGPoint(x: snapshot.viewport.width / 2, y: snapshot.viewport.height / 2)
        drag = Drag(
            sourceID: sourceID, canvasBounds: snapshot.bounds, viewportSize: snapshot.viewport.size,
            mapSize: bounds.size, projection: projection, anchor: anchor)
        if !inside { mouseDragged(with: event) }
        window?.invalidateCursorRects(for: self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag, window != nil, let overview, overview.navigationID == drag.sourceID,
            bounds.size == drag.mapSize, snapshot?.bounds == drag.canvasBounds,
            snapshot?.viewport.size == drag.viewportSize,
            overview.snapshot?.bounds == drag.canvasBounds, overview.snapshot?.viewport.size == drag.viewportSize,
            let point = drag.projection.unproject(convert(event.locationInWindow, from: nil))
        else {
            self.drag = nil
            return
        }
        overview.moveViewport(to: CGPoint(x: point.x - drag.anchor.x, y: point.y - drag.anchor.y), from: drag.sourceID)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        drag = nil
        window?.invalidateCursorRects(for: self)
    }
}
