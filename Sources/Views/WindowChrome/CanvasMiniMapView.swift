import SwiftUI

struct CanvasMiniMapView: View {
    @ObservedObject var overview: CanvasOverviewState

    var body: some View {
        let snapshot = overview.snapshot
        VStack(spacing: 6) {
            HStack {
                Text("Canvas map").fontWeight(.medium)
                Spacer(minLength: 4)
                Label("Viewport", systemImage: "rectangle.dashed").foregroundStyle(.secondary)
            }
            .font(.caption)
            Canvas { context, size in
                guard let snapshot,
                    let projection = CanvasOverviewProjection(bounds: snapshot.bounds, size: size)
                else { return }
                let canvas = Path(roundedRect: projection.project(snapshot.bounds), cornerRadius: 2)
                context.stroke(canvas, with: .color(.secondary.opacity(0.3)), lineWidth: 1)
                for (id, frame) in snapshot.panes {
                    let rect = projection.project(frame)
                    let path = Path(roundedRect: rect, cornerRadius: min(2, rect.width / 4, rect.height / 4))
                    context.fill(path, with: .color(.blue.opacity(id == snapshot.focusedPaneID ? 0.35 : 0.15)))
                    context.stroke(path, with: .color(.blue), lineWidth: 1)
                }
                if let id = snapshot.focusedPaneID, let frame = snapshot.panes[id] {
                    context.stroke(Path(projection.project(frame)), with: .color(.blue), lineWidth: 2)
                }
                let viewport = Path(projection.project(snapshot.viewport))
                context.fill(viewport, with: .color(.primary.opacity(0.04)))
                context.stroke(viewport, with: .color(.primary), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
            .frame(height: 104)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
            .overlay { CanvasMiniMapInteraction(overview: overview, snapshot: snapshot) }
            .overlay {
                if snapshot?.panes.isEmpty ?? true {
                    Text(snapshot == nil ? "Canvas unavailable" : "No windows")
                        .font(.caption).foregroundStyle(.secondary).allowsHitTesting(false)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Canvas map")
        .accessibilityValue(accessibilitySummary)
        .accessibilityHint("Drag the viewport or click the map to navigate. Scroll actions pan the canvas.")
        .accessibilityScrollAction { edge in
            guard let snapshot = overview.snapshot, let id = overview.navigationID else { return }
            var origin = snapshot.viewport.origin
            switch edge {
            case .leading: origin.x -= snapshot.viewport.width * 0.8
            case .trailing: origin.x += snapshot.viewport.width * 0.8
            case .top: origin.y -= snapshot.viewport.height * 0.8
            case .bottom: origin.y += snapshot.viewport.height * 0.8
            }
            overview.moveViewport(to: origin, from: id)
        }
        .accessibilityIdentifier("canvas-mini-map")
    }

    private var accessibilitySummary: String {
        guard let snapshot = overview.snapshot else { return "Canvas unavailable" }
        func number(_ value: CGFloat) -> String { Double(value).formatted(.number.precision(.fractionLength(0))) }
        return "\(snapshot.panes.count) windows. Viewport at \(number(snapshot.viewport.minX)), "
            + "\(number(snapshot.viewport.minY)); \(number(snapshot.viewport.width)) by "
            + "\(number(snapshot.viewport.height)) of \(number(snapshot.bounds.width)) by "
            + "\(number(snapshot.bounds.height)) canvas points."
    }
}
