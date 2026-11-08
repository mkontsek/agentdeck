import Foundation

struct PaneConnection: Identifiable, Equatable {
    enum Kind: String { case subagent, browser }
    let source: ManagedSession
    let target: ManagedSession
    let kind: Kind
    var id: UUID { target.paneID }
    var label: String {
        switch kind {
        case .subagent: return "\(source.name) delegates to \(target.name)"
        case .browser: return "Browser owned by \(source.name)"
        }
    }
}

struct PaneConnectionRoute {
    let start: CGPoint
    let end: CGPoint
    let bend1: CGPoint
    let bend2: CGPoint
    var points: [CGPoint] { PaneRouteSearch.simplify([start, bend1, bend2, end]) }

    init(source: CGRect, target: CGRect) {
        if target.minX >= source.maxX || source.minX >= target.maxX {
            let forward = target.midX >= source.midX
            start = CGPoint(x: forward ? source.maxX : source.minX, y: source.midY)
            end = CGPoint(x: forward ? target.minX : target.maxX, y: target.midY)
            let middle = (start.x + end.x) / 2
            bend1 = CGPoint(x: middle, y: start.y)
            bend2 = CGPoint(x: middle, y: end.y)
        } else {
            let down = target.midY >= source.midY
            start = CGPoint(x: source.midX, y: down ? source.maxY : source.minY)
            end = CGPoint(x: target.midX, y: down ? target.minY : target.maxY)
            let middle = (start.y + end.y) / 2
            bend1 = CGPoint(x: start.x, y: middle)
            bend2 = CGPoint(x: end.x, y: middle)
        }
    }
}
