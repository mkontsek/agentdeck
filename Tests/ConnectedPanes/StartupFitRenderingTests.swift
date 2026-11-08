import AppKit
import SwiftUI
import XCTest

@MainActor
final class StartupFitRenderingTests: XCTestCase {
    func testTwentyWindowOverviewHasVisibleNativeContentAndAutomaticFont() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        for index in 0..<20 {
            var session = ManagedSession(name: "Agent \(index + 1)", kind: .cli)
            session.canvasPosition = PanePoint(x: Double(index) * 1000, y: 1000)
            session = store.addSession(session, start: false, focus: false)
            store.runtime[session.id]?.isRunning = true
            _ = store.terminals.makeView(for: session.id, font: store.font(for: session))
        }
        store.prepareStartupLayout()
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1200, height: 760), styleMask: [.titled], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: PaneGridView().environmentObject(store).preferredColorScheme(.dark))
        window.contentView = host
        window.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(store.panes.count, 20)
        for terminal in store.terminals.views.values {
            XCTAssertTrue(terminal.window === window)
            XCTAssertGreaterThan(terminal.bounds.height, 40)
            XCTAssertGreaterThan(terminal.bounds.width, 150)
            XCTAssertLessThan(terminal.font.pointSize, store.settings.globalFontSize)
        }
        for scheme in [ColorScheme.dark, .light] {
            host.rootView = PaneGridView().environmentObject(store).preferredColorScheme(scheme)
            try await Task.sleep(for: .milliseconds(150))
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
                to: URL(fileURLWithPath: "/tmp/agentdeck-startup-fit-\(scheme).png"))
        }
    }
}
