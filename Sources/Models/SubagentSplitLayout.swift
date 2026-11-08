import Foundation

enum SubagentSplitLayout: String, Codable, CaseIterable, Identifiable {
    case automatic, horizontal, vertical
    var id: String { rawValue }
    var label: String {
        switch self {
        case .automatic: return "Automatic"
        case .horizontal: return "Side by side"
        case .vertical: return "Stacked"
        }
    }
    func isHorizontal(in size: CGSize) -> Bool {
        switch self {
        case .automatic: return size.width >= 700 && size.width > size.height * 1.25
        case .horizontal: return true
        case .vertical: return false
        }
    }
}
