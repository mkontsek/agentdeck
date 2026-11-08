import XCTest

final class SubagentPromotionTests: XCTestCase {
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
    func testLegacyOrphanRecoveryForCodexAndClaudePreservesEvidenceAndResume() throws {
        for profileID in ["codex", "claude"] {
            for missingParent in [nil, UUID()] {
                try withStore { store, parent, directory in
                    var child = try store.delegateTask(
                        from: parent.id, title: "Original task", instructions: "Original scope",
                        profileID: profileID, start: false)
                    try store.reportSubagentResult(caller: child.id, summary: "Verified evidence", blocked: false)
                    let task = try XCTUnwrap(store.tasks.first)
                    child = try XCTUnwrap(store.session(child.id))
                    child.parentSessionID = missingParent
                    store.updateSession(child)
                    let conversationID = UUID().uuidString
                    let transcript = directory.appendingPathComponent("\(conversationID).jsonl")
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try Data().write(to: transcript)
                    let checkpoint = SessionResumeCheckpoint(
                        profileID: profileID, directory: child.effectiveDirectory, launchedAt: Date(),
                        conversationID: conversationID, conversationPath: transcript.path)
                    try ResumeCheckpointStorage.write(checkpoint, id: child.id, directory: store.resumeDirectory)
                    store.saveNow()

                    let restored = AppStore(stateURL: directory.appendingPathComponent("state.json"))
                    defer { restored.shutdown() }
                    let promoted = try XCTUnwrap(restored.session(child.id))
                    XCTAssertNil(promoted.parentSessionID)
                    XCTAssertNil(promoted.delegatedTaskID)
                    XCTAssertNil(promoted.initialPrompt)
                    XCTAssertFalse(promoted.subagentCompleted)
                    XCTAssertEqual(promoted.cliProfileID, profileID)
                    XCTAssertEqual(promoted.effectiveDirectory, child.effectiveDirectory)
                    XCTAssertEqual(restored.resumeCheckpoints[child.id], checkpoint)
                    XCTAssertEqual(restored.tasks.first?.notes, task.notes)
                    XCTAssertEqual(restored.tasks.first?.status, task.status)
                    XCTAssertEqual(restored.tasks.first?.ownerSessionID, child.id)
                    XCTAssertEqual(restored.tasks.first?.requiresApproval, task.requiresApproval)
                    XCTAssertTrue(restored.canDelegate(from: child.id))
                    let briefing = try String(contentsOfFile: restored.briefingPath(for: child.id), encoding: .utf8)
                    XCTAssertTrue(briefing.contains("You are the main conversation"))
                    XCTAssertFalse(briefing.contains("Do not delegate or recruit"))
                    let command = restored.launchCommand(for: promoted, resume: true)
                    XCTAssertTrue(command.contains(conversationID))
                    XCTAssertFalse(command.contains("You are a task subagent"))
                    if profileID == "codex" { XCTAssertTrue(command.contains("You are the main conversation")) }
                    restored.saveNow()
                    let again = AppStore(stateURL: directory.appendingPathComponent("state.json"))
                    defer { again.shutdown() }
                    XCTAssertNil(again.session(child.id)?.delegatedTaskID)
                    XCTAssertTrue(again.canDelegate(from: child.id))
                }
            }
        }
    }

    @MainActor
    func testPromotionKeepsRunningProcessAndFreesWorkerSlotWithoutApprovingTask() throws {
        try withStore { store, parent, _ in
            let profile = CLIProfile(
                id: "promotion-fixture", name: "Fixture", command: "exec /bin/cat", supportsMCP: true)
            store.cliProfiles.append(profile)
            store.settings.maximumConcurrentSubagents = 1
            let child = try store.delegateTask(
                from: parent.id, title: "Keep running", instructions: "Fixture only", profileID: profile.id)
            store.selectTab(child.id)
            store.maximizedSessionID = parent.id
            let task = try XCTUnwrap(store.tasks.first)
            let generation = store.runtime[child.id]?.generation
            store.promoteToMainConversation(child.id)
            XCTAssertTrue(store.terminals.isRunning(child.id))
            XCTAssertEqual(store.runtime[child.id]?.generation, generation)
            XCTAssertTrue(store.runtime[child.id]?.programMessage?.contains("Restart this session") == true)
            XCTAssertEqual(store.focusedSessionID, child.id)
            XCTAssertEqual(store.selectedPaneTabs[child.paneID], child.id)
            XCTAssertEqual(store.maximizedSessionID, child.id)
            XCTAssertFalse(store.paneConnections.contains { $0.target.id == child.id })
            XCTAssertEqual(store.tasks.first?.status, task.status)
            XCTAssertEqual(store.tasks.first?.ownerSessionID, child.id)
            XCTAssertEqual(store.tasks.first?.notes, task.notes)
            let tools = store.toolDefinitions(caller: child.id).compactMap { $0["name"] as? String }
            XCTAssertTrue(tools.contains("delegate_task"))
            XCTAssertFalse(tools.contains("report_subagent_result"))
            XCTAssertNoThrow(
                try store.delegateTask(from: parent.id, title: "Next", instructions: "New worker", start: false))
            store.subagentStopped(child.id, reason: "main conversation exits")
            XCTAssertEqual(store.tasks.first?.status, task.status)
            let logCount = store.log.count
            store.promoteToMainConversation(child.id)
            XCTAssertEqual(store.log.count, logCount, "Repeated promotion must be a no-op")
        }
    }

    @MainActor
    func testLiveWorkersRemainRestrictedAndPromotionRespectsDisabledDelegation() throws {
        try withStore { store, parent, directory in
            let child = try store.delegateTask(from: parent.id, title: "Worker", instructions: "Work", start: false)
            store.saveNow()
            let restored = AppStore(stateURL: directory.appendingPathComponent("state.json"))
            defer { restored.shutdown() }
            XCTAssertEqual(restored.session(child.id)?.delegatedTaskID, child.delegatedTaskID)
            XCTAssertFalse(restored.canDelegate(from: child.id))
            XCTAssertTrue(
                restored.briefing(for: try XCTUnwrap(restored.session(child.id))).contains("You are a task subagent"))
            restored.settings.automaticSubagents = false
            restored.promoteToMainConversation(child.id)
            XCTAssertFalse(restored.canDelegate(from: child.id))
            XCTAssertFalse(
                restored.toolDefinitions(caller: child.id).contains { $0["name"] as? String == "delegate_task" })
            XCTAssertThrowsError(
                try restored.delegateTask(from: child.id, title: "Disabled", instructions: "No", start: false))
            XCTAssertTrue(
                restored.briefing(for: try XCTUnwrap(restored.session(child.id))).contains(
                    "You are the main conversation"))
        }
    }
}
