import Combine
import Foundation

@MainActor
final class PaneRouteCache: ObservableObject {
    private struct Edge: Equatable {
        let source: UUID
        let target: UUID
    }
    private var edges: [Edge] = []
    private var frames: [UUID: CGRect] = [:]
    private var docks: [UUID: GlassBallDock] = [:]
    private var bounds = CGRect.zero
    private var routes: [UUID: [CGPoint]] = [:]
    private(set) var computations = 0

    func paths(
        connections: [PaneConnection], frames: [UUID: CGRect], docks: [UUID: GlassBallDock] = [:], bounds: CGRect
    ) -> [UUID: [CGPoint]] {
        let edges = connections.map { Edge(source: $0.source.paneID, target: $0.target.paneID) }
        guard edges != self.edges || frames != self.frames || docks != self.docks || bounds != self.bounds else {
            return routes
        }
        self.edges = edges
        self.frames = frames
        self.docks = docks
        self.bounds = bounds
        computations += 1
        routes = [:]
        let obstacles = frames.sorted { $0.key.uuidString < $1.key.uuidString }.map(\.value).filter(
            PaneRouteSearch.valid)
        for edge in edges {
            guard let source = frames[edge.source], let target = frames[edge.target],
                PaneRouteSearch.valid(source), PaneRouteSearch.valid(target), PaneRouteSearch.valid(bounds)
            else { continue }
            routes[edge.target] = PaneRouteSearch.points(
                source: source, target: target, obstacles: obstacles, bounds: bounds,
                sourceDock: docks[edge.source], targetDock: docks[edge.target])
        }
        return routes
    }
}
