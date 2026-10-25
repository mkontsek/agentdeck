import AppKit
import XCTest

final class TerminalLifecycleTests: XCTestCase {
    @MainActor
    func testRestartDoesNotReceivePreviousDelayedSubmit() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        let output = directory.appendingPathComponent("received.txt")
        let command =
            "printf 'ready\\n'; read -r line; printf '%s' \"$line\" > "
            + CommandTemplate.expand("{file}", values: ["file": output.path])
        store.cliProfiles.append(CLIProfile(id: "test", name: "Test", command: command, submitDelayMs: 500))
        var session = ManagedSession(name: "Lifecycle", kind: .cli)
        session.cliProfileID = "test"
        session.workingDirectory = directory.path
        store.addSession(session)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(store.terminals.isRunning(session.id))
        let oldView = try XCTUnwrap(store.terminals.view(for: session.id))
        XCTAssertTrue(store.inject(session.id, text: "old input"))
        store.restartSession(session.id)
        let newView = try XCTUnwrap(store.terminals.view(for: session.id))
        XCTAssertFalse(oldView === newView)
        // Outlast the old 500 ms submit delay, then wait until the replacement shell is actually reading: an
        // interactive zsh flushes type-ahead while it starts, and a loaded machine can take seconds to get there.
        try await Task.sleep(for: .milliseconds(800))
        for _ in 0..<500 where !store.terminals.visibleLines(id: session.id).contains(where: { $0.contains("ready") }) {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(store.runtime[session.id]?.isRunning == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path), "Old Enter reached the new shell")
        XCTAssertTrue(store.inject(session.id, text: "new input"))
        for _ in 0..<500 where store.runtime[session.id]?.isRunning == true {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "new input")
        XCTAssertEqual(store.runtime[session.id]?.exitCode, 0)
        XCTAssertEqual(store.runtime[session.id]?.status, .exited)
        XCTAssertFalse(store.terminals.isRunning(session.id))
    }

    @MainActor
    func testAutomatedMessagesCannotExecuteInPlainShell() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        var session = ManagedSession(name: "Shell", kind: .cli)
        session.cliProfileID = "shell"
        store.addSession(session, start: false)
        store.runtime[session.id]?.isRunning = true
        store.runtime[session.id]?.status = .idle
        XCTAssertFalse(store.inject(session.id, text: "do something", source: "agent", queueIfBusy: true))
        XCTAssertTrue(
            store.callTool(name: "send_message", args: ["target_session": "me", "text": "hello"], caller: session.id)
                .isError)
    }
}
