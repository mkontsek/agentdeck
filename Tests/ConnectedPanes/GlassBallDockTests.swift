import AppKit
import SwiftUI
import XCTest

@MainActor
final class GlassBallDockTests: XCTestCase {
    func testAllDockSidesTouchSphereAndReserveEveryTransitionFrame() throws {
        let target = CGRect(x: 400, y: 400, width: 400, height: 300)
        let parents: [(GlassBallDock, CGRect)] = [
            (.left, CGRect(x: 20, y: 410, width: 180, height: 200)),
            (.right, CGRect(x: 950, y: 410, width: 180, height: 200)),
            (.top, CGRect(x: 420, y: 40, width: 200, height: 180)),
            (.bottom, CGRect(x: 420, y: 850, width: 200, height: 180)),
        ]
        let bounds = CGRect(x: 0, y: 0, width: 1300, height: 1200)
        for (side, parent) in parents {
            let dock = GlassBallDock(frame: target, parent: parent)
            XCTAssertEqual(dock, side)
            let point = dock.point(in: target)
            let sphere = dock.sphereFrame(in: target)
            XCTAssertEqual(hypot(point.x - sphere.midX, point.y - sphere.midY), 32, accuracy: 0.0001)
            let points = try XCTUnwrap(
                PaneRouteSearch.points(
                    source: parent, target: target,
                    obstacles: [parent, target], bounds: bounds, targetDock: dock))
            XCTAssertEqual(points.last, point)
            let reverse = try XCTUnwrap(
                PaneRouteSearch.points(
                    source: target, target: parent,
                    obstacles: [parent, target], bounds: bounds, sourceDock: dock))
            XCTAssertEqual(reverse.first, point)
            for progress in stride(from: CGFloat(0), through: 1, by: 0.05) {
                let size = CGSize(
                    width: 64 + (target.width - 64) * progress,
                    height: 64 + (target.height - 64) * progress)
                let visual = CGRect(
                    x: point.x - size.width * dock.anchor.x,
                    y: point.y - size.height * dock.anchor.y, width: size.width, height: size.height)
                XCTAssertEqual(dock.point(in: visual), point)
                for (a, b) in zip(points, points.dropFirst()) {
                    XCTAssertFalse(PaneRouteSearch.crosses(a, b, interior: visual))
                }
            }
            for scale: CGFloat in [0.65, 1, 1.75] {
                let projectedPoint = CGPoint(x: (point.x - 155) * scale, y: (point.y - 212) * scale)
                let projectedCenter = CGPoint(x: (sphere.midX - 155) * scale, y: (sphere.midY - 212) * scale)
                XCTAssertEqual(
                    hypot(projectedPoint.x - projectedCenter.x, projectedPoint.y - projectedCenter.y),
                    32 * scale, accuracy: 0.0001)
            }
        }
    }

    func testStoreGeometryAndCachedRoutesIgnoreFocusStatusButFollowRealLayout() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        store.settings.glassBallSubagents = true
        var parent = ManagedSession(name: "Parent", kind: .cli)
        parent.canvasPosition = PanePoint(x: 20, y: 20)
        parent.paneSize = PaneSize(width: 200, height: 300)
        parent = store.addSession(parent, start: false)
        var child = ManagedSession(name: "Worker", kind: .cli)
        child.parentSessionID = parent.id
        child.canvasPosition = PanePoint(x: 440, y: 40)
        child.paneSize = PaneSize(width: 400, height: 300)
        child = store.addSession(child, start: false, focus: false)
        let size = CGSize(width: 1000, height: 700)
        let bounds = CGRect(origin: .zero, size: size)
        for mode in [LayoutMode.canvas, .grid] {
            store.settings.layoutMode = mode
            let frames = store.paneFrames(in: size)
            let docks = store.glassBallDocks(in: frames)
            let cache = PaneRouteCache()
            let initial = cache.paths(connections: store.paneConnections, frames: frames, docks: docks, bounds: bounds)
            XCTAssertNotNil(initial[child.paneID])
            for status in [SessionStatus.working, .waitingForUser, .idle] {
                for focus in [child.id, parent.id] {
                    store.runtime[child.id]?.status = status
                    store.focusSession(focus)
                    let current = store.paneFrames(in: size)
                    XCTAssertEqual(
                        cache.paths(
                            connections: store.paneConnections, frames: current,
                            docks: store.glassBallDocks(in: current), bounds: bounds), initial)
                }
            }
            XCTAssertEqual(cache.computations, 1)
        }
        store.settings.layoutMode = .canvas
        let before = store.paneFrames(in: size)
        store.setCanvasPosition(for: child.id, PanePoint(x: 480, y: 80))
        store.setPaneSize(for: child.id, PaneSize(width: 420, height: 360))
        let after = store.paneFrames(in: size)
        XCTAssertNotEqual(before, after)
        let cache = PaneRouteCache()
        let old = cache.paths(
            connections: store.paneConnections, frames: before, docks: store.glassBallDocks(in: before), bounds: bounds)
        let new = cache.paths(
            connections: store.paneConnections, frames: after, docks: store.glassBallDocks(in: after), bounds: bounds)
        XCTAssertNotEqual(old, new)
        XCTAssertEqual(cache.computations, 2)
    }

    func testDockRoutingKeepsGuttersAndOmitsCoveredTangent() throws {
        let parent = CGRect(x: 20, y: 200, width: 180, height: 200)
        let child = CGRect(x: 650, y: 180, width: 400, height: 400)
        let blocker = CGRect(x: 300, y: 100, width: 200, height: 400)
        let bounds = CGRect(x: 2, y: 2, width: 1196, height: 796)
        let points = try XCTUnwrap(
            PaneRouteSearch.points(
                source: parent, target: child,
                obstacles: [parent, child, blocker], bounds: bounds, targetDock: .left))
        XCTAssertEqual(points.last, CGPoint(x: 650, y: 380))
        for (a, b) in zip(points, points.dropFirst()) {
            XCTAssertFalse(PaneRouteSearch.crosses(a, b, interior: blocker.insetBy(dx: -10, dy: -10)))
        }
        XCTAssertNil(
            PaneRouteSearch.points(
                source: parent, target: child,
                obstacles: [parent, child, CGRect(x: 620, y: 350, width: 80, height: 80)], bounds: bounds,
                targetDock: .left))
    }
}
