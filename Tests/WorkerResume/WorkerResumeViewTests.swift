import AppKit
import SwiftUI
import XCTest

final class WorkerResumeViewTests: XCTestCase {
    @MainActor
    func testResumeSheetShowsReceiptAndEditorInBothThemes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        var parent = ManagedSession(name: "Resume UI fixture", kind: .cli)
        parent.cliProfileID = "codex"
        store.addSession(parent, start: false)
        let child = try store.delegateTask(
            from: parent.id, title: "UI fixture", instructions: "No provider launched", start: false)
        let request = WorkerResumeRequest(
            id: UUID(), workerID: child.id, parentID: parent.id,
            taskID: child.delegatedTaskID!, taskRevision: 1, generation: 0, conversationID: UUID().uuidString,
            directory: directory.path, instructions: "Fixture", phase: .uncertain,
            detail: "Submission outcome is uncertain. Cancel / reconcile before retrying.")
        try store.workerResumes.put(request)
        for scheme in [ColorScheme.light, .dark] {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 480), styleMask: [.titled], backing: .buffered,
                defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            let host = NSHostingView(
                rootView: WorkerResumeSheet(workerID: child.id).environmentObject(store).preferredColorScheme(scheme)
                    .background(Color(nsColor: .windowBackgroundColor)))
            window.contentView = host
            window.orderFrontRegardless()
            try await Task.sleep(for: .milliseconds(250))
            host.layoutSubtreeIfNeeded()
            let editors = descendants(host).compactMap { $0 as? NSTextView }
            XCTAssertEqual(editors.count, 1)
            XCTAssertGreaterThan(editors.first?.bounds.width ?? 0, 400)
            XCTAssertLessThanOrEqual(host.fittingSize.width, 521)
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let name = scheme == .dark ? "agentdeck-resume97-dark.png" : "agentdeck-resume97-light.png"
            try data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent(name))
            window.close()
        }
    }

    @MainActor
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
}
