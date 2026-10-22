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
}
