import Foundation

/// A mini-window groups independently owned sessions without changing their orchestration identities.
struct SessionPane: Identifiable {
    let id: UUID
    var tabs: [ManagedSession]
    var activeSession: ManagedSession

    var showsTabBar: Bool { tabs.count > 1 || tabs.contains { $0.kind == .cli } }

    static func grouped(_ sessions: [ManagedSession], selectedTabs: [UUID: UUID]) -> [SessionPane] {
        var panes: [SessionPane] = []
        var indices: [UUID: Int] = [:]
        for session in sessions {
            if let index = indices[session.paneID] {
                panes[index].tabs.append(session)
                if selectedTabs[session.paneID] == session.id { panes[index].activeSession = session }
            } else {
                indices[session.paneID] = panes.count
                panes.append(SessionPane(id: session.paneID, tabs: [session], activeSession: session))
            }
        }
        return panes
    }
}
