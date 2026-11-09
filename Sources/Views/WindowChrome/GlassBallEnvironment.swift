import SwiftUI

private struct GlassBallCollapsedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isGlassBallCollapsed: Bool {
        get { self[GlassBallCollapsedKey.self] }
        set { self[GlassBallCollapsedKey.self] = newValue }
    }
}
