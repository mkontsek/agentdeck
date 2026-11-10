import SwiftUI

enum WorkspaceMotion {
    static let transitionDuration = 0.28

    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .smooth(duration: transitionDuration, extraBounce: 0)
    }

    static func panel(edge: Edge, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }
}
