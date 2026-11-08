import Foundation

/// Process-local only. Closing a panel must neither reread Keychain nor persist a credential.
actor UsageCredentialCache {
    private let loader: @Sendable () async throws -> String
    private let lifetime: TimeInterval
    private var cached: (token: String, date: Date)?
    private var pending: Task<String, Error>?
    private var generation = 0

    init(lifetime: TimeInterval = 300, loader: @escaping @Sendable () async throws -> String) {
        self.lifetime = lifetime
        self.loader = loader
    }

    func token(now: Date = Date()) async throws -> String {
        if let cached, now.timeIntervalSince(cached.date) < lifetime { return cached.token }
        if let pending { return try await pending.value }
        let revision = generation
        let work = Task.detached(priority: .utility) { [loader] in try await loader() }
        pending = work
        do {
            let token = try await work.value
            pending = nil
            if generation == revision {
                cached = (token, now)
            }
            return token
        } catch {
            pending = nil
            throw error
        }
    }

    func invalidate() {
        generation += 1
        cached = nil
        // Leave the synchronous lookup serialized until it finishes, then discard its result.
    }
}
