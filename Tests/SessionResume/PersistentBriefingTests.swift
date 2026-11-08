import XCTest

final class PersistentBriefingTests: XCTestCase {
    func testMigrationUpgradesOnlyShippedLaunchAndResumeCommands() throws {
        let old = [
            CLIProfile(
                id: "codex", name: "Mine",
                command: "codex --dangerously-bypass-approvals-and-sandbox -c 'mcp_servers.agentdeck.url=\"{mcpUrl}\"'",
                resumeCommand:
                    "codex resume --last --dangerously-bypass-approvals-and-sandbox -c 'mcp_servers.agentdeck.url=\"{mcpUrl}\"'"
            ),
            CLIProfile(
                id: "grok", name: "Mine", command: "grok --always-approve",
                resumeCommand: "grok --continue --always-approve"),
        ]
        for profile in old {
            let builtin = try XCTUnwrap(CLIProfile.builtins.first { $0.id == profile.id })
            let migrated = profile.adoptingBriefingAndResumeDefaults()
            XCTAssertEqual(migrated.command, builtin.command)
            XCTAssertEqual(migrated.resumeCommand, builtin.resumeCommand)
            XCTAssertEqual(migrated.name, "Mine")
            XCTAssertNotNil(migrated.exactResumeCommand)
            XCTAssertEqual(migrated.adoptingBriefingAndResumeDefaults(), migrated)
            var custom = profile
            custom.command += " --model custom"
            custom.resumeCommand = "my-resume"
            XCTAssertEqual(custom.adoptingBriefingAndResumeDefaults(), custom)
            custom.command = profile.command
            XCTAssertEqual(custom.adoptingBriefingAndResumeDefaults().resumeCommand, "my-resume")
        }
    }

    func testBridgePreservesExistingRulesAndIsIdempotent() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appendingPathComponent(".gemini/GEMINI.md")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = "# My rules\nPreserve these instructions.\n"
        try original.write(to: file, atomically: true, encoding: .utf8)
        try BriefingInstructions.installBridge(home: home)
        let first = try String(contentsOf: file, encoding: .utf8)
        try BriefingInstructions.installBridge(home: home)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), first)
        XCTAssertTrue(first.hasPrefix(original))
        XCTAssertTrue(first.contains("AGENTDECK_BRIEFING"))
        XCTAssertTrue(first.contains("cleared conversation"))
        try Data([0xFF]).write(to: file)
        XCTAssertThrowsError(try BriefingInstructions.installBridge(home: home))
        XCTAssertEqual(try Data(contentsOf: file), Data([0xFF]))
    }

    @MainActor
    func testEveryBuiltinHasPersistentContextAndLiteralPayload() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: home.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: home)
        }
        var session = ManagedSession(name: "Quotes '\" `echo BAD` $(echo BAD) \\ and\nnewline", kind: .cli)
        session.resumeLastConversation = false
        for profile in CLIProfile.builtins where profile.supportsMCP {
            XCTAssertTrue(profile.deliversBriefingInCommand || profile.usesBriefingRuleBridge, profile.id)
            if let resume = profile.resumeCommand {
                XCTAssertTrue(CLIProfile.includesBriefing(resume) || profile.usesBriefingRuleBridge, profile.id)
            }
        }
        for id in ["codex", "grok"] {
            session.cliProfileID = id
            let stubs = "codex() { printf '%s\\0' \"$@\"; }; grok() { printf '%s\\0' \"$@\"; }\n"
            for resume in [false, true] {
                let output = try Shell.run([
                    "/bin/zsh", "-f", "-c", stubs + store.launchCommand(for: session, resume: resume),
                ])
                let last = try XCTUnwrap(output.split(separator: "\0").last)
                if id == "codex" {
                    let json = String(last).replacingOccurrences(of: "developer_instructions=", with: "")
                    XCTAssertEqual(
                        try JSONDecoder().decode(String.self, from: Data(json.utf8)), store.briefingText(for: session))
                } else {
                    XCTAssertEqual(String(last), store.briefingText(for: session))
                }
            }
        }
    }
}
