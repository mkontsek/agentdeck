import SwiftUI

/// A shared tangent for the sphere, transformed native layer and every relationship on a worker.
/// It depends on full layout geometry, never focus, pulse or animation progress.
enum GlassBallDock: CaseIterable {
    case left, right, top, bottom

    static let diameter: CGFloat = 64

    init(frame: CGRect, parent: CGRect) {
        if parent.maxX <= frame.minX {
            self = .left
        } else if parent.minX >= frame.maxX {
            self = .right
        } else {
            self = parent.midY <= frame.midY ? .top : .bottom
        }
    }

    var anchor: UnitPoint {
        switch self {
        case .left: return .leading
        case .right: return .trailing
        case .top: return .top
        case .bottom: return .bottom
        }
    }

    func point(in frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX + frame.width * anchor.x, y: frame.minY + frame.height * anchor.y)
    }

    func outside(_ frame: CGRect, distance: CGFloat) -> CGPoint {
        let p = point(in: frame)
        return CGPoint(x: p.x + (anchor.x - 0.5) * 2 * distance, y: p.y + (anchor.y - 0.5) * 2 * distance)
    }

    var sphereCenter: CGPoint {
        let size = GlassBallStatus.compactSize
        switch self {
        case .left: return CGPoint(x: Self.diameter / 2, y: size.height / 2)
        case .right: return CGPoint(x: size.width - Self.diameter / 2, y: size.height / 2)
        case .top: return CGPoint(x: size.width / 2, y: Self.diameter / 2)
        case .bottom: return CGPoint(x: size.width / 2, y: size.height - Self.diameter / 2)
        }
    }

    var labelCenter: CGPoint {
        CGPoint(x: GlassBallStatus.compactSize.width / 2, y: self == .bottom ? 12 : 91)
    }

    func compactFrame(in frame: CGRect) -> CGRect {
        let local = point(in: CGRect(origin: .zero, size: GlassBallStatus.compactSize))
        let p = point(in: frame)
        return CGRect(
            x: p.x - local.x, y: p.y - local.y,
            width: GlassBallStatus.compactSize.width, height: GlassBallStatus.compactSize.height)
    }

    func sphereFrame(in frame: CGRect) -> CGRect {
        let compact = compactFrame(in: frame)
        return CGRect(
            x: compact.minX + sphereCenter.x - Self.diameter / 2,
            y: compact.minY + sphereCenter.y - Self.diameter / 2,
            width: Self.diameter, height: Self.diameter)
    }
}
