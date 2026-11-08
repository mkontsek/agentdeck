import AppKit
import Foundation

struct CoordinationError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

extension AppStore {
    func showAttention() {
        settings.workspaceMode = .board
        if let handoff = handoffs.first(where: { $0.status == .awaitingApproval || $0.status == .failed }) {
            selectedTaskID = handoff.taskID
        } else if let task = tasks.first(where: {
            $0.status == .awaitingApproval || $0.status == .blocked || $0.status == .review
        }) {
            selectedTaskID = task.id
        } else if let session = sessions.first(where: {
            $0.kind == .cli && [.waitingForUser, .stalled, .quotaWarning, .error].contains(status(of: $0.id))
        }) {
            selectTab(session.id)
            settings.workspaceMode = .sessions
        }
        if recruits.contains(where: { $0.status == .pending }) { settings.showSidebar = true }
        NSApp?.activate(ignoringOtherApps: true)
        if let window = NSApp?.windows.first(where: { $0.title == "AgentDeck" }) {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        }
    }
    var attentionCount: Int {
        tasks.filter { $0.status == .awaitingApproval || $0.status == .blocked || $0.status == .review }.count
            + handoffs.filter { $0.status == .awaitingApproval || $0.status == .failed }.count
            + recruits.filter { $0.status == .pending }.count
            + sessions.filter {
                $0.kind == .cli && [.waitingForUser, .stalled, .quotaWarning, .error].contains(status(of: $0.id))
            }.count
    }

    func openTask(_ id: Int) {
        selectedTaskID = id
        settings.workspaceMode = .board
    }

    func unfinishedDependencies(of task: BoardTask) -> [Int] {
        task.dependencies.filter { id in tasks.first(where: { $0.id == id })?.status != .done }
    }

    func validateDependencies(_ ids: [Int], for taskID: Int) throws {
        var visited = Set<Int>()
        func visit(_ id: Int) throws {
            guard id != taskID else { throw CoordinationError(message: "Dependencies cannot form a cycle.") }
            guard let dependency = tasks.first(where: { $0.id == id }) else {
                throw CoordinationError(message: "Dependency #\(id) does not exist.")
            }
            guard visited.insert(id).inserted else { return }
            for child in dependency.dependencies { try visit(child) }
        }
        for id in ids { try visit(id) }
    }

    @discardableResult
    func createTask(
        title: String, description: String = "", owner: UUID? = nil, status: TaskStatus = .todo,
        notes: String = "", createdBy: String = "user", creatorID: UUID? = nil
    ) -> BoardTask {
        var task = BoardTask(
            id: nextTaskID, title: title, description: description, ownerSessionID: owner,
            status: status, notes: notes, createdBy: createdBy)
        task.createdBySessionID = creatorID
        if creatorID != nil, status == .done { task.status = .awaitingApproval }
        task.events = [TaskEvent(actor: createdBy, message: "Created task")]
        nextTaskID += 1
        tasks.append(task)
        addLog(source: createdBy, message: "task #\(task.id) created: \(title)")
        scheduleSave()
        return task
    }

    func updateTask(_ task: BoardTask, by source: String = "user") {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let old = tasks[index]
        var next = task
        next.events = old.events
        var changes: [String] = []
        if old.status != next.status { changes.append("\(old.status.label) → \(next.status.label)") }
        if old.ownerSessionID != next.ownerSessionID {
            changes.append("Owner → \(next.ownerSessionID.map(name(of:)) ?? "Unassigned")")
        }
        if old.notes != next.notes { changes.append("Updated shared notes") }
        if old.description != next.description || old.title != next.title { changes.append("Updated task brief") }
        if old.dependencies != next.dependencies { changes.append("Updated dependencies") }
        if old.requiresApproval != next.requiresApproval { changes.append("Changed completion approval requirement") }
        guard !changes.isEmpty else { return }
        next.updatedAt = Date()
        next.revision = old.revision + 1
        next.events.append(TaskEvent(actor: source, message: changes.joined(separator: " · ")))
        tasks[index] = next
        subagentTaskDidChange(next)
        addLog(source: source, message: "task #\(task.id): \(changes.joined(separator: "; "))")
        scheduleSave()
    }

    func deleteTask(_ id: Int) {
        guard !tasks.contains(where: { $0.dependencies.contains(id) }) else {
            lastError = "Other tasks depend on #\(id). Remove those dependencies first."
            return
        }
        for transfer in handoffs where transfer.taskID == id && transfer.status.isOpen {
            transitionHandoff(transfer.id, to: .cancelled, detail: "Task deleted", actor: "user")
        }
        tasks.removeAll { $0.id == id }
        if selectedTaskID == id { selectedTaskID = nil }
        scheduleSave()
    }

    func canEditTask(_ task: BoardTask, caller: UUID) -> Bool {
        task.ownerSessionID == caller || (task.ownerSessionID == nil && task.createdBySessionID == caller)
            || session(caller)?.isOrchestrator == true
    }

    func transitionHandoff(_ id: UUID, to status: HandoffStatus, detail: String, actor: String) {
        guard let index = handoffs.firstIndex(where: { $0.id == id }) else { return }
        handoffs[index].status = status
        handoffs[index].detail = detail
        handoffs[index].updatedAt = Date()
        handoffs[index].events.append(TaskEvent(actor: actor, message: "\(status.label): \(detail)"))
        scheduleSave()
    }

