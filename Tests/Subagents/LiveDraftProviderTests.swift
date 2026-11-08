import AppKit
import XCTest

final class LiveDraftProviderTests: XCTestCase {
    @MainActor
    func testCodexLaunchArgumentAndUnfinishedComposerStaySeparate() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["AGENTDECK_LIVE_DRAFT"] == "1")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        let binary = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex").path
        let command =
            CommandTemplate.expand("{binary}", values: ["binary": binary])
            + " --no-alt-screen -c {briefingConfig} -- {initialPrompt}"
        store.settings.automaticSubagents = false
        store.cliProfiles.append(CLIProfile(id: "live-draft-fixture", name: "Live draft fixture", command: command))
        var session = ManagedSession(name: "Task79 isolated draft check", kind: .cli)
        session.cliProfileID = "live-draft-fixture"
        session.workingDirectory = directory.path
        session.initialPrompt =
            "Transport fixture only. Do not use tools, change files, or contact anyone. Calculate 773 plus 17 and reply with only the result."
        session.resumeLastConversation = false
        store.addSession(session)
        for _ in 0..<3000 {
            if store.terminals.visibleLines(id: session.id).contains(where: { $0.contains("790") }) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        // Never bypass a trust, password, setup or approval screen.
        guard store.terminals.visibleLines(id: session.id).contains(where: { $0.contains("790") }) else {
            XCTFail("Isolated provider did not accept the initial argv prompt; no keys sent")
            return
        }
        let view = try XCTUnwrap(store.terminals.view(for: session.id))
        view.pasteText("Human fixture: partial žltý 🧑🏽‍💻\nsecond line e\u{301}")
        try await Task.sleep(for: .milliseconds(300))
        view.send(txt: "\u{1b}[D\u{1b}[D")
        try await Task.sleep(for: .milliseconds(200))
        let before = store.terminals.visibleLines(id: session.id)
        let caret = view.selectedRange()
        for index in 0..<3 {
            XCTAssertTrue(
                store.inject(session.id, text: "Worker fixture \(index)", source: "worker", queueIfBusy: true))
        }
        store.runtime[session.id]?.status = .idle
        store.statusTick()
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(
            store.terminals.visibleLines(id: session.id), before, "Worker events changed the provider composer")
        XCTAssertEqual(view.selectedRange(), caret)
        XCTAssertEqual(store.inbox.pending(for: session).count, 3)
        XCTAssertTrue(store.inbox.events.allSatisfy { $0.receipt == .pending })
        // Do not submit the draft. Only this disposable provider is terminated by the store's defer.
    }
    @MainActor
    func testCodexReceivesBackgroundEventInSeparateMCPResult() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["AGENTDECK_LIVE_DRAFT"] == "1")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        store.settings.automaticSubagents = false
        store.settings.mcpPort = Int.random(in: 44000...49000)
        var requestReceived = false
        var releaseResponse: CheckedContinuation<Void, Never>?
        let server = MCPServer(port: UInt16(store.settings.mcpPort)) { method, path, body in
            let request = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
            let params = request?["params"] as? [String: Any]
            if params?["name"] as? String == "whoami" {
                requestReceived = true
                await withCheckedContinuation { releaseResponse = $0 }
            }
            return await store.handleHTTP(method: method, path: path, body: body)
        }
        try server.start()
        defer {
            releaseResponse?.resume()
            server.stop()
        }
        let binary = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex").path
        let command =
            CommandTemplate.expand("{binary}", values: ["binary": binary])
            + " --no-alt-screen --dangerously-bypass-approvals-and-sandbox -c {briefingConfig} -c 'mcp_servers.agentdeck.url=\"{mcpUrl}\"' -- {initialPrompt}"
        store.cliProfiles.append(CLIProfile(id: "live-inbox-fixture", name: "Live inbox fixture", command: command))
        var session = ManagedSession(name: "Task79 isolated MCP check", kind: .cli)
        session.cliProfileID = "live-inbox-fixture"
        session.workingDirectory = directory.path
        session.resumeLastConversation = false
        session.initialPrompt =
            "Transport fixture. Call ONLY AgentDeck whoami once. Its response will include a separate coordination inbox event. Acknowledge that event with acknowledge_inbox and reply only with its text. Do not use other tools, change files, or contact anyone."
        store.addSession(session, start: false)
        store.startSession(session.id)
        for _ in 0..<3000 where !requestReceived {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard requestReceived else {
            XCTFail("Provider did not request the fixture MCP tool")
            return
        }
        // A real provider tool response is held while the human fixture edits its composer.
        let view = try XCTUnwrap(store.terminals.view(for: session.id))
        view.pasteText("DRAFT79_abcΩxyz")
        for _ in 0..<250
        where !store.terminals.visibleLines(id: session.id).contains(where: { $0.contains("DRAFT79_abcΩxyz") }) {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(store.terminals.visibleLines(id: session.id).contains(where: { $0.contains("DRAFT79_abcΩxyz") }))
        view.send(txt: "\u{1b}[D\u{1b}[D\u{1b}[D")
        let event = try XCTUnwrap(
            store.queueCoordination(session.id, text: "MCP_FIXTURE_ACCEPTED_79", source: "fixture"))
        releaseResponse?.resume()
        releaseResponse = nil
        for _ in 0..<3000 {
            if store.inbox.events.first(where: { $0.id == event.id })?.receipt == .acknowledged { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        if store.inbox.events.first(where: { $0.id == event.id })?.receipt != .acknowledged {
            let diagnostic = store.terminals.visibleLines(id: session.id).filter {
                $0.localizedCaseInsensitiveContains("approval") || $0.localizedCaseInsensitiveContains("permission")
                    || $0.localizedCaseInsensitiveContains("mcp") || $0.localizedCaseInsensitiveContains("error")
                    || $0.localizedCaseInsensitiveContains("trust") || $0.localizedCaseInsensitiveContains("tool")
            }
            XCTFail("Disposable fixture diagnostics: \(diagnostic)")
        }
        XCTAssertEqual(
            store.inbox.events.first(where: { $0.id == event.id })?.receipt, .acknowledged,
            "Provider must receive and explicitly acknowledge the real MCP result")
        // Receipt is persisted before the provider receives its HTTP response and finishes repainting.
        for _ in 0..<250
        where !store.terminals.visibleLines(id: session.id).contains(where: { $0.contains("DRAFT79_abcΩxyz") }) {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(
            store.terminals.visibleLines(id: session.id).contains(where: { $0.contains("DRAFT79_abcΩxyz") }),
            "MCP receipt must preserve the human draft")
        view.insertText("V", replacementRange: NSRange(location: NSNotFound, length: 0))
        for _ in 0..<250
        where !store.terminals.visibleLines(id: session.id).contains(where: { $0.contains("DRAFT79_abcΩVxyz") }) {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(
            store.terminals.visibleLines(id: session.id).contains(where: { $0.contains("DRAFT79_abcΩVxyz") }),
            "MCP receipt must preserve the logical mid-text caret")
        XCTAssertFalse(store.log.contains { $0.message.hasPrefix("Explicit input sent") })
    }

}
