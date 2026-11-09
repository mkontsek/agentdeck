import Foundation

enum GlassBallStatus: Equatable {
    case working, attention, finished, idle

    var label: String {
        switch self {
        case .working: return "Working"
        case .attention: return "Needs attention"
        case .finished: return "Finished"
        case .idle: return "Idle"
        }
    }

    var symbol: String {
        switch self {
        case .working: return "bolt.fill"
        case .attention: return "exclamationmark"
        case .finished: return "checkmark"
        case .idle: return "pause.fill"
        }
    }

    static let compactSize = CGSize(width: 120, height: 100)
}
