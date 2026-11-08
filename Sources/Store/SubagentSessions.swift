import Foundation

extension AppStore {
    func parentConversationID(for session: ManagedSession) -> UUID? {
        if let id = session.parentSessionID, self.session(id) != nil { return id }
        if let ownerID = session.agentOwnerID, let owner = self.session(ownerID),
            let parent = owner.parentSessionID, self.session(parent) != nil
        {
            return parent
        }
        return nil
    }

    func canDelegate(from id: UUID?) -> Bool {
        guard settings.automaticSubagents, let parent = session(id), parent.kind == .cli,
            parent.parentSessionID == nil, parent.delegatedTaskID == nil, profile(for: parent)?.supportsMCP == true
        else { return false }
        return true
    }

    /// Creates a fresh worker without moving focus or waiting for its task to finish.
    @discardableResult
    func delegateTask(
        from parentID: UUID, taskID: Int? = nil, title: String = "", instructions: String = "",
        profileID: String? = nil, start: Bool = true
    ) throws -> ManagedSession {
        guard canDelegate(from: parentID), let parent = session(parentID) else {
            throw CoordinationError(
                message:
                    "Automatic subagents are disabled, or this session cannot delegate. Subagents cannot spawn more subagents."
            )
        }
        guard title.count <= 200, instructions.count <= 65_536 else {
            throw CoordinationError(
                message: "Keep the title within 200 characters and the task brief within 65,536 characters.")
        }
        let selectedProfile = profileID ?? parent.cliProfileID
        guard let profile = cliProfiles.first(where: { $0.id == selectedProfile }), profile.supportsMCP else {
            throw CoordinationError(message: "Choose an MCP-enabled CLI profile for the subagent.")
        }
        var task: BoardTask?
        if let taskID {
            guard let existing = tasks.first(where: { $0.id == taskID }) else {
                throw CoordinationError(message: "Unknown task_id.")
            }
            if let child = sessions.first(where: { $0.parentSessionID == parentID && $0.delegatedTaskID == taskID }),
                existing.ownerSessionID == child.id
            {
                return child
            }
            guard existing.ownerSessionID == nil || existing.ownerSessionID == parentID else {
                throw CoordinationError(
                    message:
                        "Only your own or unassigned tasks can be delegated. Other agents' work requires a handoff.")
            }
            guard !handoffs.contains(where: { $0.taskID == taskID && $0.status.isOpen }) else {
                throw CoordinationError(message: "Resolve the open handoff before delegating this task.")
            }
            guard existing.status == .todo || existing.status == .inProgress || existing.status == .blocked else {
                throw CoordinationError(
                    message:
                        "This task is already submitted for review or complete. Create a new task for further work.")
            }
            guard unfinishedDependencies(of: existing).isEmpty else {
                throw CoordinationError(message: "Complete this task's dependencies before delegating it.")
            }
            task = existing
        } else if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            throw CoordinationError(message: "A new delegated task needs a title and concrete instructions.")
        }
        let children = sessions.filter { $0.parentSessionID == parentID }
        guard children.count < SubagentLimits.retainedTabs else {
            throw CoordinationError(
                message:
                    "Close an old subagent window before creating another (\(SubagentLimits.retainedTabs)-worker limit)."
            )
        }
        guard
            children.filter({ !$0.subagentCompleted }).count
                < SubagentLimits.clampedConcurrentWorkers(settings.maximumConcurrentSubagents)
        else {
            throw CoordinationError(
                message:
                    "The concurrent subagent limit is reached. Keep the main conversation available; wait for a result notification before delegating more work."
            )
        }
        var child = ManagedSession(name: "", kind: .cli)
        child.cliProfileID = profile.id
        child.workingDirectory = parent.workingDirectory
        child.worktreePath = parent.worktreePath
        child.worktreeBranch = parent.worktreeBranch
        child.worktreeRepo = parent.worktreeRepo
        child.paneSize = parent.paneSize
        child.canvasPosition = connectedPanePosition(after: parent, size: paneSize(for: child))
        child.zIndex = parent.zIndex
        child.fontSizeOverride = parent.fontSizeOverride
        child.parentSessionID = parentID
        child.resumeLastConversation = false
        child.resumeOnRestart = true
        if task == nil {
            task = createTask(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines), description: instructions,
                owner: parentID, createdBy: parent.name, creatorID: parentID)
        }
        guard var delegated = task else { throw CoordinationError(message: "Could not create the delegated task.") }
        child.name = "#\(delegated.id) \(delegated.title.prefix(48))"
        child.delegatedTaskID = delegated.id
        child.initialPrompt = """
            Work on task #\(delegated.id): \(delegated.title).
            Objective: \(delegated.description)
            Published notes: \(delegated.notes)
            Additional instructions: \(instructions)
            This is your complete handoff; do not scrape the parent's private conversation.
            Stay within the task's file scope; other workers may share this directory. Coordinate overlapping edits with the parent.
            When finished, call report_subagent_result with a concise summary, changed files, verification and limitations. Set blocked=true if user input is required. Do not spawn more agents or approve your own completion.
            """
        addSession(child, start: false, focus: false)
        delegated.ownerSessionID = child.id
        delegated.status = .inProgress
        updateTask(delegated, by: parent.name)
        if start { startSession(child.id) }
        addLog(source: parent.name, message: "delegated task #\(delegated.id) to \(child.name)")
        return session(child.id) ?? child
    }

    func reportSubagentResult(caller: UUID, summary: String, blocked: Bool) throws {
        guard let child = session(caller),
            let id = child.delegatedTaskID, var task = tasks.first(where: { $0.id == id }),
            task.ownerSessionID == caller
        else {
            throw CoordinationError(message: "Only the assigned subagent may report this result.")
        }
        let summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty, summary.count <= 65_536 else {
            throw CoordinationError(message: "A result summary of at most 65,536 characters is required.")
        }
        if child.subagentCompleted {
            guard queueSubagentNotification(task, child: child) else {
                throw CoordinationError(
                    message: "Result is on the board but inbox acceptance failed; retry report_subagent_result.")
            }
            return
        }
        task.notes += "\n[\(child.name)] \(summary)"
        task.status = blocked ? .blocked : (task.requiresApproval ? .awaitingApproval : .review)
        updateTask(task, by: child.name)
        saveNow()
        if let published = tasks.first(where: { $0.id == task.id }), !queueSubagentNotification(published, child: child)
        {
            throw CoordinationError(
                message: "Result is on the board but inbox acceptance failed; retry report_subagent_result.")
        }
    }

    func subagentTaskDidChange(_ task: BoardTask) {
        guard let index = sessions.firstIndex(where: { $0.id == task.ownerSessionID && $0.delegatedTaskID == task.id })
        else { return }
        let submitted = [.review, .awaitingApproval, .done, .blocked].contains(task.status)
        guard submitted != sessions[index].subagentCompleted else { return }
        sessions[index].subagentCompleted = submitted
        guard submitted else { return }
        _ = queueSubagentNotification(task, child: sessions[index])
    }

    @discardableResult
    func queueSubagentNotification(_ task: BoardTask, child: ManagedSession) -> Bool {
        guard let parentID = child.parentSessionID else { return true }
        let key = "task:\(task.id):revision:\(task.revision)"
        if inbox.events.contains(where: { $0.targetID == parentID && $0.key == key }) { return true }
        let message =
            "[AgentDeck subagent] Task #\(task.id) \(task.title) is \(task.status.label). \(String(task.notes.suffix(6000))). Read the task's published evidence; keep the main conversation available for the user."
        return queueCoordination(
            parentID, text: message, source: child.name, key: key) != nil
    }

    func subagentStopped(_ id: UUID, reason: String) {
        guard let child = session(id), !child.subagentCompleted,
            let taskID = child.delegatedTaskID, var task = tasks.first(where: { $0.id == taskID }),
            task.ownerSessionID == id
        else { return }
        task.notes += "\n[AgentDeck] Worker stopped before reporting a result: \(reason)"
        task.status = .blocked
        updateTask(task, by: "AgentDeck")
    }

    func subagentBriefing(for session: ManagedSession) -> String {
        if session.delegatedTaskID != nil {
            return
                "You are a task subagent. Work only on your assigned task; report through report_subagent_result. Do not delegate or recruit more agents."
        }
        guard session.kind == .cli else { return "" }
        let mainRole =
            "You are the main conversation, not a task subagent. Earlier worker-only instructions no longer apply. Keep existing task ownership and completion approval requirements. "
        guard canDelegate(from: session.id) else { return mainRole }
        return
            mainRole
            + "Automatic subagents are enabled. For substantial implementation or research work, call delegate_task with a concrete scope and instructions, then promptly end your turn so this main conversation remains ready for new prompts. Keep quick answers here. Do not block waiting or repeatedly poll; workers report results back. Respect any user instruction to work directly. Workers and their owned browsers appear in separate connected mini-windows."
    }
}
