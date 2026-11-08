import Foundation

extension CLIProfile {
    /// Only rewrite unchanged built-in templates. Custom profiles can explicitly opt into {conversationId}.
    var exactResumeCommand: String? {
        guard canResume else { return nil }
        if resumeCommand?.contains("{conversationId}") == true { return resumeCommand }
        guard let builtin = Self.builtins.first(where: { $0.id == id }),
            command == builtin.command, resumeCommand == builtin.resumeCommand
        else { return nil }
        switch id {
        case "claude": return resumeCommand?.replacingOccurrences(of: "--continue", with: "--resume {conversationId}")
        case "codex": return resumeCommand?.replacingOccurrences(of: "--last", with: "{conversationId}")
        case "grok": return resumeCommand?.replacingOccurrences(of: "--continue", with: "--resume {conversationId}")
        default: return nil
        }
    }
}