    @discardableResult
    func handoff(
        from caller: UUID?, to target: ManagedSession, taskID: Int?, title: String?, description: String?,
        note: String?, constraints: String = "", artifacts: [String] = [], verification: String = "",
        nextAction: String = "Review the shared context and continue the task."
    ) throws -> (task: BoardTask, delivered: Bool, handoff: TaskHandoff) {
        guard target.kind == .cli, profile(for: target)?.supportsMCP == true else {
            throw CoordinationError(message: "Choose a CLI session with MCP enabled so it can acknowledge the handoff.")
        }
        let source = caller.map(name(of:)) ?? "user"
        var task: BoardTask
        if let taskID {
            guard let existing = tasks.first(where: { $0.id == taskID }) else {
                throw CoordinationError(message: "Unknown task #\(taskID).")
            }
            task = existing
            if let caller, !canEditTask(task, caller: caller) {
                throw CoordinationError(message: "Only the owner or an orchestrator can hand off this task.")
            }
        } else if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            task = createTask(
                title: title, description: description ?? "", owner: caller, createdBy: source, creatorID: caller)
        } else {
            throw CoordinationError(message: "A handoff needs task_id or title.")
        }
        guard !handoffs.contains(where: { $0.taskID == task.id && $0.status.isOpen }) else {
            throw CoordinationError(message: "This task already has an open handoff. Resolve or cancel it first.")
        }
        let context = HandoffContext(
            objective: description ?? task.description, sharedNotes: task.notes, summary: note ?? "",
            constraints: constraints, artifacts: artifacts, verification: verification, nextAction: nextAction)
        var transfer = TaskHandoff(
            taskID: task.id, taskTitle: task.title, taskRevision: task.revision, previousOwnerID: task.ownerSessionID,
            fromSessionID: caller, fromName: source, targetSessionID: target.id, targetName: target.name,
            context: context, status: caller != nil && settings.approveAgentHandoffs ? .awaitingApproval : .queued)
        transfer.events = [TaskEvent(actor: source, message: "Prepared handoff to \(target.name)")]
        handoffs.append(transfer)
        scheduleSave()
        if transfer.status == .queued { deliverNextHandoff(to: target.id) }
        return (task, false, handoffs.first(where: { $0.id == transfer.id }) ?? transfer)
    }

    func approveHandoff(_ id: UUID) {
        guard let transfer = handoffs.first(where: { $0.id == id }), transfer.status == .awaitingApproval else {
            return
        }
        transitionHandoff(id, to: .queued, detail: "User approved shared context", actor: "user")
        deliverNextHandoff(to: transfer.targetSessionID)
    }

    func retryHandoff(_ id: UUID) {
        guard let transfer = handoffs.first(where: { $0.id == id }),
            transfer.status == .failed || transfer.status == .delivered,
            session(transfer.targetSessionID) != nil
        else { return }
        transitionHandoff(id, to: .queued, detail: "User requested redelivery", actor: "user")
        deliverNextHandoff(to: transfer.targetSessionID)
    }

    func deliverNextHandoff(to targetID: UUID) {
        guard let transfer = handoffs.first(where: { $0.targetSessionID == targetID && $0.status == .queued }) else {
            return
        }
        guard let target = session(targetID), profile(for: target)?.supportsMCP == true else {
            transitionHandoff(transfer.id, to: .failed, detail: "Target is missing or MCP is disabled", actor: "app")
            return
        }
        let message =
            "[AgentDeck handoff] Task #\(transfer.taskID): \(transfer.taskTitle). Read the published context with read_handoffs(handoff_id=\"\(transfer.id)\"), then explicitly accept or decline with accept_handoff. Ownership changes only on acceptance."
        if queueCoordination(targetID, text: message, source: "handoff", key: "handoff:\(transfer.id)") != nil {
            transitionHandoff(
                transfer.id, to: .delivered,
                detail: "Accepted into recipient inbox; awaiting acknowledgment and acceptance", actor: "app")
        } else {
            transitionHandoff(
                transfer.id, to: .failed, detail: "Inbox did not accept notification; published context retained",
                actor: "app")
        }
    }

    func acceptHandoff(_ id: UUID, caller: UUID, accept: Bool, reason: String = "") throws {
        guard let transfer = handoffs.first(where: { $0.id == id }), transfer.targetSessionID == caller else {
            throw CoordinationError(message: "Only the named recipient can acknowledge this handoff.")
        }
        // Idempotent acknowledgment makes retries safe after a lost MCP response.
        if accept && transfer.status == .accepted { return }
        guard
            transfer.status == .queued || transfer.status == .delivering || transfer.status == .delivered
                || transfer.status == .failed
        else {
            throw CoordinationError(message: "This handoff is not approved or is already closed.")
        }
        if !accept {
            transitionHandoff(
                id, to: .declined, detail: reason.isEmpty ? "Recipient declined" : reason, actor: name(of: caller))
            return
        }
        guard var task = tasks.first(where: { $0.id == transfer.taskID }),
            task.ownerSessionID == transfer.previousOwnerID,
            task.revision == transfer.taskRevision
        else {
            throw CoordinationError(message: "Task changed since this handoff. Cancel it and prepare fresh context.")
        }
        guard unfinishedDependencies(of: task).isEmpty else {
            throw CoordinationError(message: "Complete the task dependencies before accepting work.")
        }
        task.ownerSessionID = caller
        task.status = .inProgress
        updateTask(task, by: name(of: caller))
        transitionHandoff(
            id, to: .accepted, detail: reason.isEmpty ? "Recipient accepted responsibility" : reason,
            actor: name(of: caller))
    }
}
