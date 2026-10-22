import Foundation

extension CLIProfile {
    var setupURL: URL? {
        let address: String
        switch id {
        case "claude": address = "https://code.claude.com/docs/en/setup"
        case "codex": address = "https://developers.openai.com/codex/cli"
        case "gemini": address = "https://geminicli.com/docs/get-started/installation/"
        case "antigravity": address = "https://antigravity.google/docs/install?tab=cli"
        case "grok": address = "https://docs.x.ai/build/overview"
        default: return nil
        }
        return URL(string: address)
    }
}
