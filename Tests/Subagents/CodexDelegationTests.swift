import XCTest

final class CodexDelegationTests: XCTestCase {
    private let oldArguments =
        "--dangerously-bypass-approvals-and-sandbox -c 'mcp_servers.agentdeck.url=\"{mcpUrl}\"' -c {briefingConfig}"

    func testOnlyExactShippedTemplatesMigrateIndependently() throws {
        let builtin = try XCTUnwrap(CLIProfile.builtins.first { $0.id == "codex" })
        var old = builtin
        old.command = "codex " + oldArguments
        old.resumeCommand = "codex resume --last " + oldArguments
        old.name = "My Codex"
        old.notes = "Keep this"
        old.submitDelayMs = 321
        let migrated = old.adoptingCodexDelegationDefaults()
        XCTAssertEqual(migrated.command, builtin.command)
        XCTAssertEqual(migrated.resumeCommand, builtin.resumeCommand)
        XCTAssertEqual(migrated.name, old.name)
        XCTAssertEqual(migrated.notes, old.notes)
        XCTAssertEqual(migrated.submitDelayMs, old.submitDelayMs)
        XCTAssertEqual(migrated.adoptingCodexDelegationDefaults(), migrated)
        XCTAssertNotNil(migrated.exactResumeCommand)
        XCTAssertNotNil(migrated.initialPromptTemplate)

        var custom = old
        custom.command += " --model custom"
        XCTAssertEqual(custom.adoptingCodexDelegationDefaults().command, custom.command)
        XCTAssertEqual(custom.adoptingCodexDelegationDefaults().resumeCommand, builtin.resumeCommand)
        custom.resumeCommand = "custom-resume {conversationId}"
        XCTAssertEqual(custom.adoptingCodexDelegationDefaults(), custom)
        custom.command = old.command
        XCTAssertEqual(custom.adoptingCodexDelegationDefaults().command, builtin.command)
        XCTAssertEqual(custom.adoptingCodexDelegationDefaults().resumeCommand, custom.resumeCommand)
        custom.resumeCommand = nil
        XCTAssertEqual(custom.adoptingCodexDelegationDefaults().resumeCommand, builtin.resumeCommand)
        custom.id = "my-codex"
        XCTAssertEqual(custom.adoptingCodexDelegationDefaults(), custom)
    }

    @MainActor
    func testPersistedProfileMigratesWithoutChangingSessionsOrTasks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(stateURL: url)
        var parent = ManagedSession(name: "Parent", kind: .cli)
        parent.cliProfileID = "codex"
        store.addSession(parent, start: false)
        let worker = try store.delegateTask(from: parent.id, title: "Fixture", instructions: "Fixture", start: false)
        let index = try XCTUnwrap(store.cliProfiles.firstIndex { $0.id == "codex" })
        store.cliProfiles[index].command = "codex " + oldArguments
        store.cliProfiles[index].resumeCommand = "codex resume --last " + oldArguments
        store.shutdown()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let saved = try decoder.decode(PersistedState.self, from: Data(contentsOf: url))
        let restored = AppStore(stateURL: url)
        defer { restored.shutdown() }
        XCTAssertEqual(restored.cliProfiles[index].command, CLIProfile.builtins[index].command)
        XCTAssertEqual(restored.sessions, saved.sessions)
        XCTAssertEqual(restored.tasks, saved.tasks)
        XCTAssertEqual(restored.focusedSessionID, parent.id)
        XCTAssertEqual(restored.session(worker.id)?.parentSessionID, parent.id)
        XCTAssertTrue(restored.settings.automaticSubagents)
        XCTAssertTrue(restored.terminals.views.isEmpty)
    }

    @MainActor
    func testLaunchAndExactResumeRespectMainWorkerAndDisabledPolicies() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        var parent = ManagedSession(name: "Quotes '\" $(echo BAD) `echo BAD`\nžltý", kind: .cli)
        parent.cliProfileID = "codex"
        parent.workingDirectory = directory.path
        parent.resumeLastConversation = false
        store.addSession(parent, start: false)
        let worker = try store.delegateTask(from: parent.id, title: "Fixture", instructions: "Fixture", start: false)
        let conversationID = UUID().uuidString
        let conversation = directory.appendingPathComponent(conversationID + ".jsonl")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: conversation)
        store.saveResumeCheckpoint(
            SessionResumeCheckpoint(
                profileID: "codex", directory: parent.effectiveDirectory, launchedAt: Date(),
                conversationID: conversationID, conversationPath: conversation.path), for: parent.id)
        for enabled in [true, false] {
            store.settings.automaticSubagents = enabled
            for session in [parent, worker] {
                for resume in [false, true] {
                    let args = try launchArguments(store, session: session, resume: resume)
                    XCTAssertTrue(args.contains("features.multi_agent_v2.disable_native_tools=true"))
                    let key = "features.multi_agent_v2.multi_agent_mode_hint_text="
                    let config = try XCTUnwrap(args.first { $0.hasPrefix(key) })
                    let policy = try JSONDecoder().decode(
                        String.self, from: Data(config.dropFirst(key.count).utf8))
                    XCTAssertTrue(policy.contains("Use only AgentDeck MCP tools"))
                    if session.id == worker.id {
                        XCTAssertTrue(policy.contains("Do not delegate or recruit more agents"))
                        XCTAssertFalse(policy.contains("call delegate_task"))
                    } else if enabled {
                        XCTAssertTrue(policy.contains("call delegate_task"))
                        XCTAssertTrue(policy.contains("promptly end your turn"))
                    } else {
                        XCTAssertTrue(policy.contains("Do not create workers"))
                        XCTAssertFalse(policy.contains("call delegate_task"))
                    }
                    if session.id == parent.id, resume {
                        XCTAssertEqual(Array(args.prefix(2)), ["resume", conversationID])
                    }
                    if session.id == worker.id {
                        XCTAssertEqual(args.contains(worker.initialPrompt!), !resume)
                    }
                }
            }
        }
        XCTAssertEqual(store.focusedSessionID, parent.id)
        XCTAssertFalse(store.canDelegate(from: worker.id))
    }

    @MainActor
    private func launchArguments(_ store: AppStore, session: ManagedSession, resume: Bool) throws -> [String] {
        let stub = "codex() { printf '%s\\0' \"$@\"; }\n"
        return try Shell.run(["/bin/zsh", "-f", "-c", stub + store.launchCommand(for: session, resume: resume)])
            .split(separator: "\0").map(String.init)
    }
}
