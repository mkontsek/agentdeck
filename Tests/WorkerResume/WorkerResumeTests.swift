import AppKit
import XCTest

@MainActor
final class WorkerResumeTests: XCTestCase {
    private func fixture() throws -> (AppStore, ManagedSession, ManagedSession, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        var parent = ManagedSession(name: "Synthetic parent", kind: .cli)
        parent.cliProfileID = "codex"
        parent.workingDirectory = directory.path
        store.addSession(parent, start: false)
        let child = try store.delegateTask(
            from: parent.id, title: "Synthetic continuation", instructions: "First checkpoint", start: false)
        store.runtime[child.id]?.status = .idle
        store.saveResumeCheckpoint(
            SessionResumeCheckpoint(
                profileID: "codex", directory: directory.path, launchedAt: Date(), conversationID: UUID().uuidString),
            for: child.id)
        return (store, parent, child, directory)
    }

    private func cleanup(_ store: AppStore, _ directory: URL) {
        store.shutdown()
        try? FileManager.default.removeItem(at: directory)
    }

    func testOriginalSilentReuseNowRejectsContinuationInstructions() throws {
        let (store, parent, child, directory) = try fixture()
        defer { cleanup(store, directory) }
        let originalPrompt = child.initialPrompt
        XCTAssertThrowsError(
            try store.delegateTask(
                from: parent.id, taskID: child.delegatedTaskID, instructions: "Do next step", start: false)
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("NOT submitted"))
            XCTAssertTrue(error.localizedDescription.contains("resume_worker"))
        }
        let repeated = try store.delegateTask(from: parent.id, taskID: child.delegatedTaskID, start: false)
        XCTAssertEqual(repeated.id, child.id)
        XCTAssertEqual(repeated.initialPrompt, originalPrompt)
        XCTAssertEqual(store.sessions.count, 2)
        store.subagentStopped(child.id, reason: "Fixture early exit")
        let response = store.callTool(
            name: "delegate_task", args: ["task_id": child.delegatedTaskID!], caller: parent.id)
        XCTAssertFalse(response.isError)
        XCTAssertTrue(response.text.contains("\"result_submitted\":false"))
    }

    func testForeignActiveStoppedSubmittedAndUnsupportedRejectWithoutMutation() throws {
        let (store, parent, child, directory) = try fixture()
        defer { cleanup(store, directory) }
        func resume(_ caller: UUID = UUID()) throws {
            _ = try store.resumeWorker(from: caller, workerID: child.id, requestID: UUID(), instructions: "Continue")
        }
        XCTAssertThrowsError(try resume())
        for state in [SessionStatus.working, .starting, .waitingForUser, .stalled, .quotaWarning] {
            store.runtime[child.id]?.status = state
            XCTAssertThrowsError(try resume(parent.id))
        }
        store.runtime[child.id]?.status = .idle
        store.stopSession(child.id)
        XCTAssertThrowsError(try resume(parent.id))
        store.enableWorkerResume(child.id)
        var worker = try XCTUnwrap(store.session(child.id))
        worker.cliProfileID = "claude"
        store.updateSession(worker)
        XCTAssertThrowsError(try resume(parent.id))
        worker.cliProfileID = "codex"
        store.updateSession(worker)
        try store.reportSubagentResult(caller: child.id, summary: "Final submitted result", blocked: false)
        XCTAssertThrowsError(try resume(parent.id))
        XCTAssertEqual(store.tasks.first?.status, .awaitingApproval)
        XCTAssertTrue(store.workerResumes.requests.isEmpty)
    }

    func testDuplicateAndConcurrentRequestsHaveOneDurableIdentity() async throws {
        let (store, parent, child, directory) = try fixture()
        defer { cleanup(store, directory) }
        store.workerResumeTransport = WorkerResumeTransport(executable: "/nonexistent-agentdeck-fixture")
        let id = UUID()
        let first = try store.resumeWorker(
            from: parent.id, workerID: child.id, requestID: id, instructions: "λ 🧑🏽‍💻 $(touch /tmp/NEVER97)")
        let retry = try store.resumeWorker(
            from: parent.id, workerID: child.id, requestID: id, instructions: first.instructions)
        XCTAssertEqual(first, retry)
        XCTAssertEqual(first.phase, .checking)
        XCTAssertThrowsError(
            try store.resumeWorker(from: parent.id, workerID: child.id, requestID: UUID(), instructions: "Concurrent"))
        XCTAssertThrowsError(
            try store.resumeWorker(from: parent.id, workerID: child.id, requestID: id, instructions: "Changed payload"))
        for _ in 0..<100 where store.workerResumes.requests.first?.phase == .checking {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(store.workerResumes.requests.count, 1)
        XCTAssertEqual(store.workerResumes.requests.first?.phase, .failed)
        XCTAssertEqual(store.tasks.first?.ownerSessionID, child.id)
        XCTAssertEqual(store.tasks.first?.status, .inProgress)
        XCTAssertFalse(FileManager.default.fileExists(atPath: "/tmp/NEVER97"))
    }

    func testCheckpointNeverMasqueradesAsCompletionAndKeepsApproval() throws {
        let (store, parent, child, directory) = try fixture()
        defer { cleanup(store, directory) }
        store.subagentStopped(child.id, reason: "Synthetic checkpoint exit")
        try store.reportSubagentProgress(caller: child.id, summary: "Part one saved; part two remains")
        XCTAssertEqual(store.tasks.first?.status, .inProgress)
        XCTAssertEqual(store.session(child.id)?.subagentCompleted, false)
        XCTAssertEqual(store.tasks.first?.requiresApproval, true)
        XCTAssertTrue(store.tasks.first?.notes.contains("checkpoint — unfinished") == true)
        let published = try XCTUnwrap(store.tasks.first)
        XCTAssertTrue(
            store.inbox.events.contains {
                $0.targetID == parent.id && $0.key == "task:\(published.id):revision:\(published.revision)"
            })
        try store.reportSubagentResult(caller: child.id, summary: "All work verified", blocked: false)
        XCTAssertEqual(store.tasks.first?.status, .awaitingApproval)
    }

    func testJournalRestartPreservesIdentityAndNeverReplaysAmbiguousRequest() throws {
        let (store, parent, child, directory) = try fixture()
        defer { cleanup(store, directory) }
        let request = WorkerResumeRequest(
            id: UUID(), workerID: child.id, parentID: parent.id, taskID: child.delegatedTaskID!, taskRevision: 1,
            generation: 0, conversationID: UUID().uuidString, directory: directory.path,
            instructions: "Only explicit next step", phase: .submitting)
        try store.workerResumes.put(request)
        store.saveNow()
        let restored = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer { restored.shutdown() }
        XCTAssertEqual(restored.workerResumes.requests.first?.id, request.id)
        XCTAssertEqual(restored.workerResumes.requests.first?.phase, .uncertain)
        XCTAssertTrue(restored.workerResumeJobs.isEmpty)
        XCTAssertThrowsError(
            try restored.resumeWorker(
                from: parent.id, workerID: child.id, requestID: UUID(), instructions: "Unsafe replay"))
        restored.startSession(child.id)
        XCTAssertFalse(restored.terminals.isRunning(child.id))
    }

    func testStaleCallbackCannotChangeReassignedTask() throws {
        let (store, parent, child, directory) = try fixture()
        defer { cleanup(store, directory) }
        let request = WorkerResumeRequest(
            id: UUID(), workerID: child.id, parentID: parent.id, taskID: child.delegatedTaskID!,
            taskRevision: store.tasks[0].revision, generation: store.runtime[child.id]!.generation,
            conversationID: UUID().uuidString, directory: directory.path, instructions: "Continue")
        try store.workerResumes.put(request)
        var task = store.tasks[0]
        task.ownerSessionID = parent.id
        task.status = .blocked
        store.tasks[0] = task  // Simulate stale external restoration, bypassing normal transfer guards.
        XCTAssertFalse(store.prepareWorkerResume(request))
        _ = store.recordWorkerResume(request, phase: .started, turnID: "stale-turn", detail: "Late receipt")
        XCTAssertEqual(store.tasks[0].status, .blocked)
        XCTAssertEqual(store.tasks[0].ownerSessionID, parent.id)
    }

    func testCorruptAndUnwritableJournalFailClosed() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("journal.json")
        let corrupt = Data("broken".utf8)
        try corrupt.write(to: url)
        let journal = WorkerResumeJournal(url: url)
        XCTAssertNotNil(journal.error)
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }

    func testLateStartedReceiptCannotUndoFinalResultApproval() throws {
        let (store, parent, child, directory) = try fixture()
        defer { cleanup(store, directory) }
        let request = WorkerResumeRequest(
            id: UUID(), workerID: child.id, parentID: parent.id,
            taskID: child.delegatedTaskID!, taskRevision: store.tasks[0].revision,
            generation: store.runtime[child.id]!.generation,
            conversationID: store.resumeCheckpoints[child.id]!.conversationID!, directory: directory.path,
            instructions: "Fast provider", phase: .queued)
        try store.workerResumes.put(request)
        try store.reportSubagentResult(caller: child.id, summary: "Finished before callback", blocked: false)
        let revision = store.tasks[0].revision
        XCTAssertTrue(
            store.recordWorkerResume(request, phase: .started, turnID: "fast-turn", detail: "Delayed start receipt"))
        XCTAssertEqual(store.tasks[0].status, .awaitingApproval)
        XCTAssertEqual(store.tasks[0].revision, revision)
        XCTAssertEqual(store.session(child.id)?.subagentCompleted, true)
    }

    func testPreflightRechecksChangedConfigurationAndActivity() throws {
        for mutation in ["profile", "directory", "checkpoint", "disabled", "active"] {
            let (store, parent, child, directory) = try fixture()
            defer { cleanup(store, directory) }
            let request = WorkerResumeRequest(
                id: UUID(), workerID: child.id, parentID: parent.id,
                taskID: child.delegatedTaskID!, taskRevision: store.tasks[0].revision,
                generation: store.runtime[child.id]!.generation,
                conversationID: store.resumeCheckpoints[child.id]!.conversationID!, directory: directory.path,
                instructions: "Pending configuration check")
            try store.workerResumes.put(request)
            let index = try XCTUnwrap(store.sessions.firstIndex { $0.id == child.id })
            switch mutation {
            case "profile": store.sessions[index].cliProfileID = "claude"
            case "directory": store.sessions[index].workingDirectory = "/different-fixture"
            case "checkpoint": store.resumeCheckpoints[child.id]?.conversationID = UUID().uuidString
            case "disabled": store.settings.automaticSubagents = false
            default: store.runtime[child.id]?.status = .working
            }
            XCTAssertFalse(store.prepareWorkerResume(request), mutation)
            XCTAssertEqual(store.workerResumes.requests[0].phase, .checking)
        }
    }

    func testDuplicateAndOversizedJournalsArePreservedAndRejected() throws {
        let (store, parent, child, directory) = try fixture()
        defer { cleanup(store, directory) }
        let request = WorkerResumeRequest(
            id: UUID(), workerID: child.id, parentID: parent.id,
            taskID: child.delegatedTaskID!, taskRevision: 1, generation: 0,
            conversationID: UUID().uuidString, directory: directory.path, instructions: "Fixture")
        let url = directory.appendingPathComponent("invalid-resumes.json")
        let duplicate = try JSONEncoder().encode([request, request])
        try duplicate.write(to: url)
        let journal = WorkerResumeJournal(url: url)
        XCTAssertNotNil(journal.error)
        XCTAssertTrue(journal.requests.isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), duplicate)
        let oversized = Data(repeating: 32, count: 8_388_609)
        try oversized.write(to: url)
        XCTAssertNotNil(WorkerResumeJournal(url: url).error)
        XCTAssertEqual(try Data(contentsOf: url).count, oversized.count)
    }
}
