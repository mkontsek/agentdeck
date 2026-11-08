import AppKit
import XCTest

@MainActor
final class MetadataLifecycleTests: XCTestCase {
    func testQueuedMetadataCannotReachStoppedRemovedOrReplacementTerminal() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        let session = store.addSession(ManagedSession(name: "Metadata lifecycle", kind: .cli), start: false)
        store.runtime[session.id]?.isRunning = true
        _ = store.terminals.makeView(for: session.id, font: store.font(for: session))
        store.queueTerminalMetadata(session.id, title: "old process")
        store.terminals.dispose(id: session.id)
        _ = store.terminals.makeView(for: session.id, font: store.font(for: session))
        store.flushTerminalMetadata()
        XCTAssertNil(store.runtime[session.id]?.title)
        store.queueTerminalMetadata(session.id, title: "before stop")
        store.stopSession(session.id)
        store.queueTerminalMetadata(session.id, title: "late callback")
        store.flushTerminalMetadata()
        XCTAssertNil(store.runtime[session.id]?.title)
        store.runtime[session.id]?.isRunning = true
        store.queueTerminalMetadata(session.id, title: "before generation change")
        store.runtime[session.id]?.generation += 1
        store.flushTerminalMetadata()
        XCTAssertNil(store.runtime[session.id]?.title)
        store.queueTerminalMetadata(session.id, title: "removed")
        store.removeSession(session.id)
        store.flushTerminalMetadata()
        XCTAssertNil(store.runtime[session.id])
        XCTAssertTrue(store.pendingTerminalMetadata.isEmpty)
        XCTAssertNil(store.terminalMetadataFlushTask)
    }
}
