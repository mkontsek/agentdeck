import XCTest

final class CanvasLayoutTests: XCTestCase {
    func testBalancedRowsFillViewportWithoutOverlap() {
        for count in [1, 2, 3, 5, 7, 11] {
            let viewport = CGSize(width: 1800, height: 1000)
            let frames = CanvasLayout.frames(count: count, viewport: viewport)
            XCTAssertEqual(frames.count, count)
            for (index, frame) in frames.enumerated() {
                XCTAssertGreaterThanOrEqual(frame.width, CanvasLayout.minimumWidth)
                XCTAssertGreaterThanOrEqual(frame.height, CanvasLayout.minimumHeight)
                XCTAssertGreaterThanOrEqual(frame.minX, CanvasLayout.spacing)
                XCTAssertLessThanOrEqual(frame.maxX, viewport.width - CanvasLayout.spacing + 0.001)
                XCTAssertLessThanOrEqual(frame.maxY, viewport.height - CanvasLayout.spacing + 0.001)
                for other in frames.dropFirst(index + 1) { XCTAssertFalse(frame.intersects(other)) }
            }
            let rows = Dictionary(grouping: frames, by: \.minY)
            for row in rows.values {
                XCTAssertEqual(row.first?.minX, CGFloat(CanvasLayout.spacing))
                XCTAssertEqual(row.last!.maxX, viewport.width - CanvasLayout.spacing, accuracy: 0.001)
            }
            XCTAssertEqual(frames.last!.maxY, viewport.height - CanvasLayout.spacing, accuracy: 0.001)
        }
    }

    func testSmallCanvasScrollsInsteadOfMakingPanesUnreadable() {
        let frames = CanvasLayout.frames(count: 5, viewport: CGSize(width: 600, height: 400))
        XCTAssertEqual(frames.count, 5)
        XCTAssertTrue(frames.allSatisfy { $0.width >= 320 && $0.height >= 200 })
        XCTAssertGreaterThan(frames.last!.maxY, 400)
        XCTAssertTrue(CanvasLayout.frames(count: 0, viewport: CGSize(width: 1000, height: 700)).isEmpty)
        XCTAssertTrue(CanvasLayout.frames(count: 2, viewport: .zero).isEmpty)
        XCTAssertTrue(CanvasLayout.frames(count: 2, viewport: CGSize(width: CGFloat.nan, height: 700)).isEmpty)
    }

    @MainActor
    func testFillAndTidyKeepClaudeAndCodexFirstDespiteFocusAndPersistLayout() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("state.json")
        let store = AppStore(stateURL: url)
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        let sessions = DefaultSessions.make(profiles: CLIProfile.builtins.reversed(), workingDirectory: "/tmp")
        for session in sessions.reversed() { store.addSession(session, start: false) }
        XCTAssertEqual(store.sessions.prefix(2).map(\.cliProfileID), ["claude", "codex"])
        let claude = try XCTUnwrap(store.sessions.first)
        store.focusedSessionID = claude.id
        store.canvasViewport = CGSize(width: 1200, height: 800)
        store.fillCanvas()
        XCTAssertEqual(store.sessions.prefix(2).map(\.cliProfileID), ["claude", "codex"])
        let frames = CanvasLayout.frames(count: store.sessions.count, viewport: store.canvasViewport)
        for (session, frame) in zip(store.sessions, frames) {
            XCTAssertEqual(session.canvasPosition, PanePoint(x: frame.minX, y: frame.minY))
            XCTAssertEqual(session.paneSize, PaneSize(width: frame.width, height: frame.height))
        }
        store.tidyCanvas(viewportWidth: 1200)
        XCTAssertEqual(store.session(claude.id)?.canvasPosition, PanePoint(x: 16, y: 16))
        store.saveNow()
        let restored = AppStore(stateURL: url)
        defer { restored.shutdown() }
        XCTAssertEqual(restored.sessions.map(\.id), store.sessions.map(\.id))
        XCTAssertEqual(restored.sessions.map(\.canvasPosition), store.sessions.map(\.canvasPosition))
        XCTAssertEqual(restored.sessions.map(\.paneSize), store.sessions.map(\.paneSize))
        XCTAssertFalse(store.runtime.values.contains { $0.isRunning })
    }
}
