import Foundation

enum WorkerResumePhase: String, Codable, Sendable {
    case checking, submitting, queued, started, ended, failed, cancelled, uncertain

    var reservesWorker: Bool { [.checking, .submitting, .queued, .started, .uncertain].contains(self) }
}

struct WorkerResumeRequest: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var workerID: UUID
    var parentID: UUID
    var taskID: Int
    var taskRevision: Int
    var generation: Int
    var conversationID: String
    var directory: String
    var instructions: String
    var phase: WorkerResumePhase = .checking
    var turnID: String?
    var queuedSubmissionID: String?
    var detail = "Accepted for transport checks; no provider turn has started."
    var createdAt = Date()
    var updatedAt = Date()
}
