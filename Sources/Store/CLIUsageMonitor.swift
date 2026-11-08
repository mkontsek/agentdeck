import Combine
import Foundation

@MainActor
final class CLIUsageMonitor: ObservableObject {
    @Published private(set) var snapshots: [String: CLIUsageSnapshot] = [:]
    @Published private(set) var refreshing = false
    private var generation = 0
    private var lastAttempt: [String: Date] = [:]
    private let reader: @Sendable (String) async throws -> CLIUsageSnapshot

    init(
        reader: @escaping @Sendable (String) async throws -> CLIUsageSnapshot = { id in
            try await CLIUsageMonitor.readProvider(id)
        }
    ) {
        self.reader = reader
    }

    nonisolated static func readProvider(_ id: String) async throws -> CLIUsageSnapshot {
        switch id {
        case "codex": return try await CodexUsageReader.read()
        case "claude": return try await ClaudeUsageReader.read()
        case "gemini": return try await GeminiUsageReader.read()
        default:
            return CLIUsageSnapshot(
                providerID: id, source: "No account usage connector",
                detail: id == "grok"
                    ? "Open /usage in Grok for account limits. Its usage subcommand reports session tokens, not account allowance."
                    : "Usage, limit and reset are not reported. Check the provider’s CLI or account page.")
        }
    }

    func poll(_ providers: [String]) async {
        while !Task.isCancelled {
            await refresh(providers, force: false)
            let delay =
                refreshing
                ? 1
                : providers.map { id in
                    max(1, 60 - Date().timeIntervalSince(lastAttempt[id] ?? .distantPast))
                }.min() ?? 60
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
        }
    }

    func refresh(_ providers: [String], force: Bool = true, now: Date = Date()) async {
        guard !refreshing else { return }
        refreshing = true
        generation += 1
        let current = generation
        defer { if current == generation { refreshing = false } }
        for id in providers {
            guard !Task.isCancelled else { return }
            if !force, let last = lastAttempt[id], now.timeIntervalSince(last) < 60 { continue }
            let previousAttempt = lastAttempt[id]
            lastAttempt[id] = now
            do {
                let snapshot = try await reader(id)
                try Task.checkCancellation()
                snapshots[id] = snapshot
            } catch {
                if error is CancellationError || Task.isCancelled {
                    lastAttempt[id] = previousAttempt
                    return
                }
                var snapshot = snapshots[id] ?? CLIUsageSnapshot(providerID: id, source: "Account usage")
                snapshot.error = error.localizedDescription
                snapshots[id] = snapshot
            }
        }
    }
}
