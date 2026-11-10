import SwiftUI

/// Decorative paths never intercept input; the same relationships are actionable text in every pane header.
struct PaneConnectionsView: View {
    let connections: [PaneConnection]
    let frames: [UUID: CGRect]
    var docks: [UUID: GlassBallDock] = [:]
    var color: Color = CanvasArrowColor.color(hex: AppSettings().arrowColorHex)
    @StateObject private var cache = PaneRouteCache()

    var body: some View {
        Canvas { context, size in
            let routes = cache.paths(
                connections: connections, frames: frames, docks: docks,
                bounds: CGRect(
                    origin: CGPoint(x: 2, y: 2),
                    size: CGSize(width: max(0, size.width - 4), height: max(0, size.height - 4))))
            for connection in connections {
                guard let points = routes[connection.target.paneID], points.count >= 2,
                    let end = points.last
                else { continue }
                let path = Self.roundedPath(points)
                let last = points[points.count - 2]
                let angle = atan2(end.y - last.y, end.x - last.x)
                let length = min(9, hypot(end.x - last.x, end.y - last.y))
                var arrow = Path()
                arrow.move(to: end)
                for offset in [-0.5, 0.5] {
                    arrow.addLine(
                        to: CGPoint(
                            x: end.x - length * cos(angle + offset), y: end.y - length * sin(angle + offset)))
                }
                arrow.closeSubpath()
                context.withCGContext { drawing in
                    drawing.setAllowsAntialiasing(true)
                    drawing.setShouldAntialias(true)
                    drawing.setLineWidth(2)
                    drawing.setLineJoin(.round)
                    drawing.setLineCap(.round)
                    drawing.setLineDash(phase: 0, lengths: connection.kind == .browser ? [5, 4] : [])
                    drawing.setStrokeColor(NSColor(color).withAlphaComponent(0.85).cgColor)
                    drawing.addPath(path.cgPath)
                    drawing.strokePath()
                    drawing.setFillColor(NSColor(color).cgColor)
                    drawing.addPath(arrow.cgPath)
                    drawing.fillPath()
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static func roundedPath(_ points: [CGPoint], radius: CGFloat = 4) -> Path {
        var path = Path()
        guard let start = points.first, let end = points.last else { return path }
        path.move(to: start)
        for index in 1..<max(1, points.count - 1) {
            let before = points[index - 1]
            let corner = points[index]
            let after = points[index + 1]
            let incoming = hypot(corner.x - before.x, corner.y - before.y)
            let outgoing = hypot(after.x - corner.x, after.y - corner.y)
            guard incoming > 0, outgoing > 0 else { continue }
            let r = min(radius, incoming / 2, outgoing / 2)
            let entry = CGPoint(
                x: corner.x + (before.x - corner.x) * r / incoming,
                y: corner.y + (before.y - corner.y) * r / incoming)
            let exit = CGPoint(
                x: corner.x + (after.x - corner.x) * r / outgoing,
                y: corner.y + (after.y - corner.y) * r / outgoing)
            path.addLine(to: entry)
            path.addQuadCurve(to: exit, control: corner)
        }
        path.addLine(to: end)
        return path
    }
}
