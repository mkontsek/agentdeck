import XCTest

final class InboxTests: XCTestCase {
    @MainActor
    func testAtomicAcceptanceReceiptsDeduplicationAndRecovery() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("inbox.json")
        let inbox = CoordinationInbox(url: url)
        var target = ManagedSession(name: "Fixture", kind: .cli)
        target.cliProfileID = "codex"
        let event = try inbox.enqueue(target: target, text: "First\nŽ 🧑🏽‍💻", source: "worker", key: "event-1")
        XCTAssertEqual(event.receipt, .pending)
        XCTAssertThrowsError(try inbox.acknowledge([event.id], by: target))
        XCTAssertEqual(
            try inbox.enqueue(target: target, text: event.text, source: "worker", key: "event-1").id, event.id)
        XCTAssertThrowsError(try inbox.enqueue(target: target, text: "Different", source: "worker", key: "event-1"))
        let restored = CoordinationInbox(url: url)
        XCTAssertEqual(restored.events, inbox.events)
        let batch = try restored.offer(to: target)
        XCTAssertEqual(batch.map(\.id), [event.id])
        XCTAssertEqual(batch.first?.receipt, .offered)
        XCTAssertEqual(try restored.offer(to: target), batch, "Lost response must keep the same event ID")
        var stranger = target
        stranger.id = UUID()
        XCTAssertThrowsError(try restored.acknowledge([event.id], by: stranger))
        XCTAssertTrue(try restored.offer(to: stranger).isEmpty)
        stranger = target
        stranger.cliProfileID = "claude"
        XCTAssertTrue(try restored.offer(to: stranger).isEmpty)
        stranger = target
        stranger.workingDirectory = "/different"
        XCTAssertTrue(try restored.offer(to: stranger).isEmpty)
        try restored.acknowledge([event.id], by: target)
        try restored.acknowledge([event.id], by: target)
        XCTAssertTrue(CoordinationInbox(url: url).pending(for: target).isEmpty)
        XCTAssertEqual(
            try restored.enqueue(target: target, text: event.text, source: "worker", key: "event-1").receipt,
            .acknowledged)
        XCTAssertEqual(restored.events.count, 1)
    }

    @MainActor
    func testCorruptAndFailedStorageNeverClaimsAcceptanceOrOverwritesOriginal() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("inbox.json")
        let original = Data("broken fixture".utf8)
        try original.write(to: url)
        let inbox = CoordinationInbox(url: url)
        let target = ManagedSession(name: "Fixture", kind: .cli)
        XCTAssertNotNil(inbox.loadError)
        XCTAssertThrowsError(try inbox.enqueue(target: target, text: "Fixture", source: "worker", key: "1"))
        XCTAssertEqual(try Data(contentsOf: url), original)
        let impossible = CoordinationInbox(url: url.appendingPathComponent("not-a-directory.json"))
        XCTAssertThrowsError(try impossible.enqueue(target: target, text: "Fixture", source: "worker", key: "1"))
        XCTAssertTrue(impossible.events.isEmpty)
    }

    @MainActor
    func testBatchOrderAndReceiptStateSurviveRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("inbox.json")
        let target = ManagedSession(name: "Fixture", kind: .cli)
        let inbox = CoordinationInbox(url: url)
        for index in 0..<19 {
            _ = try inbox.enqueue(target: target, text: "Result \(index)", source: "worker", key: "\(index)")
        }
        let batch = try inbox.offer(to: target)
        XCTAssertEqual(batch.map(\.text), (0..<16).map { "Result \($0)" })
        let restored = CoordinationInbox(url: url)
        XCTAssertEqual(try restored.offer(to: target), batch)
        try restored.acknowledge(Set(batch.map(\.id)), by: target)
        XCTAssertEqual(try restored.offer(to: target).map(\.text), ["Result 16", "Result 17", "Result 18"])
    }

    @MainActor
    func testAllCoordinationPathsUseDurableMailboxAndHTTPAttachesIt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("state.json")
        let store = AppStore(stateURL: url)
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        var parent = ManagedSession(name: "Main", kind: .cli)
        parent.cliProfileID = "codex"
        store.addSession(parent, start: false)
        let worker = try store.delegateTask(
            from: parent.id, title: "Fixture", instructions: "No provider", start: false)
        XCTAssertTrue(
            store.callTool(
                name: "send_message", args: ["target_session": parent.id.uuidString, "text": "No retry identity"],
                caller: worker.id
            ).isError)
        let sent = store.callTool(
            name: "send_message",
            args: ["target_session": parent.id.uuidString, "text": "Message", "message_id": "one"], caller: worker.id)
        XCTAssertFalse(sent.isError)
        XCTAssertTrue(sent.text.contains("durable-inbox"))
        _ = store.callTool(
            name: "send_message",
            args: ["target_session": parent.id.uuidString, "text": "Message", "message_id": "one"], caller: worker.id)
        XCTAssertEqual(store.inbox.pending(for: parent).count, 1)
        try store.reportSubagentResult(caller: worker.id, summary: "Result", blocked: false)
        try store.reportSubagentResult(caller: worker.id, summary: "Result", blocked: false)
        XCTAssertEqual(store.inbox.pending(for: parent).count, 2)
        store.injectContextNow(parent.id)
        let task = store.createTask(title: "Handoff", owner: worker.id)
        _ = try store.handoff(
            from: nil, to: parent, taskID: task.id, title: nil, description: nil, note: "Shared fixture")
        XCTAssertEqual(store.inbox.pending(for: parent).count, 4)
        XCTAssertNil(store.terminals.view(for: parent.id))
        let request: [String: Any] = [
            "jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": "read_board", "arguments": [:]],
        ]
        let response = await store.handleHTTP(
            method: "POST", path: "/mcp/\(parent.id)", body: try JSONSerialization.data(withJSONObject: request))
        let rpc = try XCTUnwrap(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        let result = try XCTUnwrap(rpc["result"] as? [String: Any])
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 2)
        XCTAssertTrue((content.last?["text"] as? String)?.contains("agentdeck_inbox") == true)
        XCTAssertEqual(store.inbox.pending(for: parent).count, 4, "HTTP response is an offer, not an acknowledgment")
        let ids = store.inbox.pending(for: parent).map { $0.id.uuidString }
        XCTAssertFalse(store.callTool(name: "acknowledge_inbox", args: ["message_ids": ids], caller: parent.id).isError)
        XCTAssertTrue(store.inbox.pending(for: parent).isEmpty)
        store.saveNow()
        let restored = AppStore(stateURL: url)
        defer { restored.shutdown() }
        XCTAssertEqual(restored.inbox.events.count, 4)
        XCTAssertTrue(restored.inbox.pending(for: parent).isEmpty)
        store.removeSession(parent.id)
        var replacement = parent
        replacement.id = UUID()
        store.addSession(replacement, start: false)
        XCTAssertTrue(store.inbox.pending(for: replacement).isEmpty)
    }
}
