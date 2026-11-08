import Foundation

enum WorkspaceMode: String, Codable, CaseIterable, Identifiable {
    case board, sessions
    var id: String { rawValue }
}

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case todo
    case inProgress = "in-progress"
    case review
    case awaitingApproval = "awaiting-approval"
    case done, blocked
    var id: String { rawValue }
    var label: String {
        switch self {
        case .todo: return "To do"
        case .inProgress: return "In progress"
        case .review: return "In review"
        case .awaitingApproval: return "Awaiting approval"
        case .done: return "Done"
        case .blocked: return "Blocked"
        }
    }
    var systemImage: String {
        switch self {
        case .todo: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .review: return "eye"
        case .awaitingApproval: return "person.badge.clock"
        case .done: return "checkmark.circle.fill"
        case .blocked: return "hand.raised.fill"
        }
    }
}

struct TaskEvent: Codable, Identifiable, Hashable {
    var id = UUID()
    var at = Date()
    var actor: String
    var message: String
}

struct BoardTask: Codable, Identifiable, Hashable {
    var id: Int
    var title: String
    var description: String = ""
    var ownerSessionID: UUID?
    var status: TaskStatus = .todo
    var notes: String = ""
    var createdBy: String = "user"
    var createdBySessionID: UUID?
    var createdAt = Date()
    var updatedAt = Date()
    var revision = 0
    var dependencies: [Int] = []
    var requiresApproval = true
    var events: [TaskEvent] = []

    init(
        id: Int, title: String, description: String = "", ownerSessionID: UUID? = nil,
        status: TaskStatus = .todo, notes: String = "", createdBy: String = "user"
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.ownerSessionID = ownerSessionID
        self.status = status
        self.notes = notes
        self.createdBy = createdBy
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description, ownerSessionID, status, notes, createdBy, createdBySessionID,
            createdAt, updatedAt, revision, dependencies, requiresApproval, events
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = c.value(.title, default: "Untitled")
        description = c.value(.description, default: "")
        ownerSessionID = c.value(.ownerSessionID, default: nil)
        status = c.value(.status, default: .todo)
        notes = c.value(.notes, default: "")
        createdBy = c.value(.createdBy, default: "user")
        createdBySessionID = c.value(.createdBySessionID, default: nil)
        createdAt = c.value(.createdAt, default: Date())
        updatedAt = c.value(.updatedAt, default: Date())
        revision = c.value(.revision, default: 0)
        dependencies = c.value(.dependencies, default: [])
        // Existing tasks retain their completion contract. New tasks require user approval.
        requiresApproval = c.value(.requiresApproval, default: false)
        events = c.value(.events, default: [])
    }
}

enum HandoffStatus: String, Codable, CaseIterable {
    case awaitingApproval = "awaiting-approval"
    case queued, delivering, delivered, accepted, declined, cancelled, failed
    var isOpen: Bool {
        switch self {
        case .awaitingApproval, .queued, .delivering, .delivered, .failed: return true
        case .accepted, .declined, .cancelled: return false
        }
    }
    var label: String {
        switch self {
        case .awaitingApproval: return "Awaiting approval"
        case .queued: return "Queued"
        case .delivering: return "Delivering"
        case .delivered: return "Awaiting acceptance"
        case .accepted: return "Accepted"
        case .declined: return "Declined"
        case .cancelled: return "Cancelled"
        case .failed: return "Needs retry"
        }
    }
}

/// A snapshot of deliberately published context, never terminal output or browser state.
struct HandoffContext: Codable, Hashable {
    var objective: String
    var sharedNotes: String
    var summary: String
    var constraints: String
    var artifacts: [String]
    var verification: String
    var nextAction: String
}

struct TaskHandoff: Codable, Identifiable, Hashable {
    var id = UUID()
    var taskID: Int
    var taskTitle: String
    var taskRevision: Int
    var previousOwnerID: UUID?
    var fromSessionID: UUID?
    var fromName: String
    var targetSessionID: UUID
    var targetName: String
    var context: HandoffContext
    var status: HandoffStatus
    var createdAt = Date()
    var updatedAt = Date()
    var detail = ""
    var events: [TaskEvent] = []
}
