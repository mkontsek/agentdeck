import SwiftUI

private struct GlassBallCollapsedKey: EnvironmentKey {
    static let defaultValue = false
}

private struct GlassBallTransitioningKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isGlassBallTransitioning: Bool {
        get { self[GlassBallTransitioningKey.self] }
        set { self[GlassBallTransitioningKey.self] = newValue }
    }
    var isGlassBallCollapsed: Bool {
        get { self[GlassBallCollapsedKey.self] }
        set { self[GlassBallCollapsedKey.self] = newValue }
    }
}
