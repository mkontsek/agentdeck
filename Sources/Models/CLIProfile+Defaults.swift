import Foundation

extension CLIProfile {
    /// Upgrade only commands previously shipped by AgentDeck, preserving all other profile fields.
    func migratingUnrestrictedDefault() -> CLIProfile {
        let previousCommands = [
            "claude": "claude --mcp-config \"{mcpConfigPath}\"",
            "codex": "codex -c 'mcp_servers.agentdeck.url=\"{mcpUrl}\"'",
            "gemini": "gemini",
            "antigravity": "agy",
            "grok": "grok",
        ]
        guard command == previousCommands[id], let builtin = Self.builtins.first(where: { $0.id == id }) else {
            return self
        }
        var updated = self
        updated.command = builtin.command
        return updated
    }

    /// Idempotent: moves an unchanged shipped command to the current built-in one (which delivers the briefing
    /// through the command line) and adopts the built-in resume command when none was ever set.
    func adoptingBriefingAndResumeDefaults() -> CLIProfile {
        guard let builtin = Self.builtins.first(where: { $0.id == id }) else { return self }
        var updated = self
        let shippedBefore = ["claude": "claude --dangerously-skip-permissions --mcp-config \"{mcpConfigPath}\""]
        if updated.command == shippedBefore[id] { updated.command = builtin.command }
        if updated.resumeCommand == nil, updated.command == builtin.command {
            updated.resumeCommand = builtin.resumeCommand
        }
        return updated
    }
}
