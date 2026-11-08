import Foundation

/// Provider-owned conversation identity only. No prompts, messages, credentials or terminal output.
struct SessionResumeCheckpoint: Codable, Equatable, Sendable {
    var profileID: String
    var directory: String
    var launchedAt: Date
    var conversationID: String?
    var conversationPath: String?

    func matches(profileID: String, directory: String) -> Bool {
        self.profileID == profileID
            && URL(fileURLWithPath: self.directory).standardizedFileURL.path
                == URL(fileURLWithPath: directory).standardizedFileURL.path
    }

    var hasSavedConversation: Bool {
        guard let conversationID, UUID(uuidString: conversationID) != nil, let conversationPath else { return false }
        return FileManager.default.fileExists(atPath: conversationPath)
    }
}
