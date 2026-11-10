import AppKit
import SwiftUI
import XCTest

@MainActor
final class SidebarNavigationTests: XCTestCase {
    func testRepeatedNativeArrowSelectionStaysInSidebarUntilReturn() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        store.settings.workspaceMode = .sessions
        for index in 0..<4 {
            let session = store.addSession(
                ManagedSession(name: "Keyboard fixture \(index)", kind: .cli), start: false, focus: false)
            store.runtime[session.id]?.isRunning = true
            _ = store.terminals.makeView(for: session.id, font: store.font(for: session))
        }
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(
            rootView: HStack(spacing: 0) {
                SidebarView().frame(width: 260)
                PaneGridView()
            }.environmentObject(store))
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            store.shutdown()
            window.close()
            try? FileManager.default.removeItem(at: directory)
        }
        try await Task.sleep(for: .milliseconds(350))
        let table = try XCTUnwrap(descendants(host).compactMap { $0 as? NSTableView }.first)
        print("SIDEBAR_NATIVE table=\(type(of: table)) rows=\(table.numberOfRows)")
        store.focusedSessionID = store.sessions[0].id
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(window.makeFirstResponder(table))
        for index in 1...3 {
            window.sendEvent(try key(.downArrow, code: 125, window: window))
            try await Task.sleep(for: .milliseconds(80))
            XCTAssertEqual(store.focusedSessionID, store.sessions[index].id)
            XCTAssertTrue(window.firstResponder === table)
        }
        window.sendEvent(try key(.downArrow, code: 125, window: window))
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(store.focusedSessionID, store.sessions[3].id, "Last row is a navigation boundary")
        window.sendEvent(try key(.upArrow, code: 126, window: window))
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(store.focusedSessionID, store.sessions[2].id)
        window.sendEvent(try key(.return, code: 36, window: window))
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(window.firstResponder === store.terminals.view(for: store.sessions[2].id))
        window.sendEvent(try key(.upArrow, code: 126, window: window))
        XCTAssertEqual(store.focusedSessionID, store.sessions[2].id, "Terminal arrows must not navigate the list")
        XCTAssertTrue(window.makeFirstResponder(table))
        for _ in 0..<4 {
            window.sendEvent(try key(.upArrow, code: 126, window: window))
            try await Task.sleep(for: .milliseconds(80))
        }
        XCTAssertEqual(store.focusedSessionID, store.sessions[0].id, "First row is a navigation boundary")
        XCTAssertTrue(window.firstResponder === table)
        let selected = store.focusedSessionID
        store.selectSidebarSession(UUID())
        XCTAssertEqual(store.focusedSessionID, selected, "A stale selection is ignored")
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private func key(_ key: KeyEquivalent, code: UInt16, window: NSWindow) throws -> NSEvent {
        let value = String(key.character)
        return try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                characters: value, charactersIgnoringModifiers: value, isARepeat: false, keyCode: code))
    }
}
