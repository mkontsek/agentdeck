import AppKit
import XCTest

final class DraftPreservationTests: XCTestCase {
    @MainActor
    func testWorkerCannotWriteIntoNativeDraft() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        let output = directory.appendingPathComponent("fixture-input.bin")
        let command =
            "stty raw -echo; printf '\\033[?2004hDRAFT_READY\\n'; cat > "
            + CommandTemplate.expand("{file}", values: ["file": output.path])
        store.cliProfiles.append(CLIProfile(id: "draft-fixture", name: "Draft fixture", command: command))
        var session = ManagedSession(name: "Draft fixture", kind: .cli)
        session.cliProfileID = "draft-fixture"
        session.workingDirectory = directory.path
        store.addSession(session)
        let initialEventCount = store.inbox.pending(for: session).count
        let view = try XCTUnwrap(store.terminals.view(for: session.id))
        for _ in 0..<500
        where !store.terminals.visibleLines(id: session.id).contains(where: { $0.contains("DRAFT_READY") }) {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(store.terminals.visibleLines(id: session.id).contains(where: { $0.contains("DRAFT_READY") }))
        let draft = "in agentdeck, each subagent should have\nžltý 🧑🏽‍💻 e\u{301}"
        view.pasteText(draft)
        let paste = Data(("\u{1b}[200~" + draft + "\u{1b}[201~").utf8)
        for _ in 0..<100 where (try? Data(contentsOf: output).count) != paste.count {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(try Data(contentsOf: output), paste)
        view.send(txt: "\u{1b}[3D")
        view.insertText("Ω", replacementRange: NSRange(location: NSNotFound, length: 0))
        let expected = Data(("\u{1b}[200~" + draft + "\u{1b}[201~\u{1b}[3DΩ").utf8)
        for _ in 0..<100 where (try? Data(contentsOf: output).count) != expected.count {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(try Data(contentsOf: output), expected)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeFirstResponder(view)
        defer {
            window.contentView = nil
            window.close()
        }
        view.selectAll(nil)
        view.setMarkedText(
            "仮", selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        let selection = view.selectedRange()
        let marked = view.markedRange()
        let focused = store.focusedSessionID
        for status in [SessionStatus.working, .idle, .waitingForUser, .exited, .starting] {
            store.runtime[session.id]?.status = status
            XCTAssertTrue(
                store.inject(
                    session.id, text: "[worker fixture] Task complete \(status)", source: "worker", queueIfBusy: true))
            store.statusTick()
        }
        store.injectContextNow(session.id)
        let sent = store.callTool(
            name: "send_message",
            args: ["target_session": "me", "text": "Another result", "message_id": "native-fixture"], caller: session.id
        )
        XCTAssertFalse(sent.isError)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(try Data(contentsOf: output), expected, "Background delivery wrote into the native human draft")
        XCTAssertTrue(window.firstResponder === view)
        XCTAssertEqual(store.focusedSessionID, focused)
        XCTAssertEqual(view.selectedRange(), selection)
        XCTAssertEqual(view.markedRange(), marked)
        XCTAssertTrue(view.hasMarkedText())
        // Commit the synthetic IME and press Enter while more updates are accepted.
        view.unmarkText()
        view.insertText("仮", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(store.inject(session.id, text: "Race fixture", source: "worker"))
        view.send(txt: "\r")
        store.statusTick()
        let submitted = expected + Data("仮\r".utf8)
        for _ in 0..<100 where (try? Data(contentsOf: output).count) != submitted.count {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(try Data(contentsOf: output), submitted, "Only the human fixture may submit")
        XCTAssertEqual(store.inbox.pending(for: session).count, initialEventCount + 8)
        store.stopSession(session.id)
        XCTAssertEqual(store.inbox.pending(for: session).count, initialEventCount + 8)
        store.restartSession(session.id)
        for _ in 0..<500
        where !store.terminals.visibleLines(id: session.id).contains(where: { $0.contains("DRAFT_READY") }) {
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(try Data(contentsOf: output), Data(), "Restart never replays terminal keystrokes")
        XCTAssertEqual(store.inbox.pending(for: session).count, initialEventCount + 8)
    }
}
