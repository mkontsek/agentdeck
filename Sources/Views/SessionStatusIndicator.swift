import SwiftUI

extension GlassBallStatus {
    var color: Color {
        switch self {
        case .working: return .blue
        case .attention: return .yellow
        case .finished: return .green
        case .idle: return .gray
        }
    }
}

/// The same presentation state and palette as the sphere, including task approval/attention.
struct SessionStatusIndicator: View {
    let status: GlassBallStatus
    var diameter: CGFloat = 8

    var body: some View {
        Circle().fill(status.color).frame(width: diameter, height: diameter)
            .accessibilityLabel(status.label)
            .help(status.label)
    }
}
