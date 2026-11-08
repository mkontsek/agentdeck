import Darwin
import XCTest

final class ProcessConversationTests: XCTestCase {
    func testCodexProcessOpenFileIdentifiesConversationWithoutReadingTranscript() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let id = UUID().uuidString.lowercased()
        let file = home.appendingPathComponent(".codex/sessions/2026/10/29/rollout-timestamp-\(id).jsonl")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("This deliberately is not JSON or a transcript.".utf8).write(to: file)
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let result = ProcessConversationReader.read(
            profileID: "codex", directory: "/fixture", pid: getpid(), home: home.path)
        XCTAssertEqual(result?.conversationID, id)
        XCTAssertEqual(result?.conversationPath, file.path)
        XCTAssertEqual(try handle.offset(), 0)
        XCTAssertNil(
            ProcessConversationReader.read(profileID: "codex", directory: "/fixture", pid: -1, home: home.path))
    }

    func testClaudeMetadataChecksPIDDirectoryAndSavedConversation() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let id = UUID().uuidString.lowercased()
        let metadata = home.appendingPathComponent(".claude/sessions/\(getpid()).json")
        let transcript = home.appendingPathComponent(".claude/projects/-fixture/\(id).jsonl")
        try FileManager.default.createDirectory(
            at: metadata.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: transcript.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: transcript)
        let data = try JSONSerialization.data(withJSONObject: ["pid": getpid(), "cwd": "/fixture", "sessionId": id])
        try data.write(to: metadata)
        XCTAssertEqual(
            ProcessConversationReader.read(profileID: "claude", directory: "/fixture", pid: getpid(), home: home.path)?
                .conversationID, id)
        XCTAssertNil(
            ProcessConversationReader.read(profileID: "claude", directory: "/other", pid: getpid(), home: home.path))
        try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: metadata.path)
        XCTAssertNil(
            ProcessConversationReader.read(profileID: "claude", directory: "/fixture", pid: getpid(), home: home.path))
        try data.write(to: metadata)
        try FileManager.default.removeItem(at: transcript)
        XCTAssertNil(
            ProcessConversationReader.read(profileID: "claude", directory: "/fixture", pid: getpid(), home: home.path))
    }

    func testMultipleOpenConversationsAndMalformedMetadataAreNotGuessed() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let first = home.path + "/.grok/sessions/%2Ffixture/\(UUID())/events.jsonl"
        let second = home.path + "/.grok/sessions/%2Ffixture/\(UUID())/events.jsonl"
        XCTAssertNotNil(
            ProcessConversationReader.checkpoint(
                profileID: "grok", directory: "/fixture", paths: [first, first], home: home.path))
        XCTAssertNil(
            ProcessConversationReader.checkpoint(
                profileID: "grok", directory: "/fixture", paths: [first, second], home: home.path))
        XCTAssertNil(
            ProcessConversationReader.checkpoint(
                profileID: "grok", directory: "/fixture", paths: ["/elsewhere/\(UUID())/events.jsonl"], home: home.path)
        )
        let receipt = ResumeCheckpointStorage.url(for: UUID(), directory: home)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try Data(repeating: 65, count: 8193).write(to: receipt)
        XCTAssertNil(ProcessConversationReader.boundedData(at: receipt, limit: 8192))
    }
}
