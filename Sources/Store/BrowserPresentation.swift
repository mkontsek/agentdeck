import AppKit

extension AppStore {
    func browserOwner(for session: ManagedSession) -> ManagedSession? {
        if session.kind == .cli { return session }
        guard let owner = self.session(session.agentOwnerID), owner.kind == .cli,
            owner.paneID == session.paneID
        else { return nil }
        return owner
    }

    func visibleSessions(in pane: SessionPane) -> [ManagedSession] {
        guard let owner = browserOwner(for: pane.activeSession), owner.browserSplitEnabled,
            let browser = agentBrowser(for: owner.id), browser.paneID == pane.id
        else {
            return [pane.activeSession]
        }
        return [owner, browser]
    }

    func setBrowserSplit(for session: ManagedSession, enabled: Bool) {
        guard var owner = browserOwner(for: session) else { return }
        owner.browserSplitEnabled = enabled
        updateSession(owner)
    }

    func toggleMaximize(_ id: UUID) {
        guard let pane = pane(containing: id) else { return }
        if session(maximizedSessionID)?.paneID == pane.id {
            maximizedSessionID = nil
            paneRevealRevision += 1
        } else {
            focusSession(id)
            maximizedSessionID = id
        }
    }

    func setDemoMode(_ enabled: Bool) {
        isDemoMode = enabled
        if enabled { NSApp.keyWindow?.makeFirstResponder(nil) }
    }
}
