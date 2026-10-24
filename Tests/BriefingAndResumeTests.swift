import XCTest

final class BriefingAndResumeTests: XCTestCase {
    @MainActor
    func testBriefingFileIsWrittenBeforeLaunchAndHoldsIdentityBoardAndSkills() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        // A command that proves the file exists at launch time, without starting any provider.
        store.cliProfiles.append(
            CLIProfile(
                id: "probe", name: "Probe",
                command: "test -s {briefingPath} && printf ok > "
                    + CommandTemplate.expand(
                        "{out}", values: ["out": directory.appendingPathComponent("probe.txt").path])))
        var session = ManagedSession(name: "Briefed", kind: .cli)
        session.cliProfileID = "probe"
        session.workingDirectory = directory.path
        session.isOrchestrator = true
        store.createTask(title: "Review login flow", owner: session.id)
        store.addSession(session)
        for _ in 0..<200 where store.runtime[session.id]?.isRunning == true {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(
            try? String(contentsOf: directory.appendingPathComponent("probe.txt"), encoding: .utf8), "ok",
            "briefing file missing or empty when the command ran")
        let text = try String(contentsOfFile: store.briefingPath(for: session.id), encoding: .utf8)
        XCTAssertTrue(text.contains("managed session \"Briefed\""))
        XCTAssertTrue(text.contains("Orchestrator"))
        XCTAssertTrue(text.contains("Review login flow"))
        XCTAssertTrue(text.contains("Assigned to you: #1"))
        XCTAssertTrue(store.environment(for: session)["AGENTDECK_BRIEFING"] == store.briefingPath(for: session.id))
        store.removeSession(session.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.briefingPath(for: session.id)))
    }

    @MainActor
    func testStatusSummaryToggleOnlyAffectsTheBriefingBody() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        var session = ManagedSession(name: "Quiet", kind: .cli)
        session.cliProfileID = "claude"
        session.autoInjectContext = false
        store.addSession(session, start: false)
        XCTAssertTrue(store.briefingText(for: session).contains("[AgentDeck] You are managed session"))
        XCTAssertFalse(store.briefingText(for: session).contains("[AgentDeck status]"))
        session.autoInjectContext = true
        XCTAssertTrue(store.briefingText(for: session).contains("[AgentDeck status]"))
    }

    @MainActor
    func testResumeIsUsedOnlyWhenRequestedAndAConversationExists() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        var session = ManagedSession(name: "Fresh", kind: .cli)
        session.cliProfileID = "claude"
        // A brand-new directory has no Claude conversation, so even the default (on) starts fresh.
        session.workingDirectory = directory.appendingPathComponent("never-used-\(UUID())").path
        XCTAssertTrue(session.resumeLastConversation)
        XCTAssertFalse(store.shouldResume(session))
        XCTAssertFalse(store.launchCommand(for: session).contains("--continue"))
        XCTAssertTrue(store.launchCommand(for: session, resume: true).contains("--continue"))
        // Unknown providers with a resume command are trusted to handle a missing conversation themselves.
        store.cliProfiles.append(
            CLIProfile(id: "custom", name: "Custom", command: "agent", resumeCommand: "agent --resume"))
        session.cliProfileID = "custom"
        XCTAssertTrue(store.shouldResume(session))
        XCTAssertEqual(store.launchCommand(for: session), "agent --resume")
        session.resumeLastConversation = false
        XCTAssertFalse(store.shouldResume(session))
        XCTAssertEqual(store.launchCommand(for: session), "agent")
        // Profiles without a resume command never resume.
        session.resumeLastConversation = true
        session.cliProfileID = "shell"
        XCTAssertFalse(store.shouldResume(session))
    }

    func testResumeDetectionReadsEachProvidersStorage() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let fm = FileManager.default
        let cwd = "/Users/someone/gitrepos/my app.v2"
        for id in ["claude", "codex", "gemini"] {
            XCTAssertEqual(ResumeDetection.hasPriorConversation(profileID: id, cwd: cwd, home: home.path), false, id)
        }
        XCTAssertNil(ResumeDetection.hasPriorConversation(profileID: "custom", cwd: cwd, home: home.path))

        let claudeDir = home.appendingPathComponent(".claude/projects/-Users-someone-gitrepos-my-app-v2")
        try fm.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        try Data().write(to: claudeDir.appendingPathComponent("notes.txt"))
        XCTAssertEqual(ResumeDetection.hasPriorConversation(profileID: "claude", cwd: cwd, home: home.path), false)
        try Data().write(to: claudeDir.appendingPathComponent("0f1e-session.jsonl"))
        XCTAssertEqual(ResumeDetection.hasPriorConversation(profileID: "claude", cwd: cwd, home: home.path), true)

        let codexDay = home.appendingPathComponent(".codex/sessions/2026/10/22")
        try fm.createDirectory(at: codexDay, withIntermediateDirectories: true)
        let other = #"{"type":"session_meta","payload":{"cwd":"/Users/someone/gitrepos/other"}}"# + "\n"
        try Data(other.utf8).write(to: codexDay.appendingPathComponent("rollout-2026-10-22T10-00-00-a.jsonl"))
        XCTAssertEqual(ResumeDetection.hasPriorConversation(profileID: "codex", cwd: cwd, home: home.path), false)
        let mine = #"{"type":"session_meta","payload":{"cwd":"/Users/someone/gitrepos/my app.v2"}}"# + "\n"
        try Data(mine.utf8).write(to: codexDay.appendingPathComponent("rollout-2026-10-22T11-00-00-b.jsonl"))
        XCTAssertEqual(ResumeDetection.hasPriorConversation(profileID: "codex", cwd: cwd, home: home.path), true)

        let geminiChats = home.appendingPathComponent(".gemini/tmp/my app.v2/chats")
        try fm.createDirectory(at: geminiChats, withIntermediateDirectories: true)
        XCTAssertEqual(ResumeDetection.hasPriorConversation(profileID: "gemini", cwd: cwd, home: home.path), false)
        try Data().write(to: geminiChats.appendingPathComponent("session-2026-10-22T12-50-abcd.json"))
        XCTAssertEqual(ResumeDetection.hasPriorConversation(profileID: "gemini", cwd: cwd, home: home.path), true)
    }
}
