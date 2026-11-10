import Combine
import Foundation

/// Scroll updates invalidate only the sidebar map, never AppStore or the terminal canvas.
@MainActor
final class CanvasOverviewState: ObservableObject {
    @Published private(set) var snapshot: CanvasOverviewSnapshot?
    private var sourceID: UUID?
    private var snapshotSourceID: UUID?
    private var navigator: ((CGPoint) -> Void)?
    var navigationID: UUID? { navigator != nil && snapshot != nil && snapshotSourceID == sourceID ? sourceID : nil }

    func attach(navigate: ((CGPoint) -> Void)? = nil) -> UUID {
        let id = UUID()
        sourceID = id
        snapshotSourceID = nil
        navigator = navigate
        return id
    }

    func moveViewport(to origin: CGPoint, from id: UUID) {
        guard navigationID == id, origin.x.isFinite, origin.y.isFinite else { return }
        navigator?(origin)
    }

    func update(_ snapshot: CanvasOverviewSnapshot?, from id: UUID) {
        guard sourceID == id else { return }
        snapshotSourceID = id
        guard self.snapshot != snapshot else { return }
        self.snapshot = snapshot
    }

    func detach(_ id: UUID) {
        guard sourceID == id else { return }
        sourceID = nil
        snapshotSourceID = nil
        navigator = nil
        if snapshot != nil { snapshot = nil }
    }
}
