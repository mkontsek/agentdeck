import Foundation

enum ResumeCheckpointStorage {
    static func url(for id: UUID, directory: URL) -> URL { directory.appendingPathComponent("\(id.uuidString).json") }

    static func read(id: UUID, directory: URL) -> SessionResumeCheckpoint? {
        guard let data = ProcessConversationReader.boundedData(at: url(for: id, directory: directory), limit: 8192)
        else { return nil }
        return try? JSONDecoder().decode(SessionResumeCheckpoint.self, from: data)
    }

    static func write(_ checkpoint: SessionResumeCheckpoint, id: UUID, directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(checkpoint).write(to: url(for: id, directory: directory), options: .atomic)
    }
}
