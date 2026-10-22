import Foundation

enum DefaultSessions {
    /// Prefer each provider's CLI; use its browser preset when no CLI profile is available.
    static func make(profiles: [CLIProfile], workingDirectory: String) -> [ManagedSession] {
        let builtInIDs = Set(CLIProfile.builtins.map(\.id)).subtracting(["shell"])
        let hasAntigravity = profiles.contains { $0.id == "antigravity" }
        let selectedProfiles = profiles.filter {
            builtInIDs.contains($0.id) && !($0.id == "gemini" && hasAntigravity)
        }
        var result = selectedProfiles.map { profile in
            var session = ManagedSession(name: profile.name, kind: .cli)
            session.cliProfileID = profile.id
            session.workingDirectory = workingDirectory.expandingTilde
            return session
        }
        let activeCLIIDs = Set(result.compactMap(\.cliProfileID))
        let browserPresets = BrowserPreset.allCases.filter { preset in
            switch preset {
            case .chatgpt: return !activeCLIIDs.contains("codex")
            case .claude: return !activeCLIIDs.contains("claude")
            case .gemini: return !activeCLIIDs.contains("gemini") && !activeCLIIDs.contains("antigravity")
            case .grok: return !activeCLIIDs.contains("grok")
            case .perplexity: return true
            case .custom: return false
            }
        }
        result += browserPresets.map { preset in
            var session = ManagedSession(name: preset.label, kind: .browser)
            session.url = preset.url
            return session
        }
        return SessionOrdering.ordered(result)
    }
}
