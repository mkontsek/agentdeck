import Foundation

/// Transport receipts are not proof that a provider processed a message.
enum InboxReceipt: String, Codable {
    case pending, offered, acknowledged
}

struct InboxEvent: Codable, Identifiable, Equatable {
    var id = UUID()
    let key: String
    let targetID: UUID
    let profileID: String?
    let directory: String
    let source: String
    let text: String
    var receipt: InboxReceipt = .pending
}

/// A separate atomic journal: accepting an event never touches a terminal or waits for an idle heuristic.
/// Session UUID + profile + directory binds a mailbox to a logical session across its process restarts.
@MainActor
final class CoordinationInbox {
    static let maximumBytes = 8 * 1024 * 1024
    private let url: URL
    private(set) var events: [InboxEvent] = []
    private(set) var loadError: String?

    init(url: URL) {
        self.url = url
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= Self.maximumBytes else { throw CoordinationError(message: "Inbox is too large") }
            events = try JSONDecoder().decode([InboxEvent].self, from: data)
        } catch {
            loadError = "Could not load coordination inbox; original file preserved: \(error.localizedDescription)"
        }
    }

    func enqueue(target: ManagedSession, text: String, source: String, key: String) throws -> InboxEvent {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 262_144,
            key.utf8.count <= 512, source.utf8.count <= 1024
        else { throw CoordinationError(message: "Message is empty or exceeds the inbox limit") }
        if let existing = events.first(where: { $0.key == key && $0.targetID == target.id }) {
            guard matches(existing, target: target), existing.text == text, existing.source == source else {
                throw CoordinationError(message: "Message ID already belongs to a different event")
            }
            return existing
        }
        let event = InboxEvent(
            key: key, targetID: target.id, profileID: target.cliProfileID,
            directory: target.effectiveDirectory.expandingTilde, source: source, text: text)
        // Reserve receipt-growth space; acknowledged IDs remain durable deduplication records.
        guard events.count < 4096, try JSONEncoder().encode(events + [event]).count < Self.maximumBytes - 65_536 else {
            throw CoordinationError(message: "Coordination inbox is full; archive it before accepting more events")
        }
        try persist(events + [event])
        return event
    }

    func pending(for target: ManagedSession) -> [InboxEvent] {
        events.filter { matches($0, target: target) && $0.receipt != .acknowledged }
    }

    /// Offer a bounded batch. Lost responses remain available under the same IDs until explicit acknowledgment.
    func offer(to target: ManagedSession) throws -> [InboxEvent] {
        if let loadError { throw CoordinationError(message: loadError) }
        let batch = Array(pending(for: target).prefix(16))
        let ids = Set(batch.map(\.id))
        var next = events
        for index in next.indices where ids.contains(next[index].id) && next[index].receipt == .pending {
            next[index].receipt = .offered
        }
        if next != events { try persist(next) }
        return next.filter { ids.contains($0.id) }
    }

    func acknowledge(_ ids: Set<UUID>, by target: ManagedSession) throws {
        guard !ids.isEmpty, ids.count <= 16,
            ids.allSatisfy({ id in
                events.contains { $0.id == id && matches($0, target: target) && $0.receipt != .pending }
            })
        else { throw CoordinationError(message: "Acknowledge only offered IDs from your own inbox (up to 16)") }
        var next = events
        for index in next.indices where ids.contains(next[index].id) { next[index].receipt = .acknowledged }
        if next != events { try persist(next) }
    }

    private func matches(_ event: InboxEvent, target: ManagedSession) -> Bool {
        event.targetID == target.id && event.profileID == target.cliProfileID
            && event.directory == target.effectiveDirectory.expandingTilde
    }

    private func persist(_ next: [InboxEvent]) throws {
        if let loadError { throw CoordinationError(message: loadError) }
        let data = try JSONEncoder().encode(next)
        guard data.count <= Self.maximumBytes else {
            throw CoordinationError(message: "Coordination inbox is full; existing events have been preserved")
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        events = next
    }
}
