import Foundation

extension AppStore {
    func glassBallOwner(in pane: SessionPane) -> ManagedSession? {
        guard let owner = browserOwner(for: pane.activeSession), owner.parentSessionID != nil else { return nil }
        return owner
    }

    func collapsesToGlassBall(_ pane: SessionPane) -> Bool {
        settings.glassBallSubagents && !isDemoMode && maximizedSessionID == nil
            && !pane.tabs.contains { $0.id == focusedSessionID } && glassBallOwner(in: pane) != nil
    }

    func collapseToGlassBall(_ id: UUID) {
        guard settings.glassBallSubagents, !isDemoMode, let pane = pane(containing: id),
            glassBallOwner(in: pane) != nil
        else { return }
        if pane.tabs.contains(where: { $0.id == maximizedSessionID }) { maximizedSessionID = nil }
        if pane.tabs.contains(where: { $0.id == focusedSessionID }) { focusedSessionID = nil }
    }

    func glassBallStatus(for owner: ManagedSession) -> GlassBallStatus {
        let status = status(of: owner.id)
        let tasks = tasks.filter { $0.ownerSessionID == owner.id || $0.id == owner.delegatedTaskID }
        if [.waitingForUser, .stalled, .error, .quotaWarning].contains(status)
            || tasks.contains(where: { [.blocked, .review, .awaitingApproval].contains($0.status) })
        {
            return .attention
        }
        if status == .working || status == .starting { return .working }
        if finishedSessionIDs.contains(owner.id) || (!tasks.isEmpty && tasks.allSatisfy { $0.status == .done }) {
            return .finished
        }
        return .idle
    }
}
