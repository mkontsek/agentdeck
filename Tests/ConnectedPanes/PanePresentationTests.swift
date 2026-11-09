import AppKit
import SwiftUI
import XCTest

@MainActor
final class PanePresentationTests: XCTestCase {
    func testInitiallyEmptyWorkspaceFitsTwentyWindowsOnceAndPreservesThatLayoutOnRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("state.json")
        let store = AppStore(stateURL: url)
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        store.prepareStartupLayout()
        store.updateCanvasViewport(.zero)
        XCTAssertTrue(store.startupPaneFitPending)
        for index in 0..<20 {
            var session = ManagedSession(name: "Pane \(index)", kind: .cli)
            session.canvasPosition = PanePoint(x: Double(index) * 1000, y: 1500)
            session.fontSizeOverride = index == 0 ? 17 : nil
            store.addSession(session, start: false, focus: false)
        }
        let ids = store.sessions.map(\.id)
        store.focusedSessionID = ids[4]
        store.maximizedSessionID = ids[4]
        store.updateCanvasViewport(CGSize(width: 1200, height: 760))
        XCTAssertFalse(store.startupPaneFitPending)
        XCTAssertNil(store.maximizedSessionID)
        XCTAssertEqual(store.focusedSessionID, ids[4])
        XCTAssertEqual(store.sessions.map(\.id), ids)
        let frames = store.paneFrames(in: store.canvasViewport)
        XCTAssertEqual(frames.count, 20)
        for frame in frames.values { XCTAssertTrue(CGRect(origin: .zero, size: store.canvasViewport).contains(frame)) }
        XCTAssertEqual(store.textSize(for: store.sessions[0]), 17)
        XCTAssertLessThan(store.textSize(for: store.sessions[1]), store.settings.globalFontSize)
        store.setCanvasPosition(for: ids[4], PanePoint(x: 1600, y: 900))
        store.updateCanvasViewport(CGSize(width: 1100, height: 700))
        XCTAssertEqual(
            store.session(ids[4])?.canvasPosition, PanePoint(x: 1600, y: 900),
            "Later viewport changes retain manual layout")
        store.saveNow()
        let savedPositions = store.sessions.map(\.canvasPosition)
        let savedSizes = store.sessions.map(\.paneSize)
        let restored = AppStore(stateURL: url)
        defer { restored.shutdown() }
        restored.prepareStartupLayout()
        restored.updateCanvasViewport(CGSize(width: 1000, height: 700))
        XCTAssertEqual(restored.sessions.map(\.id), ids)
        XCTAssertEqual(restored.sessions[0].fontSizeOverride, 17)
        XCTAssertEqual(restored.sessions.map(\.canvasPosition), savedPositions)
        XCTAssertEqual(restored.sessions.map(\.paneSize), savedSizes)
    }

    func testResizeScalesTerminalAndBrowserWithIndependentPersistedOverrides() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("state.json")
        let store = AppStore(stateURL: url)
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        var agent = ManagedSession(name: "Agent", kind: .cli)
        agent.paneSize = PaneSizePreset.normal.size
        agent = store.addSession(agent, start: false)
        let terminal = store.terminals.makeView(for: agent.id, font: store.font(for: agent))
        var browser = ManagedSession(name: "Browser", kind: .browser)
        browser.agentOwnerID = agent.id
        browser = store.addSession(browser, start: false, focus: false)
        XCTAssertEqual(browser.paneID, agent.paneID)
        XCTAssertEqual(terminal.font.pointSize, 11)
        store.setPaneSize(for: agent.id, PaneSize(width: 320, height: 220))
        XCTAssertEqual(terminal.font.pointSize, 5.5)
        XCTAssertEqual(store.textSize(for: try XCTUnwrap(store.session(browser.id))), 11)
        store.adjustFont(for: agent.id, by: 2)
        XCTAssertEqual(terminal.font.pointSize, 7.5)
        store.setPaneSize(for: browser.id, PaneSize(width: 1280, height: 880))
        XCTAssertEqual(terminal.font.pointSize, 7.5)
        XCTAssertEqual(store.textSize(for: try XCTUnwrap(store.session(browser.id))), 11)
        store.resetFont(for: agent.id)
        XCTAssertEqual(terminal.font.pointSize, 11)
        store.setAutomaticTextSize(for: browser.id, enabled: false)
        store.updateCanvasViewport(CGSize(width: 1600, height: 1000))
        store.maximizedSessionID = agent.id
        XCTAssertEqual(terminal.font.pointSize, 11)
        XCTAssertEqual(store.textSize(for: try XCTUnwrap(store.session(browser.id))), 11)
        store.saveNow()
        let restored = AppStore(stateURL: url)
        defer { restored.shutdown() }
        XCTAssertNil(restored.session(agent.id)?.fontSizeOverride)
        XCTAssertEqual(restored.session(browser.id)?.fontSizeOverride, 11)
        for value in [Double.greatestFiniteMagnitude, -.infinity, .nan, 0] {
            var invalid = browser
            invalid.fontSizeOverride = value
            XCTAssertTrue((5...40).contains(store.textSize(for: invalid)))
            XCTAssertTrue((0.05...4).contains(try XCTUnwrap(store.browserZoomOverride(for: invalid))))
            XCTAssertFalse(store.textSizeLabel(for: invalid).isEmpty)
        }
        XCTAssertEqual(
            PaneTextScale.points(base: .nan, size: PaneSize(width: .infinity, height: -1), override: .nan), 11)
    }

    func testConnectionsUseOnlyHorizontalOrVerticalSegments() {
        let source = CGRect(x: 100, y: 100, width: 300, height: 200)
        for target in [
            CGRect(x: 500, y: 250, width: 300, height: 200), CGRect(x: 110, y: 450, width: 300, height: 200),
            CGRect(x: -300, y: 0, width: 200, height: 200),
        ] {
            let route = PaneConnectionRoute(source: source, target: target)
            let points = [route.start, route.bend1, route.bend2, route.end]
            for (a, b) in zip(points, points.dropFirst()) { XCTAssertTrue(a.x == b.x || a.y == b.y) }
        }
    }
}
