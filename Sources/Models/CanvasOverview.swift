import Foundation

/// Presentation-only canvas coordinates, without terminal text or session metadata.
struct CanvasOverviewSnapshot: Equatable {
    let bounds: CGRect
    let viewport: CGRect
    let panes: [UUID: CGRect]
    let focusedPaneID: UUID?

    init?(bounds: CGRect, viewport: CGRect, panes: [UUID: CGRect], focusedPaneID: UUID?) {
        guard Self.isValid(bounds), Self.isValid(viewport) else { return nil }
        let panes = panes.filter { Self.isValid($0.value) }
        let extent = panes.values.reduce(bounds) { $0.union($1) }
        guard Self.isValid(extent) else { return nil }
        self.bounds = extent
        let visible = viewport.intersection(extent)
        self.viewport = visible.isNull ? CGRect(origin: extent.origin, size: .zero) : visible
        self.panes = panes
        self.focusedPaneID = focusedPaneID
    }

    static func isValid(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite
            && rect.minX.isFinite && rect.minY.isFinite && rect.maxX.isFinite && rect.maxY.isFinite
            && rect.width.isFinite && rect.height.isFinite && rect.width > 0 && rect.height > 0
    }
}

/// One uniform scale preserves the relationship between windows and the viewport at any sidebar width.
struct CanvasOverviewProjection {
    let scale: CGFloat
    let origin: CGPoint
    private let bounds: CGRect

    init?(bounds: CGRect, size: CGSize) {
        let inset: CGFloat = 8
        guard CanvasOverviewSnapshot.isValid(bounds), size.width.isFinite, size.height.isFinite,
            size.width > inset * 2, size.height > inset * 2
        else { return nil }
        self.bounds = bounds
        scale = min((size.width - inset * 2) / bounds.width, (size.height - inset * 2) / bounds.height)
        origin = CGPoint(x: (size.width - bounds.width * scale) / 2, y: (size.height - bounds.height * scale) / 2)
    }

    func project(_ rect: CGRect) -> CGRect {
        CGRect(
            x: origin.x + (rect.minX - bounds.minX) * scale,
            y: origin.y + (rect.minY - bounds.minY) * scale,
            width: rect.width * scale, height: rect.height * scale)
    }
}
