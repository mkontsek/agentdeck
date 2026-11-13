import XCTest

@MainActor
final class WorkerResumeTransportTests: XCTestCase {
    private func fixture(mode: String) throws -> (AppStore, ManagedSession, ManagedSession, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        var parent = ManagedSession(name: "Protocol fixture parent", kind: .cli)
        parent.cliProfileID = "codex"
        parent.workingDirectory = directory.path
        store.addSession(parent, start: false)
        let child = try store.delegateTask(
            from: parent.id, title: "Protocol fixture", instructions: "Synthetic only", start: false)
        let threadID = UUID().uuidString
        store.saveResumeCheckpoint(
            SessionResumeCheckpoint(
                profileID: "codex", directory: directory.path, launchedAt: Date(), conversationID: threadID),
            for: child.id)
        store.workerResumeTransport = WorkerResumeTransport(
            executable: try ResumeProtocolFixture.write(directory: directory, threadID: threadID, mode: mode))
        store.runtime[child.id]?.status = .idle
        return (store, parent, child, directory)
    }

    private func wait(_ store: AppStore, until predicate: (WorkerResumePhase) -> Bool) async throws {
        for _ in 0..<500 {
            if let phase = store.workerResumes.requests.first?.phase, predicate(phase) { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out: \(store.workerResumes.requests.first?.detail ?? "no receipt")")
        if let directory = store.workerResumes.requests.first?.directory {
            print(
                "FIXTURE_PROTOCOL_TRACE: \((try? String(contentsOfFile: directory + "/protocol.jsonl")) ?? "missing")")
        }
    }

    func testIdleAndExitedNativeQueueStartProduceVerifiedReceiptWithoutShellEvaluation() async throws {
        for status in [SessionStatus.idle, .exited] {
            let (store, parent, child, directory) = try fixture(mode: "happy")
            defer {
                store.shutdown()
                try? FileManager.default.removeItem(at: directory)
            }
            store.runtime[child.id]?.status = status
            let literal = "Do the next step: žltý 🧑🏽‍💻 e\u{301}\n$(touch NEVER97); `id`; ' \""
            let request = try store.resumeWorker(
                from: parent.id, workerID: child.id, requestID: UUID(), instructions: literal)
            XCTAssertEqual(request.phase, .checking)
            try await wait(store) { !$0.reservesWorker }
            let receipt = try XCTUnwrap(store.workerResumes.requests.first)
            XCTAssertEqual(receipt.phase, .ended, receipt.detail)
            XCTAssertEqual(receipt.turnID, "turn97")
            XCTAssertEqual(receipt.queuedSubmissionID, "queue97")
            let messages = try String(contentsOf: directory.appendingPathComponent("protocol.jsonl")).split(
                separator: "\n"
            ).map {
                try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any]
            }
            XCTAssertEqual(messages.filter { $0["method"] as? String == "thread/queue/add" }.count, 1)
            XCTAssertEqual(messages.filter { $0["method"] as? String == "thread/queue/start" }.count, 1)
            XCTAssertFalse(messages.contains { $0["method"] as? String == "turn/start" })
            let add = try XCTUnwrap(
                messages.first { $0["method"] as? String == "thread/queue/add" }?["params"] as? [String: Any])
            XCTAssertEqual((add["input"] as? [[String: String]])?.first?["text"], literal)
            XCTAssertEqual(store.tasks[0].ownerSessionID, child.id)
            XCTAssertEqual(store.tasks[0].status, .inProgress)
            XCTAssertNil(store.terminals.view(for: child.id))
        }
    }

    func testProviderActiveAndActiveRaceNeverSteerRunningTurn() async throws {
        for mode in ["active", "race", "lost-acceptance"] {
            let (store, parent, child, directory) = try fixture(mode: mode)
            defer {
                store.shutdown()
                try? FileManager.default.removeItem(at: directory)
            }
            _ = try store.resumeWorker(
                from: parent.id, workerID: child.id, requestID: UUID(), instructions: "Only next explicit step")
            try await wait(store) { $0 == .failed || $0 == .uncertain }
            let request = try XCTUnwrap(store.workerResumes.requests.first)
            XCTAssertEqual(request.phase, mode == "lost-acceptance" ? .uncertain : .failed, request.detail)
            XCTAssertNil(request.turnID)
            let log = try String(contentsOf: directory.appendingPathComponent("protocol.jsonl"))
            XCTAssertFalse(log.contains("\"method\":\"turn/start\""))
            if mode == "active" { XCTAssertFalse(log.contains("thread/queue/add")) }
            if mode == "race" { XCTAssertTrue(log.contains("thread/queue/delete")) }
            XCTAssertEqual(store.tasks[0].status, .inProgress)
        }
    }

    func testCancellationTargetsOnlyVerifiedTurnAndExplicitStopPersists() async throws {
        let (store, parent, child, directory) = try fixture(mode: "running")
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        _ = try store.resumeWorker(
            from: parent.id, workerID: child.id, requestID: UUID(), instructions: "Long fixture work")
        try await wait(store) { $0 == .started }
        store.stopSession(child.id)
        try await wait(store) { $0 == .cancelled || $0 == .uncertain }
        XCTAssertEqual(store.workerResumes.requests.first?.phase, .cancelled)
        XCTAssertEqual(store.session(child.id)?.resumeStopped, true)
        let restored = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer { restored.shutdown() }
        XCTAssertEqual(restored.session(child.id)?.resumeStopped, true)
        restored.startSession(child.id)
        XCTAssertFalse(restored.terminals.isRunning(child.id), "Restarting the app must not undo explicit Stop")
        XCTAssertTrue(
            try String(contentsOf: directory.appendingPathComponent("protocol.jsonl")).contains("turn/interrupt"))
        XCTAssertThrowsError(
            try store.resumeWorker(
                from: parent.id, workerID: child.id, requestID: UUID(), instructions: "Do not silently undo Stop"))
    }

    func testHandoffDuringChecksCancelsBeforeSubmission() async throws {
        let (store, parent, child, directory) = try fixture(mode: "slow")
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        _ = try store.resumeWorker(from: parent.id, workerID: child.id, requestID: UUID(), instructions: "Pending")
        var task = store.tasks[0]
        task.ownerSessionID = parent.id
        store.tasks[0] = task  // Simulate an external/stale ownership change while the transport is suspended.
        try await wait(store) { !$0.reservesWorker }
        XCTAssertNil(store.workerResumes.requests.first?.turnID)
        let log = try String(contentsOf: directory.appendingPathComponent("protocol.jsonl"))
        XCTAssertFalse(log.contains("thread/queue/add"))
        XCTAssertEqual(store.tasks[0].ownerSessionID, parent.id)
    }

    func testCancellingOldReceiptNeverInterruptsNewerContinuation() async throws {
        let (store, parent, child, directory) = try fixture(mode: "running")
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        let current = try store.resumeWorker(
            from: parent.id, workerID: child.id, requestID: UUID(), instructions: "New continuation")
        try await wait(store) { $0 == .started }
        var old = current
        old.id = UUID()
        old.phase = .ended
        old.turnID = "old-turn"
        try store.workerResumes.put(old)
        let oldCancellation = store.callTool(
            name: "cancel_worker_resume", args: ["request_id": old.id.uuidString], caller: parent.id)
        XCTAssertFalse(oldCancellation.isError)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(store.workerResumes.requests.first?.phase, .started)
        XCTAssertFalse(
            try String(contentsOf: directory.appendingPathComponent("protocol.jsonl")).contains("turn/interrupt"))
        let currentCancellation = store.callTool(
            name: "cancel_worker_resume", args: ["request_id": current.id.uuidString], caller: parent.id)
        XCTAssertFalse(currentCancellation.isError)
        try await wait(store) { $0 == .cancelled }
        XCTAssertEqual(store.workerResumes.requests.last?.phase, .ended)
    }

    func testRestartUncertaintyRequiresExplicitReconciliationAndDoesNotRelaunch() async throws {
        let (store, parent, child, directory) = try fixture(mode: "happy")
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        let request = WorkerResumeRequest(
            id: UUID(), workerID: child.id, parentID: parent.id,
            taskID: child.delegatedTaskID!, taskRevision: store.tasks[0].revision, generation: 0,
            conversationID: store.resumeCheckpoints[child.id]!.conversationID!, directory: directory.path,
            instructions: "Lost response fixture", phase: .uncertain)
        try store.workerResumes.put(request)
        store.cancelWorkerResume(child.id)
        try await wait(store) { $0 == .cancelled }
        let log = try String(contentsOf: directory.appendingPathComponent("protocol.jsonl"))
        XCTAssertTrue(log.contains("thread/queue/list"))
        XCTAssertFalse(log.contains("thread/queue/add"))
        XCTAssertFalse(log.contains("thread/queue/start"))
        XCTAssertFalse(log.contains("turn/interrupt"), "Unknown turns must never be interrupted")
        XCTAssertEqual(store.tasks[0].status, .inProgress)
    }

    func testOwnershipAndConcurrencyStayReservedDuringNativeTurn() async throws {
        let (store, parent, child, directory) = try fixture(mode: "running")
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        store.settings.maximumConcurrentSubagents = 1
        _ = try store.resumeWorker(from: parent.id, workerID: child.id, requestID: UUID(), instructions: "Wait fixture")
        try await wait(store) { $0 == .started }
        var task = store.tasks[0]
        task.status = .blocked
        store.updateTask(task)
        XCTAssertEqual(store.status(of: child.id), .working)
        XCTAssertThrowsError(
            try store.delegateTask(from: parent.id, title: "Another", instructions: "Cannot exceed limit", start: false)
        )
        XCTAssertThrowsError(try store.updateTaskFromAgent(["task_id": task.id, "owner": "none"], caller: child.id))
        XCTAssertThrowsError(
            try store.handoff(
                from: child.id, to: parent, taskID: task.id, title: nil, description: nil, note: "Transfer",
                artifacts: [], verification: "", nextAction: "Continue"))
        store.promoteToMainConversation(child.id)
        store.removeSession(parent.id)
        XCTAssertEqual(store.session(child.id)?.parentSessionID, parent.id)
        XCTAssertNotNil(store.session(parent.id))
        store.cancelWorkerResume(child.id)
        try await wait(store) { !$0.reservesWorker }
    }
}
