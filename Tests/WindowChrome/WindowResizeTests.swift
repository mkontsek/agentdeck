import AppKit
import SwiftUI
import XCTest

final class WindowResizeTests: XCTestCase {
    func testEveryEdgeKeepsItsOppositeEdgeAnchored() {
        let start = CGRect(x: 100, y: 100, width: 500, height: 400)
        for edge in WindowResizeEdge.allCases {
            let result = WindowResizeGeometry.resize(
                start, edge: edge, translation: CGSize(width: 40, height: 30), minimum: CGSize(width: 320, height: 200))
            XCTAssertEqual(result.minX, edge.movesLeft ? 140 : 100, "\(edge)")
            XCTAssertEqual(result.maxX, edge.movesRight ? 640 : 600, "\(edge)")
            XCTAssertEqual(result.minY, edge.movesTop ? 130 : 100, "\(edge)")
            XCTAssertEqual(result.maxY, edge.movesBottom ? 530 : 500, "\(edge)")
        }
    }

    func testMinimumAndViewportLimitsDoNotMoveTheOppositeCorner() {
        let start = CGRect(x: 100, y: 100, width: 500, height: 400)
        let minimum = CGSize(width: 320, height: 220)
        let small = WindowResizeGeometry.resize(
            start, edge: .topLeft, translation: CGSize(width: 1000, height: 1000), minimum: minimum)
        XCTAssertEqual(small, CGRect(x: 280, y: 280, width: 320, height: 220))
        let origin = WindowResizeGeometry.resize(
            start, edge: .topLeft, translation: CGSize(width: -1000, height: -1000), minimum: minimum)
        XCTAssertEqual(origin, CGRect(x: 0, y: 0, width: 600, height: 500))
        let bounded = WindowResizeGeometry.resize(
            start, edge: .bottomRight, translation: CGSize(width: 1000, height: 1000), minimum: minimum,
            bounds: CGRect(x: 8, y: 8, width: 784, height: 584))
        XCTAssertEqual(bounded, CGRect(x: 100, y: 100, width: 692, height: 492))
    }

    @MainActor
    func testBorderHitTestingLeavesContentAndHeaderControlsAlone() {
        let parent = NSView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let view = MiniWindowResizeView(frame: CGRect(x: 100, y: 50, width: 420, height: 360))
        parent.addSubview(view)
        let samples: [(CGPoint, WindowResizeEdge)] = [
            (CGPoint(x: 400, y: 340), .bottomRight), (CGPoint(x: 418, y: 358), .bottomRight),
        ]
        for (point, edge) in samples {
            XCTAssertEqual(view.edge(at: point), edge)
            XCTAssertTrue(view.hitTest(view.convert(point, to: parent)) === view)
        }
        for point in [
            CGPoint(x: 210, y: 180), CGPoint(x: 380, y: 22), CGPoint(x: 430, y: 180),
            CGPoint(x: 2, y: 2), CGPoint(x: 418, y: 2), CGPoint(x: 2, y: 358),
            CGPoint(x: 200, y: 2), CGPoint(x: 200, y: 358), CGPoint(x: 2, y: 180), CGPoint(x: 418, y: 180),
        ] {
            XCTAssertNil(view.edge(at: point))
            XCTAssertNil(view.hitTest(view.convert(point, to: parent)))
        }
        view.isHidden = true
        XCTAssertNil(view.hitTest(view.convert(CGPoint(x: 2, y: 180), to: parent)))
    }

    @MainActor
    func testGridResizeKeepsAllTabFramesAndPersistsCanvasLayout() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("state.json")
        let store = AppStore(stateURL: url)
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        let first = store.addSession(ManagedSession(name: "One", kind: .cli), start: false)
        var tab = ManagedSession(name: "Tab", kind: .cli)
        tab.paneID = first.paneID
        store.addSession(tab, start: false)
        let second = store.addSession(ManagedSession(name: "Two", kind: .cli), start: false)
        let frames = [
            first.paneID: CGRect(x: 8, y: 8, width: 500, height: 350),
            second.paneID: CGRect(x: 516, y: 8, width: 500, height: 350),
        ]
        store.settings.layoutMode = .grid
        store.detachGridForResize(frames: frames)
        XCTAssertEqual(store.settings.layoutMode, .canvas)
        for session in store.sessions {
            let frame = try XCTUnwrap(frames[session.paneID])
            XCTAssertEqual(session.canvasPosition, PanePoint(x: frame.minX, y: frame.minY))
            XCTAssertEqual(session.paneSize, PaneSize(width: frame.width, height: frame.height))
        }
        store.saveNow()
        let restored = AppStore(stateURL: url)
        defer { restored.shutdown() }
        XCTAssertEqual(restored.settings.layoutMode, .canvas)
        XCTAssertEqual(restored.sessions.map(\.paneSize), store.sessions.map(\.paneSize))
        XCTAssertEqual(restored.sessions.map(\.canvasPosition), store.sessions.map(\.canvasPosition))
    }
}
