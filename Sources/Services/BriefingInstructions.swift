import Foundation

enum BriefingInstructions {
    /// Encode TOML basic strings before shell-template escaping, including all prohibited control scalars.
    static func tomlString(_ text: String) -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    result += String(format: "\\u%04X", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result + "\""
    }

    static let bridge = """
        <!-- AgentDeck managed context bridge v1 -->
        ## AgentDeck managed sessions

        At the beginning of every fresh, resumed, or cleared conversation, check the
        AGENTDECK_SESSION_ID and AGENTDECK_BRIEFING environment variables before answering.
        If both are set, read the complete file at AGENTDECK_BRIEFING and follow its
        session identity, coordination, browser, task-board, delegation, and skill instructions.
        This is required even if the user has not asked you to read the briefing.
        Use only this process's briefing; sibling sessions have different identities.
        If the variables are absent, this section does not apply.
        If the file cannot be read, report that AgentDeck context could not be loaded.
        <!-- End AgentDeck managed context bridge -->
        """

    /// Gemini and Antigravity both load this global instruction file after conversation resets.
    /// Keep user content byte-for-byte and never replace the provider's built-in system prompt.
    static func installBridge(home: URL) throws {
        let file = home.appendingPathComponent(".gemini/GEMINI.md")
        let manager = FileManager.default
        let existing = manager.fileExists(atPath: file.path) ? try String(contentsOf: file, encoding: .utf8) : ""
        if existing.contains(bridge) { return }
        try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (existing + (existing.isEmpty ? "" : "\n\n") + bridge + "\n").write(
            to: file, atomically: true, encoding: .utf8)
    }
}
