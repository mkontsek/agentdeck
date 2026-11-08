import Foundation

struct PendingTerminalMetadata {
    struct Program: Equatable {
        let state: String?
        let message: String?
    }
    let generation: Int
    let terminal: ObjectIdentifier
    var title: String?
    var program: Program?
}

extension AppStore {
    /// Presentation metadata can change for every spinner frame. Keep the latest values and publish
    /// one workspace update at most ten times per second; PTY bytes and native drawing bypass this queue.
    func queueTerminalMetadata(_ id: UUID, title: String? = nil, program: PendingTerminalMetadata.Program? = nil) {
        guard let runtime = runtime[id], runtime.isRunning, let view = terminals.view(for: id) else { return }
        let identity = ObjectIdentifier(view)
        var pending =
            pendingTerminalMetadata[id]
            ?? PendingTerminalMetadata(generation: runtime.generation, terminal: identity)
        if pending.generation != runtime.generation || pending.terminal != identity {
            pending = PendingTerminalMetadata(generation: runtime.generation, terminal: identity)
        }
        if let title, title != (pending.title ?? runtime.title) { pending.title = title }
        if let program,
            program != (pending.program ?? .init(state: runtime.programState, message: runtime.programMessage))
        {
            pending.program = program
        }
        guard pending.title != nil || pending.program != nil else { return }
        pendingTerminalMetadata[id] = pending
        guard terminalMetadataFlushTask == nil else { return }
        terminalMetadataFlushTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.flushTerminalMetadata()
        }
    }

    func flushTerminalMetadata() {
        terminalMetadataFlushTask?.cancel()
        terminalMetadataFlushTask = nil
        let pending = pendingTerminalMetadata
        pendingTerminalMetadata.removeAll(keepingCapacity: true)
        var updated = runtime
        for (id, metadata) in pending {
            guard var current = updated[id], current.isRunning, current.generation == metadata.generation,
                let terminal = terminals.view(for: id), ObjectIdentifier(terminal) == metadata.terminal
            else { continue }
            if let title = metadata.title { current.title = title }
            if let program = metadata.program {
                current.programState = program.state
                current.programMessage = program.message
            }
            updated[id] = current
        }
        if updated != runtime { runtime = updated }
    }

    func cancelTerminalMetadata() {
        terminalMetadataFlushTask?.cancel()
        terminalMetadataFlushTask = nil
        pendingTerminalMetadata.removeAll()
    }
}
