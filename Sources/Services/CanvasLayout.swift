import Foundation

enum CanvasLayout {
    static let minimumWidth = 320.0
    static let minimumHeight = 200.0
    static let spacing = 16.0

    /// Balanced rows fill the viewport; retain readable minimum sizes if scrolling is unavoidable.
    static func frames(count: Int, viewport: CGSize) -> [CGRect] {
        guard count > 0, viewport.width.isFinite, viewport.height.isFinite,
            viewport.width > 0, viewport.height > 0
        else { return [] }
        let width = max(viewport.width, minimumWidth + 2 * spacing)
        let maxColumns = Int(max(1, min(Double(count), (width - spacing) / (minimumWidth + spacing))))
        let minimumRows = Int(ceil(Double(count) / Double(maxColumns)))
        let maximumRows = max(
            minimumRows, Int(max(1, min(Double(count), (viewport.height - spacing) / (minimumHeight + spacing)))))
        let rows = (minimumRows...maximumRows).min { rowScore($0) < rowScore($1) } ?? minimumRows
        let height = max(minimumHeight, (viewport.height - spacing * Double(rows + 1)) / Double(rows))
        var result: [CGRect] = []
        for row in 0..<rows {
            let columns = count / rows + (row < count % rows ? 1 : 0)
            let paneWidth = (width - spacing * Double(columns + 1)) / Double(columns)
            for column in 0..<columns {
                result.append(
                    CGRect(
                        x: spacing + Double(column) * (paneWidth + spacing),
                        y: spacing + Double(row) * (height + spacing),
                        width: paneWidth, height: height))
            }
        }
        return result

        func rowScore(_ rows: Int) -> Double {
            let height = max(minimumHeight, (viewport.height - spacing * Double(rows + 1)) / Double(rows))
            return (0..<rows).reduce(0) { score, row in
                let columns = count / rows + (row < count % rows ? 1 : 0)
                let paneWidth = (width - spacing * Double(columns + 1)) / Double(columns)
                return score + Double(columns) * abs(log(paneWidth / height / 1.6))
            }
        }
    }
}
