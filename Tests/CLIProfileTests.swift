import XCTest

final class CLIProfileTests: XCTestCase {
    @MainActor
    func testBuiltinLaunchArgumentsIncludeBypassAndMCPConfiguration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AgentDeck 'profile' \(UUID())")
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        var session = ManagedSession(name: "Test", kind: .cli)
        session.resumeLastConversation = false
        let expectedArguments = [
            "claude": [
                "--dangerously-skip-permissions", "--mcp-config", store.mcpConfigPath(for: session.id),
                "--append-system-prompt-file", store.briefingPath(for: session.id),
            ],
            "codex": [
                "--dangerously-bypass-approvals-and-sandbox", "-c",
                "mcp_servers.agentdeck.url=\"\(store.mcpURL(for: session.id))\"",
            ],
            "gemini": ["--yolo"],
            "antigravity": ["--dangerously-skip-permissions"],
            "grok": ["--always-approve"],
        ]
        // Shell functions record arguments without launching a provider or reading its configuration.
        let stubs = """
            claude() { printf '%s\\n' "$@"; }
            codex() { printf '%s\\n' "$@"; }
            gemini() { printf '%s\\n' "$@"; }
            agy() { printf '%s\\n' "$@"; }
            grok() { printf '%s\\n' "$@"; }
            """
        for (id, arguments) in expectedArguments {
            session.cliProfileID = id
            let command = stubs + "\n" + store.launchCommand(for: session)
            let output = try Shell.run(["/bin/zsh", "-f", "-c", command])
            XCTAssertEqual(output.split(separator: "\n").map { String($0) }, arguments, id)
        }
        XCTAssertEqual(
            store.cliProfiles.first { $0.id == "shell" }?.command, "exec ${SHELL:-/bin/zsh} -l")
        // Resume commands keep the same arguments and add the provider's continue flag.
        let expectedResumeArguments = [
            "claude": ["--continue"] + expectedArguments["claude"]!,
            "codex": ["resume", "--last"] + expectedArguments["codex"]!,
            "gemini": ["--yolo", "--resume", "latest"],
        ]
        for (id, arguments) in expectedResumeArguments {
            session.cliProfileID = id
            let command = stubs + "\n" + store.launchCommand(for: session, resume: true)
            let output = try Shell.run(["/bin/zsh", "-f", "-c", command])
            XCTAssertEqual(output.split(separator: "\n").map { String($0) }, arguments, id)
        }
        XCTAssertNil(store.cliProfiles.first { $0.id == "shell" }?.resumeCommand)
    }

    @MainActor
    func testUnchangedOlderClaudeCommandAdoptsBriefingFileAndResumeCommands() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("state.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var state = PersistedState()
        state.unrestrictedCLIDefaultsApplied = true
        state.cliProfiles = CLIProfile.builtins.map { profile in
            var saved = profile
            saved.resumeCommand = nil
            if profile.id == "claude" {
                saved.command = "claude --dangerously-skip-permissions --mcp-config \"{mcpConfigPath}\""
            }
            if profile.id == "codex" { saved.command = "codex --model gpt-5" }
            return saved
        }
        try JSONEncoder().encode(state).write(to: url)
        let store = AppStore(stateURL: url)
        defer { store.shutdown() }
        let claude = try XCTUnwrap(store.cliProfiles.first { $0.id == "claude" })
        XCTAssertEqual(claude.command, CLIProfile.builtins[0].command)
        XCTAssertEqual(claude.resumeCommand, CLIProfile.builtins[0].resumeCommand)
        // A customised command keeps its text and gets no resume command imposed on it.
        let codex = try XCTUnwrap(store.cliProfiles.first { $0.id == "codex" })
        XCTAssertEqual(codex.command, "codex --model gpt-5")
        XCTAssertNil(codex.resumeCommand)
        XCTAssertEqual(store.cliProfiles.first { $0.id == "gemini" }?.resumeCommand, "gemini --yolo --resume latest")
    }

    @MainActor
    func testLegacyDefaultsMigrateOnceAndPreserveCustomProfiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("state.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let previousCommands = [
            "claude": "claude --mcp-config \"{mcpConfigPath}\"",
            "codex": "codex -c 'mcp_servers.agentdeck.url=\"{mcpUrl}\"'",
            "gemini": "gemini",
            "antigravity": "agy",
            "grok": "grok",
        ]
        var state = PersistedState()
        state.cliProfiles = CLIProfile.builtins.map { profile in
            var legacy = profile
            legacy.command = previousCommands[profile.id] ?? profile.command
            legacy.name = "My \(profile.name)"
            legacy.submitDelayMs = 321
            legacy.notes = "Keep my notes"
            return legacy
        }
        let custom = CLIProfile(id: "custom", name: "Custom", command: "grok --model custom")
        state.cliProfiles.append(custom)
        // Remove the marker to reproduce a saved workspace from before this migration.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        json.removeValue(forKey: "unrestrictedCLIDefaultsApplied")
        try JSONSerialization.data(withJSONObject: json).write(to: url)

        let migrated = AppStore(stateURL: url)
        for builtin in CLIProfile.builtins {
            let profile = try XCTUnwrap(migrated.cliProfiles.first { $0.id == builtin.id })
            XCTAssertEqual(profile.command, builtin.command)
            XCTAssertEqual(profile.name, "My \(builtin.name)")
            XCTAssertEqual(profile.submitDelayMs, 321)
            XCTAssertEqual(profile.notes, "Keep my notes")
        }
        XCTAssertEqual(migrated.cliProfiles.last, custom)
        // A later deliberate opt-out must survive another launch.
        let index = try XCTUnwrap(migrated.cliProfiles.firstIndex { $0.id == "grok" })
        migrated.cliProfiles[index].command = "grok"
        migrated.shutdown()
        let restored = AppStore(stateURL: url)
        defer { restored.shutdown() }
        XCTAssertEqual(restored.cliProfiles.first { $0.id == "grok" }?.command, "grok")
        XCTAssertEqual(restored.cliProfiles.first { $0.id == "claude" }?.command, CLIProfile.builtins[0].command)
    }

    func testMigrationPreservesCustomCommandsAndAlreadyUpdatedDefaults() {
        let custom = CLIProfile(id: "claude", name: "Custom Claude", command: "claude --model sonnet")
        XCTAssertEqual(custom.migratingUnrestrictedDefault(), custom)
        let renamed = CLIProfile(id: "my-gemini", name: "Gemini", command: "gemini")
        XCTAssertEqual(renamed.migratingUnrestrictedDefault(), renamed)
        for profile in CLIProfile.builtins {
            XCTAssertEqual(profile.migratingUnrestrictedDefault(), profile)
        }
    }
}
