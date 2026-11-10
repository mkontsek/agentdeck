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

        func matches(_ snapshot: CanvasOverviewSnapshot?) -> Bool {
            guard let snapshot, snapshot.bounds == canvasBounds else { return false }
            // Native coordinate conversion can round a scroll-dependent edge by a fraction of a point.
            let size = snapshot.unclippedViewport.size
            return abs(size.width - viewportSize.width) < 0.5 && abs(size.height - viewportSize.height) < 0.5
        }
    }
    private var drag: Drag?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func configure(overview: CanvasOverviewState, snapshot: CanvasOverviewSnapshot?) {
        if self.overview !== overview || drag.map({ !$0.matches(snapshot) }) == true {
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
            ? CGPoint(
                x: canvasPoint.x - snapshot.unclippedViewport.minX, y: canvasPoint.y - snapshot.unclippedViewport.minY)
            : CGPoint(x: snapshot.unclippedViewport.width / 2, y: snapshot.unclippedViewport.height / 2)
        drag = Drag(
            sourceID: sourceID, canvasBounds: snapshot.bounds, viewportSize: snapshot.unclippedViewport.size,
            mapSize: bounds.size, projection: projection, anchor: anchor)
        if !inside { mouseDragged(with: event) }
        window?.invalidateCursorRects(for: self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag, window != nil, let overview, overview.navigationID == drag.sourceID,
            bounds.size == drag.mapSize, drag.matches(snapshot), drag.matches(overview.snapshot),
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
