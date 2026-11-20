import AppKit
import SwiftUI
import XCTest

@MainActor
final class SessionRenameTests: XCTestCase {
    func testRenamePersistsOnlyTheTargetAndKeepsSessionIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        var owner = ManagedSession(name: "Original", kind: .cli)
        owner.cliProfileID = "codex"
        owner = store.addSession(owner, start: false)
        let sibling = try XCTUnwrap(store.addCLITab(to: owner.id, start: false))
        var browser = ManagedSession(name: "Browser", kind: .browser)
        browser.agentOwnerID = owner.id
        browser = store.addSession(browser, start: false)
        store.setCanvasPosition(for: owner.id, PanePoint(x: 100, y: 200))
        store.setPaneSize(for: owner.id, PaneSize(width: 700, height: 500))
        let before = try XCTUnwrap(store.session(owner.id))
        let selection = store.selectedPaneTabs
        let endpoint = store.mcpURL(for: owner.id)

        XCTAssertFalse(store.renameSession(owner.id, to: " \n\t "))
        XCTAssertFalse(store.renameSession(UUID(), to: "Missing"))
        XCTAssertEqual(store.session(owner.id), before)
        XCTAssertTrue(store.renameSession(owner.id, to: "  Návrh 🛴  "))
        var expected = before
        expected.name = "Návrh 🛴"
        XCTAssertEqual(store.session(owner.id), expected)
        XCTAssertEqual(store.session(sibling.id)?.name, sibling.name)
        XCTAssertEqual(store.session(browser.id)?.name, browser.name)
        XCTAssertEqual(store.selectedPaneTabs, selection)
        XCTAssertEqual(store.mcpURL(for: owner.id), endpoint)
        XCTAssertTrue(store.renameSession(browser.id, to: "Research"))
        XCTAssertEqual(store.session(browser.id)?.agentOwnerID, owner.id)
        XCTAssertEqual(store.session(browser.id)?.browserProfileID, browser.browserProfileID)
        store.saveNow()
        let restored = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer { restored.shutdown() }
        XCTAssertEqual(restored.session(owner.id)?.name, "Návrh 🛴")
        XCTAssertEqual(restored.session(browser.id)?.name, "Research")
        XCTAssertEqual(restored.session(sibling.id)?.name, sibling.name)
    }

    func testDialogFocusKeyboardSaveCancelAndThemes() async throws {
        _ = NSApplication.shared
        for scheme in [ColorScheme.light, .dark] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
            let session = store.addSession(ManagedSession(name: "Original name", kind: .cli), start: false)
            let other = store.addSession(ManagedSession(name: "Other tab", kind: .cli), start: false)
            let presentation = RenamePresentation()
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 600, height: 360),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let host = NSHostingView(
                rootView: RenameFixture(presentation: presentation, session: session)
                    .environmentObject(store).preferredColorScheme(scheme))
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            defer {
                window.close()
                store.shutdown()
                try? FileManager.default.removeItem(at: directory)
            }
            presentation.presented = true
            try await Task.sleep(for: .milliseconds(400))
            let sheet = try XCTUnwrap(window.attachedSheet)
            let editor = try XCTUnwrap(sheet.firstResponder as? NSTextView)
            XCTAssertEqual(editor.string, "Original name")
            let content = try XCTUnwrap(sheet.contentView)
            let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
            content.cacheDisplay(in: content.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
                to: FileManager.default.temporaryDirectory.appendingPathComponent("agentdeck-rename-\(scheme).png"))
            editor.selectAll(nil)
            editor.insertText("Cancelled edit", replacementRange: editor.selectedRange())
            sheet.cancelOperation(nil)
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertFalse(presentation.presented)
            XCTAssertEqual(store.session(session.id)?.name, "Original name")

            presentation.presented = true
            try await Task.sleep(for: .milliseconds(300))
            let secondSheet = try XCTUnwrap(window.attachedSheet)
            let secondEditor = try XCTUnwrap(secondSheet.firstResponder as? NSTextView)
            XCTAssertEqual(secondEditor.string, "Original name")
            secondEditor.selectAll(nil)
            secondEditor.insertText("  Renamed 🛴  ", replacementRange: secondEditor.selectedRange())
            store.focusedSessionID = other.id
            secondEditor.insertNewline(nil)
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertEqual(store.session(session.id)?.name, "Renamed 🛴")
            XCTAssertEqual(store.session(other.id)?.name, "Other tab")
            XCTAssertFalse(presentation.presented)
        }
    }
}

@MainActor
private final class RenamePresentation: ObservableObject {
    @Published var presented = false
}

private struct RenameFixture: View {
    @ObservedObject var presentation: RenamePresentation
    let session: ManagedSession

    var body: some View {
        Text("Rename fixture").frame(width: 600, height: 360)
            .sheet(isPresented: $presentation.presented) { RenameSessionSheet(session: session) }
    }
}
