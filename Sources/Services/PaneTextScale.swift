import Foundation

enum PaneTextScale {
    static let minimum = 5.0
    static let maximum = 40.0
    static let browserReference = 11.0

    /// Area-based linear scaling responds to either resize axis; half-points avoid needless PTY reflow.
    static func points(base: Double, size: PaneSize, override: Double?) -> Double {
        if let override, override.isFinite { return min(maximum, max(minimum, override)) }
        let normal = PaneSizePreset.normal.size
        let scale: Double
        if size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 {
            scale = sqrt(size.width / normal.width) * sqrt(size.height / normal.height)
        } else {
            scale = 1
        }
        // Use the configured size as the automatic ceiling. Geometry, rather than the last resized
        // font, is the reference: restoring the old dimensions restores the old small font exactly.
        let ceiling = min(maximum, max(minimum, base.isFinite ? base : browserReference))
        let value = ceiling * scale
        if value >= ceiling { return ceiling }
        return min(ceiling, (max(minimum, min(ceiling, value)) * 2).rounded() / 2)
    }
}
