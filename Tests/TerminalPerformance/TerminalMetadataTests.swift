import AppKit
import Combine
import XCTest

@MainActor
final class TerminalMetadataTests: XCTestCase {
    func testNativeRepeatedMetadataPublishesOnlyChangesAndPreservesText() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        let session = store.addSession(ManagedSession(name: "Metadata fixture", kind: .cli), start: false)
        store.runtime[session.id]?.isRunning = true
        let terminal = store.terminals.makeView(
            for: session.id, font: .monospacedSystemFont(ofSize: 12, weight: .regular))
        terminal.startProcess(
            executable: "/bin/sh", args: ["-c", "stty raw -echo; printf READY; exec /bin/cat"],
            environment: ["TERM=xterm-256color", "PATH=/usr/bin:/bin"], currentDirectory: directory.path)
        try await waitUntil { store.terminals.visibleLines(id: session.id).joined().contains("READY") }
        let title = "\u{1b}]0;Fixture title\u{7}"
        let working = "\u{1b}]7501;state=working:msg=V29ya2luZw\u{7}"
        terminal.send(txt: title + working)
        try await waitUntil {
            store.runtime[session.id]?.title == "Fixture title"
                && store.runtime[session.id]?.programState == "working"
                && store.runtime[session.id]?.programMessage == "Working"
        }
        var changes = 0
        let observation = store.objectWillChange.sink { changes += 1 }
        // These bytes go through the actual input writer, child PTY, parser, and main-thread delegates.
        // A final changed state provides an ordered callback barrier for all the repeated metadata.
        terminal.send(
            txt: String(repeating: title + working, count: 200)
                + "\u{1b}]7501;state=done:msg=V29ya2luZw\u{7}\r\nPHASE1")
        try await waitUntil {
            store.runtime[session.id]?.programState == "done"
                && store.terminals.visibleLines(id: session.id).joined().contains("PHASE1")
        }
        XCTAssertEqual(changes, 1, "Repeated metadata must not invalidate the entire workspace")
        changes = 0
        terminal.send(txt: "\u{1b}]0;Changed title\u{7}\u{1b}]7501;state=blocked:msg=SGVsbG8\u{7}\r\nPHASE2")
        try await waitUntil {
            store.runtime[session.id]?.title == "Changed title"
                && store.runtime[session.id]?.programState == "blocked"
                && store.runtime[session.id]?.programMessage == "Hello"
                && store.terminals.visibleLines(id: session.id).joined().contains("PHASE2")
        }
        XCTAssertEqual(changes, 1, "Title and status changes in the same frame publish together")
        changes = 0
        terminal.send(txt: "\u{1b}]7501;state=clear\u{7}\r\nPHASE3")
        try await waitUntil {
            store.runtime[session.id]?.programState == nil && store.runtime[session.id]?.programMessage == nil
                && store.terminals.visibleLines(id: session.id).joined().contains("PHASE3")
        }
        XCTAssertEqual(changes, 1)
        let text = "draft žluťoučký 🐻 abcdefghijklmnopqrstuvwxyz"
        terminal.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        try await waitUntil {
            store.terminals.visibleLines(id: session.id).joined().contains("abcdefghijklmnopqrstuvwxyz")
        }
        let screen = store.terminals.visibleLines(id: session.id).joined()
        XCTAssertTrue(screen.contains("PHASE1"))
        XCTAssertTrue(screen.contains("PHASE2"))
        XCTAssertTrue(screen.contains("PHASE3"))
        XCTAssertTrue(screen.contains(text))
        withExtendedLifetime(observation) {}
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(condition(), "Native metadata fixture timed out")
    }
}
