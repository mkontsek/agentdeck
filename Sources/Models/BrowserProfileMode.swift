import Foundation

enum BrowserProfileMode: String, Codable, CaseIterable, Identifiable {
    case shared, isolated

    var id: String { rawValue }
    var label: String {
        switch self {
        case .shared: return "Shared AgentDeck"
        case .isolated: return "Separate account"
        }
    }
}

extension ManagedSession {
    func browserDataStoreID(sharedProfileID: UUID) -> UUID {
        browserProfileMode == .shared ? sharedProfileID : browserProfileID
    }
}
