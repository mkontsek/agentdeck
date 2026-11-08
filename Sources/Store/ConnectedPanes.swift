import Foundation

extension AppStore {
    /// Repair legacy nesting using only presentation fields. Never recreate a PTY, browser, profile or resume ID.
    /// Reapplying this invariant leaves valid pane IDs and geometry unchanged, including after a tab closes.
    func separateConnectedPanes() {
        let oldSelection = selectedPaneTabs.values
        for id in oldSelection {
            if let browser = session(id), let owner = browser.agentOwnerID {
                selectedBrowserTabs[owner] = id
            }
        }
        var updated = sessions
        for index in updated.indices where updated[index].kind == .cli && updated[index].parentSessionID != nil {
            guard updated[index].paneID != updated[index].id else { continue }
            updated[index].paneID = updated[index].id
            updated[index].canvasPosition = nil
        }
        let owners = Set(updated.filter { $0.kind == .browser }.compactMap(\.agentOwnerID))
        for owner in owners {
            let indices = updated.indices.filter { updated[$0].kind == .browser && updated[$0].agentOwnerID == owner }

            guard let agent = updated.first(where: { $0.id == owner && $0.kind == .cli }) else { continue }
            for index in indices {
                updated[index].paneID = agent.paneID
                updated[index].canvasPosition = agent.canvasPosition
                updated[index].paneSize = agent.paneSize
                updated[index].zIndex = agent.zIndex
            }
        }
        if updated != sessions { sessions = updated }
        var selected = selectedPaneTabs.filter { paneID, id in
            sessions.contains { $0.id == id && $0.paneID == paneID }
        }
        // Preserve a previously expanded browser tab even when keyboard focus stayed in its parent's terminal.
        for id in expandedSubagentTabs.values {
            if let tab = session(id) {
                if let owner = tab.agentOwnerID { selectedBrowserTabs[owner] = id }
                if selected[tab.paneID] == nil { selected[tab.paneID] = id }
            }
        }
        for session in sessions where selected[session.paneID] == nil { selected[session.paneID] = session.id }
        if selected != selectedPaneTabs { selectedPaneTabs = selected }
        if let focused = session(focusedSessionID) { selectedPaneTabs[focused.paneID] = focused.id }
        selectedBrowserTabs = selectedBrowserTabs.filter { owner, id in
            sessions.contains { $0.id == id && $0.agentOwnerID == owner && $0.kind == .browser }
        }
        if !expandedSubagentTabs.isEmpty { expandedSubagentTabs = [:] }
    }

    /// Place a new connected pane beside its owner, moving down past occupied rectangles.
    func connectedPanePosition(after owner: ManagedSession, size: PaneSize) -> PanePoint? {
        guard let origin = owner.canvasPosition else { return nil }
        let x = origin.x + paneSize(for: owner).width + 48
        var candidate = CGRect(x: x, y: origin.y, width: size.width, height: size.height)
        let occupied = panes.compactMap { pane -> CGRect? in
            guard let point = pane.activeSession.canvasPosition else { return nil }
            let size = paneSize(for: pane.activeSession)
            return CGRect(x: point.x, y: point.y, width: size.width, height: size.height)
        }
        while let collision = occupied.first(where: { $0.insetBy(dx: -16, dy: -16).intersects(candidate) }) {
            candidate.origin.y = collision.maxY + 32
        }
        return PanePoint(x: candidate.minX, y: candidate.minY)
    }

    @discardableResult
    func addBrowserTab(to id: UUID, start: Bool = true, focus: Bool = true) -> ManagedSession? {
        guard let source = session(id), source.kind == .browser else { return nil }
        var tab = ManagedSession(name: "Browser tab", kind: .browser)
        tab.agentOwnerID = source.agentOwnerID
        tab.browserProfileMode = source.browserProfileMode
        tab.browserProfileID = source.browserProfileID
        tab.url = "about:blank"
        tab.paneID = source.paneID
        tab.paneSize = source.paneSize
        tab.canvasPosition = source.canvasPosition
        tab.zIndex = source.zIndex
        tab.fontSizeOverride = source.fontSizeOverride
        tab.autoInjectContext = false
        return addSession(tab, start: start, focus: focus)
    }

    var paneConnections: [PaneConnection] {
        var connections: [PaneConnection] = []
        var browserPanes: Set<UUID> = []
        for target in sessions {
            if target.kind == .cli, let source = session(target.parentSessionID), source.paneID != target.paneID {
                connections.append(PaneConnection(source: source, target: target, kind: .subagent))
            } else if target.kind == .browser, let source = session(target.agentOwnerID),
                source.paneID != target.paneID, browserPanes.insert(target.paneID).inserted
            {
                connections.append(PaneConnection(source: source, target: target, kind: .browser))
            }
        }
        return connections
    }
}
