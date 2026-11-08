import AppKit
import XCTest

final class MessageSubmissionTests: XCTestCase {
    @MainActor
    func testExplicitUserInjectionUsesNegotiatedPasteAndSeparateSubmit() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        let text = String(repeating: "Worker result — verified. ", count: 300).singleLine
        let expected = "\u{1b}[200~" + text + "\u{1b}[201~\r"
        let output = directory.appendingPathComponent("received.bin")
        let command =
            "stty raw -echo; printf '\\033[?2004hPASTE_READY\\n'; dd bs=1 count=\(expected.utf8.count) of="
            + CommandTemplate.expand("{file}", values: ["file": output.path]) + " 2>/dev/null"
        store.cliProfiles.append(CLIProfile(id: "paste-fixture", name: "Paste fixture", command: command))
        var session = ManagedSession(name: "Paste fixture", kind: .cli)
        session.cliProfileID = "paste-fixture"
        session.workingDirectory = directory.path
        store.addSession(session)
        for _ in 0..<500
        where !store.terminals.visibleLines(id: session.id).contains(where: { $0.contains("PASTE_READY") }) {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(store.terminals.visibleLines(id: session.id).contains(where: { $0.contains("PASTE_READY") }))
        XCTAssertTrue(store.inject(session.id, text: text, source: "user"))
        for _ in 0..<250 where store.runtime[session.id]?.isRunning == true {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(try Data(contentsOf: output), Data(expected.utf8))
        XCTAssertEqual(store.runtime[session.id]?.exitCode, 0)
    }

    @MainActor
    func testLiveCodexAcceptsAutomaticSubmission() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["AGENTDECK_LIVE_CODEX_SUBMIT"] == "1")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        let binary = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex").path
        let command = CommandTemplate.expand("{binary}", values: ["binary": binary]) + " --no-alt-screen"
        store.cliProfiles.append(CLIProfile(id: "live-codex-submit", name: "Live Codex", command: command))
        var session = ManagedSession(name: "Live submission smoke", kind: .cli)
        session.cliProfileID = "live-codex-submit"
        session.workingDirectory = directory.path
        store.addSession(session)
        // Wait for the real composer, never submit into setup, login or an approval prompt.
        for _ in 0..<1500 {
            if store.terminals.visibleLines(id: session.id).contains(where: {
                $0.contains("› Ask Codex to do anything")
            }) {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let ready = store.terminals.visibleLines(id: session.id)
        XCTAssertTrue(
            ready.contains(where: { $0.contains("› Ask Codex to do anything") }),
            ready.joined(separator: "\n"))
        guard ready.contains(where: { $0.contains("› Ask Codex to do anything") }) else { return }
        let prompt =
            "Transport smoke check. Do not use tools or change files. Calculate 773 plus 17 and reply with only the result. "
            + String(repeating: "Ignore this filler sentence. ", count: 200)
        XCTAssertTrue(store.inject(session.id, text: prompt, source: "user"))
        for _ in 0..<3000 {
            if store.terminals.visibleLines(id: session.id).contains(where: { $0.contains("790") }) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let result = store.terminals.visibleLines(id: session.id)
        XCTAssertTrue(result.contains(where: { $0.contains("790") }), result.joined(separator: "\n"))
    }
}
