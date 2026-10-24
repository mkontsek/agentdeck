import Foundation

extension AppStore {
    var panes: [SessionPane] { SessionPane.grouped(sessions, selectedTabs: selectedPaneTabs) }

    func pane(containing id: UUID?) -> SessionPane? {
        guard let session = session(id) else { return nil }
        return panes.first { $0.id == session.paneID }
    }

    func cliTabSource(for id: UUID?) -> ManagedSession? {
        let target = session(id)
        return target?.kind == .cli ? target : pane(containing: id)?.tabs.first { $0.kind == .cli }
    }

    @discardableResult
    func addCLITab(to id: UUID?, start: Bool = true) -> ManagedSession? {
        guard let source = cliTabSource(for: id), let profile = profile(for: source) else { return nil }
        var number = 2
        while sessions.contains(where: { $0.name.caseInsensitiveCompare("\(profile.name) \(number)") == .orderedSame })
        {
            number += 1
        }
        var tab = ManagedSession(name: "\(profile.name) \(number)", kind: .cli)
        tab.cliProfileID = source.cliProfileID
        tab.workingDirectory = source.workingDirectory
        tab.worktreePath = source.worktreePath
        tab.worktreeBranch = source.worktreeBranch
        tab.worktreeRepo = source.worktreeRepo
        tab.paneID = source.paneID
        tab.paneSize = source.paneSize
        tab.canvasPosition = source.canvasPosition
        tab.zIndex = source.zIndex
        tab.fontSizeOverride = source.fontSizeOverride
        tab.autoInjectContext = source.autoInjectContext
        tab.autoStart = source.autoStart
        return addSession(tab, start: start)
    }

    func selectTab(_ id: UUID) {
        guard session(id) != nil else { return }
        focusedSessionID = id
    }

    func selectAdjacentTab(_ offset: Int) {
        guard let pane = pane(containing: focusedSessionID), pane.tabs.count > 1,
            let index = pane.tabs.firstIndex(where: { $0.id == pane.activeSession.id })
        else { return }
        let next = (index + offset % pane.tabs.count + pane.tabs.count) % pane.tabs.count
        selectTab(pane.tabs[next].id)
    }
}
