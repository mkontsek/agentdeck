import Foundation

extension AppStore {
    /// A user action or parent removal changes the role, never the owned task or provider history.
    /// Keep a running PTY alive: its launch instructions and cached MCP catalog reload on restart.
    func promoteToMainConversation(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }),
            sessions[index].kind == .cli, sessions[index].delegatedTaskID != nil
        else { return }

        sessions[index].parentSessionID = nil
        sessions[index].delegatedTaskID = nil
        sessions[index].subagentCompleted = false
        // The original generated task includes worker-only instructions. Never replay it after promotion.
        sessions[index].initialPrompt = nil
        let promoted = sessions[index]
        expandedSubagentTabs = expandedSubagentTabs.filter { $0.value != id }
        if focusedSessionID == id {
            selectedPaneTabs[promoted.paneID] = id
            if maximizedSessionID != nil { maximizedSessionID = id }
        }
        do {
            try writeBriefing(for: promoted)
        } catch {
            lastError = "Could not refresh the main conversation briefing: \(error.localizedDescription)"
        }
        if runtime[id]?.isRunning == true {
            runtime[id]?.programMessage =
                "Promoted to main conversation. Restart this session to reload its instructions and delegation tools."
        }
        addLog(
            source: "app",
            message:
                "Promoted \(promoted.name) to a main conversation; task history retained. Restart a running CLI to refresh its role."
        )
        scheduleSave()
    }

    /// Older versions detached orphan tabs visually but persisted their worker-only role.
    func restoreOrphanedSubagents() {
        let orphanIDs = sessions.filter {
            $0.kind == .cli && $0.delegatedTaskID != nil && session($0.parentSessionID) == nil
        }.map(\.id)
        for id in orphanIDs { promoteToMainConversation(id) }
    }
}
