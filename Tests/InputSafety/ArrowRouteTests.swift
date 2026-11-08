import AppKit
import SwiftUI
import XCTest

@MainActor
final class ArrowRouteTests: XCTestCase {
    func testCachedRoutesLeaveSpaceBesideWindowsIncludingDirectShortcuts() throws {
        let source = ManagedSession(name: "Source", kind: .cli)
        let target = ManagedSession(name: "Target", kind: .cli)
        let connection = PaneConnection(source: source, target: target, kind: .subagent)
        let bounds = CGRect(x: 0, y: 0, width: 900, height: 600)
        let layouts: [(CGRect, CGRect, CGRect)] = [
            (
                CGRect(x: 20, y: 60, width: 180, height: 180),
                CGRect(x: 650, y: 280, width: 180, height: 180),
                CGRect(x: 280, y: 80, width: 250, height: 350)
            ),
            // The old fast path misses this obstacle by only five points.
            (
                CGRect(x: 20, y: 100, width: 100, height: 100),
                CGRect(x: 600, y: 300, width: 100, height: 100),
                CGRect(x: 365, y: 195, width: 150, height: 80)
            ),
            (
                CGRect(x: 20, y: 20, width: 100, height: 100),
                CGRect(x: 136, y: 220, width: 100, height: 100),
                CGRect(x: 800, y: 20, width: 10, height: 10)
            ),
        ]
        for (start, end, obstacle) in layouts {
            let frames = [source.paneID: start, target.paneID: end, UUID(): obstacle]
            let points = try XCTUnwrap(
                PaneRouteCache().paths(connections: [connection], frames: frames, bounds: bounds)[target.paneID])
            for (index, pair) in zip(points, points.dropFirst()).enumerated() {
                let (a, b) = pair
                XCTAssertFalse(
                    PaneRouteSearch.crosses(a, b, interior: obstacle.insetBy(dx: -10, dy: -10)),
                    "The route needs visible breathing room, not just a nonintersecting centerline")
                if index > 0 {
                    XCTAssertFalse(PaneRouteSearch.crosses(a, b, interior: start.insetBy(dx: -10, dy: -10)))
                }
                if index < points.count - 2 {
                    XCTAssertFalse(PaneRouteSearch.crosses(a, b, interior: end.insetBy(dx: -10, dy: -10)))
                }
            }
            let first = try XCTUnwrap(points.first)
            let last = try XCTUnwrap(points.last)
            XCTAssertTrue(
                first.x == start.minX || first.x == start.maxX || first.y == start.minY || first.y == start.maxY)
            XCTAssertTrue(last.x == end.minX || last.x == end.maxX || last.y == end.minY || last.y == end.maxY)
        }
    }

    func testNarrowCanvasFallsBackToVisibleRouteWithoutCrossingWindows() throws {
        let source = CGRect(x: 10, y: 0, width: 50, height: 140)
        let target = CGRect(x: 240, y: 0, width: 50, height: 140)
        let blocker = CGRect(x: 120, y: 0, width: 70, height: 134)
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 140)
        let frames = [source, target, blocker]
        let points = try XCTUnwrap(
            PaneRouteSearch.points(source: source, target: target, obstacles: frames, bounds: bounds))
        XCTAssertTrue(points.contains { $0.y >= 137 }, "Keep the arrow visible in the only six-point corridor")
        for (a, b) in zip(points, points.dropFirst()) {
            for frame in frames { XCTAssertFalse(PaneRouteSearch.crosses(a, b, interior: frame)) }
        }
        XCTAssertTrue(points.allSatisfy { $0.x >= 0 && $0.x <= 300 && $0.y >= 0 && $0.y <= 140 })
    }

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
