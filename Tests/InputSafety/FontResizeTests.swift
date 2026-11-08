import AppKit
import XCTest

final class FontResizeTests: XCTestCase {
    func testAutomaticCeilingReversibleShrinkAndManualOverride() {
        let small = PaneSize(width: 320, height: 220)
        let expanded = PaneSize(width: 2000, height: 1600)
        let original = PaneTextScale.points(base: 16, size: small, override: nil)
        XCTAssertEqual(original, 8)
        XCTAssertEqual(PaneTextScale.points(base: 16, size: expanded, override: nil), 16)
        XCTAssertEqual(PaneTextScale.points(base: 16, size: small, override: nil), original)
        XCTAssertLessThan(
            PaneTextScale.points(base: 16, size: PaneSize(width: 260, height: 160), override: nil), original)
        for size in [small, expanded] {
            XCTAssertEqual(PaneTextScale.points(base: 16, size: size, override: 25), 25)
        }
        XCTAssertEqual(PaneTextScale.points(base: 13.2, size: expanded, override: nil), 13.2)
    }
}
