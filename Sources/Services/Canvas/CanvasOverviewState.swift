import Combine
import Foundation

/// Scroll updates invalidate only the sidebar map, never AppStore or the terminal canvas.
@MainActor
final class CanvasOverviewState: ObservableObject {
    @Published private(set) var snapshot: CanvasOverviewSnapshot?
    private var sourceID: UUID?

    func attach() -> UUID {
        let id = UUID()
        sourceID = id
        return id
    }

    func update(_ snapshot: CanvasOverviewSnapshot?, from id: UUID) {
        guard sourceID == id, self.snapshot != snapshot else { return }
        self.snapshot = snapshot
    }

    func detach(_ id: UUID) {
        guard sourceID == id else { return }
        sourceID = nil
        if snapshot != nil { snapshot = nil }
    }
}
