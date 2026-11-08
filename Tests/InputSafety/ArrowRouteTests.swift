import AppKit
import SwiftUI
import XCTest

@MainActor
final class ArrowRouteTests: XCTestCase {
    func testInvalidAndOversizedRouteSearchIsBounded() {
        let source = CGRect(x: 10, y: 10, width: 50, height: 50)
        let target = CGRect(x: 300, y: 300, width: 50, height: 50)
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 500)
        XCTAssertNil(
            PaneRouteSearch.points(
                source: CGRect(x: CGFloat.nan, y: 0, width: 5, height: 5),
                target: target, obstacles: [], bounds: bounds))
        XCTAssertNil(
            PaneRouteSearch.points(
                source: source, target: target,
                obstacles: Array(repeating: source, count: 129), bounds: bounds))
        XCTAssertNil(PaneRouteSearch.points(source: source, target: target, obstacles: [], bounds: .zero))
    }

    func testRoutesAvoidInterveningAndOverlappingWindowsAndStayInsideCanvas() throws {
        let source = CGRect(x: 20, y: 60, width: 180, height: 180)
        let target = CGRect(x: 650, y: 280, width: 180, height: 180)
        let bounds = CGRect(x: 2, y: 2, width: 880, height: 560)
        for blockers in [
            [CGRect(x: 280, y: 80, width: 250, height: 350)],
            [CGRect(x: 130, y: 100, width: 160, height: 180), CGRect(x: 320, y: 0, width: 180, height: 300)],
            [CGRect(x: 210, y: 0, width: 100, height: 320), CGRect(x: 420, y: 200, width: 100, height: 350)],
        ] {
            let obstacles = [source, target] + blockers
            let points = try XCTUnwrap(
                PaneRouteSearch.points(source: source, target: target, obstacles: obstacles, bounds: bounds))
            XCTAssertGreaterThan(points.count, 2)
            for p in points { XCTAssertTrue(bounds.contains(p)) }
            for (a, b) in zip(points, points.dropFirst()) {
                XCTAssertTrue(a.x == b.x || a.y == b.y)
                for obstacle in obstacles { XCTAssertFalse(PaneRouteSearch.crosses(a, b, interior: obstacle)) }
            }
        }
    }

    func testCoveredEndpointIsNotDrawnThroughPrivateContentAndRoutesCache() throws {
        let source = ManagedSession(name: "Source", kind: .cli)
        let target = ManagedSession(name: "Target", kind: .cli)
        let blocker = UUID()
        let connections = [PaneConnection(source: source, target: target, kind: .subagent)]
        var frames = [
            source.paneID: CGRect(x: 10, y: 10, width: 80, height: 80),
            target.paneID: CGRect(x: 400, y: 10, width: 80, height: 80),
            blocker: CGRect(x: 390, y: 0, width: 100, height: 100),
        ]
        let bounds = CGRect(x: 0, y: 0, width: 600, height: 500)
        let cache = PaneRouteCache()
        XCTAssertNil(cache.paths(connections: connections, frames: frames, bounds: bounds)[target.paneID])
        frames[blocker] = CGRect(x: 200, y: 0, width: 100, height: 150)
        let routed = try XCTUnwrap(cache.paths(connections: connections, frames: frames, bounds: bounds)[target.paneID])
        for _ in 0..<100 {
            XCTAssertEqual(cache.paths(connections: connections, frames: frames, bounds: bounds)[target.paneID], routed)
        }
        XCTAssertEqual(cache.computations, 2, "Status/text repaint must reuse geometry")
        frames.removeValue(forKey: blocker)
        XCTAssertNotEqual(cache.paths(connections: connections, frames: frames, bounds: bounds)[target.paneID], routed)
    }

    func testSmallRadiusIsAnActualCurveAndColorPersistsIndependently() throws {
        let points = [CGPoint(x: 10, y: 10), CGPoint(x: 60, y: 10), CGPoint(x: 60, y: 50)]
        var curves = 0
        // Path exposes visitor traversal; it is not a Sequence.
        // swift-format-ignore: ReplaceForEachWithForLoop
        PaneConnectionsView.roundedPath(points).forEach { element in
            if case .quadCurve(let end, let control) = element {
                curves += 1
                XCTAssertEqual(control, points[1])
                XCTAssertEqual(end, CGPoint(x: 60, y: 14))
            }
        }
        XCTAssertEqual(curves, 1)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(old.arrowColorHex, "B96B35")
        var settings = old
        settings.arrowColorHex = "8B53C9"
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.arrowColorHex, settings.arrowColorHex)
        XCTAssertEqual(CanvasArrowColor.hex(color: CanvasArrowColor.color(hex: restored.arrowColorHex)), "8B53C9")
        XCTAssertEqual(CanvasArrowColor.hex(color: CanvasArrowColor.color(hex: "bad")), old.arrowColorHex)
    }
}
