import XCTest

final class SubagentSessionTests: XCTestCase {
    @MainActor
    private func withStore(_ body: (AppStore, ManagedSession, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        var parent = ManagedSession(name: "Main", kind: .cli)
        parent.cliProfileID = "codex"
        parent.workingDirectory = directory.path
        store.addSession(parent, start: false)
        try body(store, parent, directory)
    }

    @MainActor
    func testMCPRoutesDelegationAndResultsThroughManagedWorkers() throws {
        try withStore { store, parent, _ in
            let profile = CLIProfile(
                id: "mcp-worker-fixture", name: "Fixture", command: "exec /bin/cat", supportsMCP: true)
            store.cliProfiles.append(profile)
            let response = store.callTool(
                name: "delegate_task",
                args: [
                    "title": "Fixture task", "instructions": "No real provider call", "cli_profile": profile.id,
                ], caller: parent.id)
            XCTAssertFalse(response.isError)
            let child = try XCTUnwrap(store.sessions.first { $0.parentSessionID == parent.id })
            XCTAssertTrue(store.terminals.isRunning(child.id))
            XCTAssertEqual(store.focusedSessionID, parent.id)
            XCTAssertTrue(
                store.callTool(name: "report_subagent_result", args: ["summary": "Wrong caller"], caller: parent.id)
                    .isError)
            XCTAssertFalse(
                store.callTool(
                    name: "report_subagent_result", args: ["summary": "Verified fixture result"], caller: child.id
                ).isError)
            XCTAssertEqual(store.tasks.first?.status, .awaitingApproval)
            XCTAssertTrue(
                store.callTool(
                    name: "delegate_task", args: ["title": "Recursion", "instructions": "No"], caller: child.id
                ).isError)
        }
    }

    @MainActor
    func testDelegationIsFreshIdempotentAndDoesNotTakeFocus() throws {
        try withStore { store, parent, _ in
            let child = try store.delegateTask(
                from: parent.id, title: "Implement feature", instructions: "Only change Sources/Feature.swift",
                start: false)
            XCTAssertEqual(store.focusedSessionID, parent.id)
            XCTAssertEqual(store.panes.count, 2)
            XCTAssertEqual(child.parentSessionID, parent.id)
            XCTAssertNotEqual(child.paneID, parent.paneID)
            XCTAssertFalse(child.resumeLastConversation)
            XCTAssertFalse(child.isOrchestrator)
            XCTAssertTrue(child.resumeOnRestart)
            XCTAssertEqual(child.effectiveDirectory, parent.effectiveDirectory)
            XCTAssertEqual(store.tasks.first?.ownerSessionID, child.id)
            XCTAssertTrue(child.initialPrompt?.contains("Only change Sources/Feature.swift") == true)
            XCTAssertTrue(store.briefing(for: parent).contains("promptly end your turn"))
            let again = try store.delegateTask(from: parent.id, taskID: child.delegatedTaskID, start: false)
            XCTAssertEqual(again.id, child.id)
            XCTAssertEqual(store.tasks.count, 1)
            XCTAssertFalse(store.canDelegate(from: child.id))
            XCTAssertThrowsError(
                try store.delegateTask(from: child.id, title: "Recursive", instructions: "No", start: false))
            XCTAssertEqual(
                store.toolDefinitions(caller: child.id).filter { $0["name"] as? String == "delegate_task" }.count, 0)
        }
    }

    @MainActor
    func testWorkerSelectionPersistsInIndependentPane() throws {
        try withStore { store, parent, directory in
            let child = try store.delegateTask(
                from: parent.id, title: "Review", instructions: "Read only", start: false)
            store.selectTab(child.id)
            XCTAssertEqual(store.pane(containing: parent.id)?.activeSession.id, parent.id)
            XCTAssertEqual(store.pane(containing: child.id)?.activeSession.id, child.id)
            store.saveNow()
            let restored = AppStore(stateURL: directory.appendingPathComponent("state.json"))
            defer { restored.shutdown() }
            XCTAssertEqual(restored.focusedSessionID, child.id)
            XCTAssertEqual(restored.pane(containing: child.id)?.id, child.paneID)
            XCTAssertNotEqual(child.paneID, parent.paneID)
        }
    }

    @MainActor
    func testResultsKeepApprovalAndReleaseConcurrencySlot() throws {
        try withStore { store, parent, _ in
            store.settings.maximumConcurrentSubagents = 1
            let child = try store.delegateTask(from: parent.id, title: "Fix", instructions: "Small fix", start: false)
            XCTAssertThrowsError(
                try store.delegateTask(from: parent.id, title: "Second", instructions: "Wait", start: false))
            XCTAssertEqual(store.tasks.count, 1)
            XCTAssertThrowsError(
                try store.reportSubagentResult(caller: parent.id, summary: "Wrong caller", blocked: false))
            try store.reportSubagentResult(caller: child.id, summary: "Changed A; 2 tests pass", blocked: false)
            XCTAssertEqual(store.tasks.first?.status, .awaitingApproval)
            XCTAssertTrue(store.session(child.id)?.subagentCompleted == true)
            let revision = store.tasks.first?.revision
            try store.reportSubagentResult(caller: child.id, summary: "Duplicate", blocked: false)
            XCTAssertEqual(store.tasks.first?.revision, revision)
            XCTAssertNoThrow(
                try store.delegateTask(from: parent.id, title: "Second", instructions: "Next task", start: false))
            store.settings.automaticSubagents = false
            XCTAssertThrowsError(
                try store.delegateTask(from: parent.id, title: "Disabled", instructions: "No", start: false))
        }
    }

    @MainActor
    func testDelegationCannotBypassOwnershipHandoffsOrDependencies() throws {
        try withStore { store, parent, _ in
            var other = ManagedSession(name: "Other", kind: .cli)
            other.cliProfileID = "claude"
            store.addSession(other, start: false)
            let owned = store.createTask(title: "Other's task", owner: other.id)
            XCTAssertThrowsError(try store.delegateTask(from: parent.id, taskID: owned.id, start: false))
            let pending = store.createTask(title: "Pending handoff", owner: parent.id)
            _ = try store.handoff(
                from: parent.id, to: other, taskID: pending.id, title: nil, description: nil,
                note: "Transfer", artifacts: [], verification: "", nextAction: "Wait")
            XCTAssertThrowsError(try store.delegateTask(from: parent.id, taskID: pending.id, start: false))
            var dependent = store.createTask(title: "Blocked", owner: parent.id)
            dependent.dependencies = [owned.id]
            store.updateTask(dependent)
            XCTAssertThrowsError(try store.delegateTask(from: parent.id, taskID: dependent.id, start: false))
            XCTAssertEqual(store.sessions.count, 2)
        }
    }

    @MainActor
    func testStoppedWorkerReleasesSlotWithoutChangingSubmittedEvidence() throws {
        try withStore { store, parent, _ in
            store.settings.maximumConcurrentSubagents = 1
            let child = try store.delegateTask(
                from: parent.id, title: "Fix", instructions: "Fix one file", start: false)
            store.subagentStopped(child.id, reason: "process exited (code 1)")
            XCTAssertEqual(store.tasks.first?.status, .blocked)
            XCTAssertTrue(store.tasks.first?.notes.contains("code 1") == true)
            XCTAssertTrue(store.session(child.id)?.subagentCompleted == true)
            let next = try store.delegateTask(from: parent.id, title: "Next", instructions: "Continue", start: false)
            try store.reportSubagentResult(caller: next.id, summary: "Done and verified", blocked: false)
            store.subagentStopped(next.id, reason: "normal exit")
            let submitted = store.tasks.first { $0.id == next.delegatedTaskID }
            XCTAssertEqual(submitted?.status, .awaitingApproval)
            XCTAssertFalse(submitted?.notes.contains("normal exit") == true)
            let closing = try store.delegateTask(
                from: parent.id, title: "Close", instructions: "Unfinished", start: false)
            store.removeSession(closing.id)
            let closedTask = store.tasks.first { $0.id == closing.delegatedTaskID }
            XCTAssertEqual(closedTask?.status, .blocked)
            XCTAssertNil(closedTask?.ownerSessionID)
        }
    }

    @MainActor
    func testTabCyclingStaysInItsWindowAndMaximizeFollowsWorkerFocus() throws {
        try withStore { store, parent, _ in
            let second = try XCTUnwrap(store.addCLITab(to: parent.id, start: false))
            let child = try store.delegateTask(from: parent.id, title: "Worker", instructions: "Review", start: false)
            store.selectTab(child.id)
            store.selectAdjacentTab(1)
            XCTAssertEqual(store.focusedSessionID, child.id)
            store.selectTab(parent.id)
            store.selectAdjacentTab(1)
            XCTAssertEqual(store.focusedSessionID, second.id)
            store.selectAdjacentTab(-1)
            XCTAssertEqual(store.focusedSessionID, parent.id)
            store.maximizedSessionID = parent.id
            store.selectTab(child.id)
            XCTAssertEqual(store.maximizedSessionID, child.id)
        }
    }

    @MainActor
    func testClosingParentPromotesWorkerAndPreservesTask() throws {
        try withStore { store, parent, _ in
            let child = try store.delegateTask(from: parent.id, title: "Worker", instructions: "Finish", start: false)
            store.selectTab(child.id)
            let task = try XCTUnwrap(store.tasks.first)
            store.removeSession(parent.id)
            let promoted = try XCTUnwrap(store.session(child.id))
            XCTAssertNil(promoted.parentSessionID)
            XCTAssertNil(promoted.delegatedTaskID)
            XCTAssertNil(promoted.initialPrompt)
            XCTAssertTrue(store.canDelegate(from: child.id))
            XCTAssertEqual(store.tasks.first?.id, task.id)
            XCTAssertEqual(store.tasks.first?.ownerSessionID, child.id)
            XCTAssertEqual(store.tasks.first?.status, task.status)
            XCTAssertFalse(store.briefing(for: promoted).contains("You are a task subagent"))
            XCTAssertTrue(store.toolDefinitions(caller: child.id).contains { $0["name"] as? String == "delegate_task" })
            XCTAssertNoThrow(
                try store.delegateTask(from: child.id, title: "New work", instructions: "Continue", start: false))
        }
    }
}
