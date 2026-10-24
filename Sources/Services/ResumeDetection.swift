import Foundation

/// Finds out whether a provider has a conversation to continue for a working directory, by looking at the
/// provider's own on-disk session storage. `nil` means the layout is unknown and the resume command decides.
enum ResumeDetection {
    static func hasPriorConversation(profileID: String, cwd: String, home: String = NSHomeDirectory()) -> Bool? {
        let cwd = cwd.expandingTilde
        let fm = FileManager.default
        switch profileID {
        case "claude":
            // ~/.claude/projects/<cwd with every non-alphanumeric character replaced by "-">/<session>.jsonl
            let encoded = String(cwd.map { $0.isLetter || $0.isNumber ? $0 : "-" })
            let dir = home + "/.claude/projects/" + encoded
            return (try? fm.contentsOfDirectory(atPath: dir))?.contains { $0.hasSuffix(".jsonl") } ?? false
        case "codex":
            // ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl; the first line is session_meta with the cwd.
            let root = URL(fileURLWithPath: home + "/.codex/sessions")
            guard let files = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { return false }
            let marker = "\"cwd\":\"" + cwd + "\""
            for case let file as URL in files where file.lastPathComponent.hasPrefix("rollout-") {
                guard let handle = try? FileHandle(forReadingFrom: file) else { continue }
                defer { try? handle.close() }
                guard let head = try? handle.read(upToCount: 8192), let text = String(data: head, encoding: .utf8)
                else { continue }
                if text.contains(marker) { return true }
            }
            return false
        case "gemini":
            // ~/.gemini/tmp/<directory name>/chats/session-*.json
            let dir = home + "/.gemini/tmp/" + URL(fileURLWithPath: cwd).lastPathComponent + "/chats"
            return (try? fm.contentsOfDirectory(atPath: dir))?.contains { $0.hasSuffix(".json") } ?? false
        default:
            return nil
        }
    }
}
