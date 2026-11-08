import Foundation

enum CanvasLayout {
    static let minimumWidth = 320.0
    static let minimumHeight = 200.0
    static let spacing = 16.0

    /// Balanced rows fit every pane inside the viewport, including dense startup workspaces.
    static func frames(count: Int, viewport: CGSize) -> [CGRect] {
        guard count > 0, viewport.width.isFinite, viewport.height.isFinite,
            viewport.width > 0, viewport.height > 0
        else { return [] }
        let width = viewport.width
        let gap = min(spacing, min(width, viewport.height) / (Double(count) + 1) / 2)
        let rows = (1...count).min { rowScore($0) < rowScore($1) } ?? 1
        let height = (viewport.height - gap * Double(rows + 1)) / Double(rows)
        var result: [CGRect] = []
        for row in 0..<rows {
            let columns = count / rows + (row < count % rows ? 1 : 0)
            let paneWidth = (width - gap * Double(columns + 1)) / Double(columns)
            for column in 0..<columns {
                result.append(
                    CGRect(
                        x: gap + Double(column) * (paneWidth + gap),
                        y: gap + Double(row) * (height + gap),
                        width: paneWidth, height: height))
            }
        }
        return result

        func rowScore(_ rows: Int) -> Double {
            let height = (viewport.height - gap * Double(rows + 1)) / Double(rows)
            return (0..<rows).reduce(0) { score, row in
                let columns = count / rows + (row < count % rows ? 1 : 0)
                let paneWidth = (width - gap * Double(columns + 1)) / Double(columns)
                return score + Double(columns) * abs(log(paneWidth / height / 1.6))
            }
        }
    }
}
