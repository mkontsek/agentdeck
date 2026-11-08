import Foundation

enum WindowResizeEdge: CaseIterable {
    case top, bottom, left, right, topLeft, topRight, bottomLeft, bottomRight

    var movesLeft: Bool { self == .left || self == .topLeft || self == .bottomLeft }
    var movesRight: Bool { self == .right || self == .topRight || self == .bottomRight }
    var movesTop: Bool { self == .top || self == .topLeft || self == .topRight }
    var movesBottom: Bool { self == .bottom || self == .bottomLeft || self == .bottomRight }
}

enum WindowResizeGeometry {
    /// Keep the opposite edge anchored, including when the minimum size or workspace boundary is reached.
    static func resize(
        _ start: CGRect, edge: WindowResizeEdge, translation: CGSize, minimum: CGSize,
        bounds: CGRect? = nil
    ) -> CGRect {
        var left = start.minX
        var right = start.maxX
        var top = start.minY
        var bottom = start.maxY
        if edge.movesLeft {
            left = min(max(bounds?.minX ?? 0, left + translation.width), right - minimum.width)
        }
        if edge.movesRight {
            right = max(left + minimum.width, min(bounds?.maxX ?? .greatestFiniteMagnitude, right + translation.width))
        }
        if edge.movesTop {
            top = min(max(bounds?.minY ?? 0, top + translation.height), bottom - minimum.height)
        }
        if edge.movesBottom {
            bottom = max(
                top + minimum.height, min(bounds?.maxY ?? .greatestFiniteMagnitude, bottom + translation.height))
        }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}
