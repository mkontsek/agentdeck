import AppKit
import SwiftUI

/// SwiftUI scroll IDs use layout bounds before canvas offsets. Reveal the actual native canvas rectangle instead.
struct CanvasNavigationView: NSViewRepresentable {
    let revision: Int
    let target: CGRect?

    final class Coordinator { var revision = 0 }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> CanvasNavigationTarget { CanvasNavigationTarget() }

    func updateNSView(_ view: CanvasNavigationTarget, context: Context) {
        guard context.coordinator.revision != revision else { return }
        context.coordinator.revision = revision
        view.revision = revision
        guard let target else { return }
        DispatchQueue.main.async { [weak view] in
            guard let view, view.revision == revision else { return }
            view.scrollToVisible(target)
        }
    }
}

final class CanvasNavigationTarget: NSView {
    var revision = 0
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
