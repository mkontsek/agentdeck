import Foundation

extension CLIProfile {
    /// Built-in positional/interactive prompt arguments are consumed by the provider before a composer exists.
    /// Custom profiles can opt in with an explicitly positioned {initialPrompt} placeholder.
    var initialPromptTemplate: String? {
        if command.contains("{initialPrompt}") { return command }
        guard command == Self.builtins.first(where: { $0.id == id })?.command else { return nil }
        switch id {
        case "claude", "codex", "grok": return command + " -- {initialPrompt}"
        case "gemini", "antigravity": return command + " --prompt-interactive {initialPrompt}"
        default: return nil
        }
    }
}
