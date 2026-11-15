import Foundation

extension AppStore {
    func removeMiniWindow(containing id: UUID) {
        guard let pane = pane(containing: id) else { return }
        let members = Set(pane.tabs.map(\.id))
        guard
            !workerResumes.requests.contains(where: {
                $0.phase.reservesWorker && (members.contains($0.workerID) || members.contains($0.parentID))
            })
        else {
            lastError = "Cancel or reconcile worker continuations before removing this mini-window."
            return
        }
        // Close browser tabs first so removing their owners cannot delete an isolated sign-in profile.
        // Snapshot membership before removal changes the selected tab or promotes independent workers.
        let ordered = pane.tabs.filter { $0.kind == .browser } + pane.tabs.filter { $0.kind != .browser }
        for tab in ordered { removeSession(tab.id) }
    }
}
