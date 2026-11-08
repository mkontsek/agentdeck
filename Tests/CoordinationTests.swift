import XCTest

final class CoordinationTests: XCTestCase {
    @MainActor
    private func withStore(_ body: (AppStore, URL, ManagedSession, ManagedSession) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("state.json")
        let store = AppStore(stateURL: url)
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        var first = ManagedSession(name: "Implementer", kind: .cli)
        first.cliProfileID = "codex"
        var second = ManagedSession(name: "Reviewer", kind: .cli)
        second.cliProfileID = "claude"
        first = store.addSession(first, start: false)
        second = store.addSession(second, start: false)
        try body(store, url, first, second)
    }

    @MainActor
    func testApprovalAcceptanceAndCompletionCannotBeBypassed() throws {
        try withStore { store, _, sender, recipient in
            let task = store.createTask(
                title: "Fix login", description: "Preserve sessions", owner: sender.id, creatorID: sender.id)
            let handoff = try store.handoff(
                from: sender.id, to: recipient, taskID: task.id, title: nil, description: nil,
                note: "Fixed", artifacts: ["Sources/Auth.swift"], verification: "Auth tests pass",
                nextAction: "Review the diff"
            ).handoff
            XCTAssertEqual(handoff.status, .awaitingApproval)
            XCTAssertTrue(
                store.callTool(name: "read_handoffs", args: ["handoff_id": handoff.id.uuidString], caller: recipient.id)
                    .isError)
            XCTAssertEqual(store.tasks.first?.ownerSessionID, sender.id)
            XCTAssertThrowsError(try store.acceptHandoff(handoff.id, caller: recipient.id, accept: true))
            XCTAssertThrowsError(
                try store.updateTaskFromAgent(["task_id": task.id, "owner": "me"], caller: recipient.id))
            store.approveHandoff(handoff.id)
            XCTAssertFalse(
                store.callTool(name: "read_handoffs", args: ["handoff_id": handoff.id.uuidString], caller: recipient.id)
                    .isError)
            XCTAssertEqual(store.handoffs.first?.status, .delivered)
            XCTAssertEqual(store.tasks.first?.ownerSessionID, sender.id)
            try store.acceptHandoff(handoff.id, caller: recipient.id, accept: true)
            try store.acceptHandoff(handoff.id, caller: recipient.id, accept: true)
            XCTAssertEqual(store.tasks.first?.ownerSessionID, recipient.id)
            XCTAssertEqual(store.handoffs.first?.status, .accepted)
            let completed = try store.updateTaskFromAgent(["task_id": task.id, "status": "done"], caller: recipient.id)
            XCTAssertEqual(completed.status, .awaitingApproval)
            var approved = completed
            approved.status = .done
            store.updateTask(approved)
            XCTAssertEqual(store.tasks.first?.status, .done)
            XCTAssertTrue(store.tasks.first?.events.last?.message.contains("Done") == true)
        }
    }

    @MainActor
    func testPersistentPackagesRecoverWithoutAssumingDelivery() throws {
        try withStore { store, url, sender, recipient in
            let task = store.createTask(title: "Review", owner: sender.id, notes: "Published finding")
            let transfer = try store.handoff(
                from: nil, to: recipient, taskID: task.id, title: nil, description: nil, note: "Summary"
            ).handoff
            store.transitionHandoff(transfer.id, to: .delivering, detail: "in flight", actor: "app")
            store.saveNow()
            let restored = AppStore(stateURL: url)
            defer { restored.shutdown() }
            XCTAssertEqual(restored.handoffs.first?.status, .failed)
            XCTAssertEqual(restored.handoffs.first?.context.sharedNotes, "Published finding")
            XCTAssertEqual(restored.tasks.first?.ownerSessionID, sender.id)
            restored.retryHandoff(transfer.id)
            XCTAssertEqual(restored.handoffs.first?.status, .delivered)
            try restored.acceptHandoff(transfer.id, caller: recipient.id, accept: true)
            XCTAssertEqual(restored.tasks.first?.ownerSessionID, recipient.id)
        }
    }

    @MainActor
    func testStaleContextDeclineAndDuplicateHandoffs() throws {
        try withStore { store, _, sender, recipient in
            var task = store.createTask(title: "Review", owner: sender.id)
            let transfer = try store.handoff(
                from: nil, to: recipient, taskID: task.id, title: nil, description: nil, note: nil
            ).handoff
            XCTAssertThrowsError(
                try store.handoff(from: nil, to: recipient, taskID: task.id, title: nil, description: nil, note: nil))
            task.notes = "New evidence"
            store.updateTask(task)
            XCTAssertThrowsError(try store.acceptHandoff(transfer.id, caller: recipient.id, accept: true))
            try store.acceptHandoff(transfer.id, caller: recipient.id, accept: false, reason: "Need refreshed evidence")
            XCTAssertEqual(store.tasks.first?.ownerSessionID, sender.id)
            XCTAssertEqual(store.handoffs.first?.status, .declined)
        }
    }

    @MainActor
    func testDependenciesAndOwnershipGuards() throws {
        try withStore { store, _, sender, recipient in
            var prerequisite = store.createTask(title: "Build", owner: sender.id)
            var review = store.createTask(title: "Review", owner: recipient.id)
            review.dependencies = [prerequisite.id]
            store.updateTask(review)
            XCTAssertThrowsError(try store.validateDependencies([review.id], for: prerequisite.id))
            XCTAssertThrowsError(try store.validateDependencies([999], for: review.id))
            XCTAssertThrowsError(
                try store.updateTaskFromAgent(["task_id": review.id, "status": "in-progress"], caller: recipient.id))
            XCTAssertThrowsError(
                try store.updateTaskFromAgent(["task_id": review.id, "notes": "overwrite"], caller: sender.id))
            prerequisite.status = .done
            store.updateTask(prerequisite)
            XCTAssertNoThrow(
                try store.updateTaskFromAgent(["task_id": review.id, "status": "in-progress"], caller: recipient.id))
            store.deleteTask(prerequisite.id)
            XCTAssertTrue(store.tasks.contains { $0.id == prerequisite.id })
            XCTAssertNotNil(store.lastError)
        }
    }

    func testLegacyTaskPreservesCompletionContract() throws {
        let task = try JSONDecoder().decode(
            BoardTask.self, from: Data(#"{"id":1,"title":"Legacy","status":"done"}"#.utf8))
        XCTAssertEqual(task.status, .done)
        XCTAssertFalse(task.requiresApproval)
        XCTAssertTrue(task.dependencies.isEmpty)
        XCTAssertTrue(BoardTask(id: 2, title: "New").requiresApproval)
    }
}
