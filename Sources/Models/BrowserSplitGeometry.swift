import Foundation

struct BrowserSplitGeometry {
    static let defaultFraction = 0.5
    let size: CGSize
    let isHorizontal: Bool
    let availableExtent: CGFloat
    let dividerExtent: CGFloat
    let firstSize: CGSize
    let secondSize: CGSize
    let dividerFrame: CGRect

    var displayedFraction: Double {
        guard availableExtent > 0 else { return Self.defaultFraction }
        return Double((isHorizontal ? firstSize.width : firstSize.height) / availableExtent)
    }

    static func clampedFraction(_ value: Double) -> Double {
        value.isFinite ? min(0.9, max(0.1, value)) : defaultFraction
    }

    init(size: CGSize, isHorizontal: Bool, fraction: Double) {
        let width = size.width.isFinite ? max(0, size.width) : 0
        let height = size.height.isFinite ? max(0, size.height) : 0
        self.size = CGSize(width: width, height: height)
        self.isHorizontal = isHorizontal
        let extent = isHorizontal ? width : height
        dividerExtent = min(8, extent)
        availableExtent = extent - dividerExtent
        let minimum = min(120, availableExtent / 2)
        let first = min(availableExtent - minimum, max(minimum, availableExtent * Self.clampedFraction(fraction)))
        let second = availableExtent - first
        firstSize = isHorizontal ? CGSize(width: first, height: height) : CGSize(width: width, height: first)
        secondSize = isHorizontal ? CGSize(width: second, height: height) : CGSize(width: width, height: second)
        dividerFrame =
            isHorizontal
            ? CGRect(x: first, y: 0, width: dividerExtent, height: height)
            : CGRect(x: 0, y: first, width: width, height: dividerExtent)
    }
}
