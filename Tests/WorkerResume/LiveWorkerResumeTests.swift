import AppKit
import XCTest

@MainActor
private final class ResumeProbeState {
    var threadID: String?
    var firstCompleted = false
    var secondCompleted = false
    var answers: [String] = []
    var error: String?
}

final class LiveWorkerResumeTests: XCTestCase {
    @MainActor
    func testNativeContinuationPerformsNextStepAndPreservesRealCodexDraft() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["AGENTDECK_LIVE_RESUME"] == "1")
        let executable = try XCTUnwrap(CodexResumeConnection.executable)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("resume97-" + UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let socket = directory.appendingPathComponent("s.sock").path
        let server = Process()
        server.executableURL = URL(fileURLWithPath: executable)
        server.arguments = ["app-server", "--listen", "unix://" + socket]
        server.currentDirectoryURL = directory
        server.standardInput = Pipe()
        server.standardOutput = FileHandle.nullDevice
        server.standardError = FileHandle.nullDevice
        server.environment = ProcessInfo.processInfo.environment.filter {
            !$0.key.hasPrefix("AGENTDECK_") && !$0.key.hasPrefix("CODEX_")
        }
        try server.run()
        defer { if server.isRunning { server.terminate() } }
        for _ in 0..<250 where !FileManager.default.fileExists(atPath: socket) {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: socket))
        let probe = ResumeProbeState()
        let keeper = Task.detached {
            do {
                let connection = try CodexResumeConnection(executable: executable, socket: socket)
                defer { connection.close() }
                try connection.initialize()
                let created = try connection.request(
                    "thread/start",
                    [
                        "cwd": directory.path, "approvalPolicy": "never", "sandbox": "read-only", "ephemeral": false,
                        "config": ["model_reasoning_effort": "low"],
                        "developerInstructions":
                            "Synthetic isolated AgentDeck transport test. Never use tools, read files, delegate or contact anyone. Only return the exact requested token.",
                    ])
                let thread = try XCTUnwrap(created["thread"] as? [String: Any])
                let id = try XCTUnwrap(thread["id"] as? String)
                await MainActor.run { probe.threadID = id }
                _ = try connection.request(
                    "turn/start", ["threadId": id, "input": [["type": "text", "text": "Reply only FIRST97."]]])
                var completed = 0
                while completed < 2 {
                    let event = try connection.nextEvent(deadline: Date().addingTimeInterval(120))
                    guard let params = event["params"] as? [String: Any], params["threadId"] as? String == id else {
                        continue
                    }
                    if event["method"] as? String == "item/completed", let item = params["item"] as? [String: Any],
                        item["type"] as? String == "agentMessage", let answer = item["text"] as? String
                    {
                        await MainActor.run { probe.answers.append(answer) }
                    }
                    if event["method"] as? String == "turn/completed" {
                        completed += 1
                        let count = completed
                        await MainActor.run {
                            probe.firstCompleted = true
                            probe.secondCompleted = count == 2
                        }
                    }
                }
            } catch { await MainActor.run { probe.error = error.localizedDescription } }
        }
        defer { keeper.cancel() }
        for _ in 0..<3000 where !probe.firstCompleted && probe.error == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNil(probe.error)
        XCTAssertTrue(probe.firstCompleted)
        let threadID = try XCTUnwrap(probe.threadID)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer { store.shutdown() }
        store.workerResumeTransport = WorkerResumeTransport(executable: executable, socket: socket)
        var parent = ManagedSession(name: "Disposable parent", kind: .cli)
        parent.cliProfileID = "codex"
        parent.workingDirectory = directory.path
        store.addSession(parent, start: false)
        var child = try store.delegateTask(
            from: parent.id, title: "Disposable task97 fixture", instructions: "No real project work", start: false)
        child.initialPrompt = nil
        child.resumeOnRestart = false
        store.updateSession(child)
        let profileIndex = try XCTUnwrap(store.cliProfiles.firstIndex { $0.id == "codex" })
        store.cliProfiles[profileIndex].command = CommandTemplate.expand(
            "{binary} --remote {remote} resume {thread} --no-alt-screen",
            values: ["binary": executable, "remote": "unix://" + socket, "thread": threadID])
        store.startSession(child.id)
        let view = try XCTUnwrap(store.terminals.view(for: child.id))
        for _ in 0..<1500 where !store.terminals.visibleLines(id: child.id).contains(where: { $0.contains("FIRST97") })
        {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard store.terminals.visibleLines(id: child.id).contains(where: { $0.contains("FIRST97") }) else {
            XCTFail(
                "Disposable TUI did not attach; no draft input sent. Screen: \(store.terminals.visibleLines(id: child.id))"
            )
            return
        }
        view.pasteText("DRAFT97_žltý🧑🏽‍💻_abcΩxyz")
        try await Task.sleep(for: .milliseconds(250))
        view.send(txt: "\u{1b}[D\u{1b}[D\u{1b}[D")
        try await Task.sleep(for: .milliseconds(200))
        view.setMarkedText(
            "仮", selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        let marked = view.markedRange()
        let nativeIdentity = ObjectIdentifier(view)
        let focused = store.focusedSessionID
        store.saveResumeCheckpoint(
            SessionResumeCheckpoint(
                profileID: "codex", directory: directory.path, launchedAt: Date(), conversationID: threadID),
            for: child.id)
        store.runtime[child.id]?.status = .idle
        let request = try store.resumeWorker(
            from: parent.id, workerID: child.id, requestID: UUID(),
            instructions: "Next step: reply only CONTINUED97. Never use tools.")
        XCTAssertEqual(request.phase, .checking)
        for _ in 0..<3000 where !probe.secondCompleted && probe.error == nil {
            if let receipt = store.workerResumes.requests.first, receipt.phase == .failed || receipt.phase == .uncertain
            {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        for _ in 0..<100 where store.workerResumes.requests.first?.phase == .started {
            try await Task.sleep(for: .milliseconds(20))
        }
        let receipt = try XCTUnwrap(store.workerResumes.requests.first)
        print("LIVE_RESUME97 phase=\(receipt.phase.rawValue) detail=\(receipt.detail) answers=\(probe.answers)")
        XCTAssertEqual(receipt.phase, .ended)
        XCTAssertNotNil(receipt.turnID)
        XCTAssertNotNil(receipt.queuedSubmissionID)
        XCTAssertTrue(probe.answers.contains { $0.contains("CONTINUED97") })
        XCTAssertEqual(ObjectIdentifier(try XCTUnwrap(store.terminals.view(for: child.id))), nativeIdentity)
        XCTAssertEqual(store.focusedSessionID, focused)
        XCTAssertTrue(view.hasMarkedText())
        XCTAssertEqual(view.markedRange(), marked)
        view.unmarkText()
        view.insertText("§", replacementRange: NSRange(location: NSNotFound, length: 0))
        try await Task.sleep(for: .milliseconds(300))
        let screen = store.terminals.visibleLines(id: child.id).joined(separator: "\n")
        XCTAssertTrue(screen.contains("DRAFT97_žltý"), "Unicode draft prefix changed")
        XCTAssertTrue(
            screen.contains("abcΩ§xyz"), "Native continuation moved/cleared the logical draft caret: \(screen)")
        XCTAssertEqual(store.tasks.first?.status, .inProgress)
        XCTAssertEqual(store.tasks.first?.ownerSessionID, child.id)
        XCTAssertFalse(store.session(child.id)?.subagentCompleted == true)
        // Never submit the synthetic draft. Only disposable processes are terminated.
    }
}
