import AppKit
import XCTest

@MainActor
final class PaneRestorationTests: XCTestCase {
    func testCanvasGeometryAndTabsSurviveRepeatedRestartsAtDifferentViewportSizes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        let source = AppStore(stateURL: url)
        source.settings.globalFontSize = 14
        source.updateCanvasViewport(CGSize(width: 1600, height: 1000))
        var parent = ManagedSession(name: "Parent", kind: .cli)
        parent.cliProfileID = "codex"
        parent.canvasPosition = PanePoint(x: 31.5, y: 43.25)
        parent.paneSize = PaneSize(width: 380.5, height: 280.25)
        source.addSession(parent, start: false)
        let tab = try XCTUnwrap(source.addCLITab(to: parent.id, start: false))
        let worker = try source.delegateTask(from: parent.id, title: "Worker", instructions: "Fixture", start: false)
        var browser = ManagedSession(name: "Worker browser", kind: .browser)
        browser.agentOwnerID = worker.id
        source.addSession(browser, start: false, focus: false)
        source.setCanvasPosition(for: worker.id, PanePoint(x: 1800.5, y: 900.25))
        source.setPaneSize(for: worker.id, PaneSize(width: 530.5, height: 360.25))
        source.adjustFont(for: worker.id, by: 2)
        source.selectTab(tab.id)
        let expected = source.sessions
        let fonts = expected.map { source.textSize(for: $0) }
        source.shutdown()

        for viewport in [CGSize(width: 640, height: 400), CGSize(width: 2400, height: 1500)] {
            let restored = AppStore(stateURL: url)
            restored.prepareStartupLayout()
            restored.updateCanvasViewport(.zero)
            restored.updateCanvasViewport(viewport)
            XCTAssertFalse(restored.startupPaneFitPending)
            XCTAssertEqual(restored.sessions.map(\.id), expected.map(\.id))
            XCTAssertEqual(restored.sessions.map(\.paneID), expected.map(\.paneID))
            XCTAssertEqual(restored.session(browser.id)?.paneID, worker.paneID)
            XCTAssertEqual(restored.sessions.map(\.canvasPosition), expected.map(\.canvasPosition))
            XCTAssertEqual(restored.sessions.map(\.paneSize), expected.map(\.paneSize))
            XCTAssertEqual(restored.sessions.map { restored.textSize(for: $0) }, fonts)
            XCTAssertEqual(restored.focusedSessionID, tab.id)
            XCTAssertEqual(restored.pane(containing: parent.id)?.activeSession.id, tab.id)
            restored.updateCanvasViewport(CGSize(width: viewport.width + 100, height: viewport.height + 100))
            XCTAssertEqual(restored.sessions.map(\.canvasPosition), expected.map(\.canvasPosition))
            XCTAssertEqual(restored.sessions.map(\.paneSize), expected.map(\.paneSize))
            restored.shutdown()
        }
    }

    func testGridSavesItsUnmaximizedGeometryWithoutChangingTheLiveLayout() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        let source = AppStore(stateURL: url)
        source.settings.layoutMode = .grid
        source.updateCanvasViewport(CGSize(width: 1200, height: 900))
        for index in 0..<3 {
            var session = ManagedSession(name: "Grid \(index)", kind: .cli)
            session.cliProfileID = "codex"
            source.addSession(session, start: false, focus: false)
        }
        let first = try XCTUnwrap(source.sessions.first)
        let tab = try XCTUnwrap(source.addCLITab(to: first.id, start: false))
        let expected = source.paneFrames(in: source.canvasViewport)
        let live = source.sessions
        source.maximizedSessionID = tab.id
        source.saveNow()
        XCTAssertEqual(source.settings.layoutMode, .grid)
        XCTAssertEqual(source.maximizedSessionID, tab.id)
        XCTAssertEqual(source.sessions.map(\.paneSize), live.map(\.paneSize))
        XCTAssertEqual(source.sessions.map(\.canvasPosition), live.map(\.canvasPosition))
        source.shutdown()

        let restored = AppStore(stateURL: url)
        defer { restored.shutdown() }
        restored.prepareStartupLayout()
        restored.updateCanvasViewport(CGSize(width: 700, height: 400))
        XCTAssertEqual(restored.settings.layoutMode, .canvas)
        XCTAssertEqual(restored.paneFrames(in: restored.canvasViewport), expected)
        for session in restored.sessions {
            let frame = try XCTUnwrap(expected[session.paneID])
            XCTAssertEqual(session.canvasPosition, PanePoint(x: frame.minX, y: frame.minY))
            XCTAssertEqual(session.paneSize, PaneSize(width: frame.width, height: frame.height))
        }
    }

    func testLegacyGridAndUnpositionedPaneDoNotRepackSavedCanvasGeometry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        let source = AppStore(stateURL: url)
        source.settings.layoutMode = .grid
        var placed = ManagedSession(name: "Saved", kind: .cli)
        placed.canvasPosition = PanePoint(x: 123, y: 456)
        placed.paneSize = PaneSize(width: 333, height: 222)
        source.addSession(placed, start: false)
        let missing = source.addSession(ManagedSession(name: "Unpositioned", kind: .cli), start: false)
        // Old versions did not persist displayed grid frames. Simulate a save with no measured viewport.
        source.shutdown()
        let restored = AppStore(stateURL: url)
        defer { restored.shutdown() }
        restored.prepareStartupLayout()
        restored.updateCanvasViewport(CGSize(width: 800, height: 500))
        XCTAssertEqual(restored.settings.layoutMode, .canvas)
        XCTAssertEqual(restored.session(placed.id)?.canvasPosition, placed.canvasPosition)
        XCTAssertEqual(restored.session(placed.id)?.paneSize, placed.paneSize)
        XCTAssertNotNil(restored.session(missing.id)?.canvasPosition)
        XCTAssertNil(restored.session(missing.id)?.paneSize)
    }
}
