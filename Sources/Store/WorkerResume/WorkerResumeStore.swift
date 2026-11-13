import Foundation

extension AppStore {
    func resumeWorker(from parentID: UUID, workerID: UUID, requestID: UUID, instructions: String) throws
        -> WorkerResumeRequest
    {
        if let error = workerResumes.error { throw CoordinationError(message: error) }
        guard let worker = session(workerID), worker.parentSessionID == parentID, session(parentID) != nil,
            let taskID = worker.delegatedTaskID, let task = tasks.first(where: { $0.id == taskID }),
            task.ownerSessionID == workerID
        else {
            throw CoordinationError(
                message: "Only this worker's parent may resume its assigned task; resolve ownership or handoff first.")
        }
        if let previous = workerResumes.requests.first(where: { $0.id == requestID }) {
            guard previous.parentID == parentID, previous.workerID == workerID, previous.instructions == instructions
            else {
                throw CoordinationError(message: "request_id already belongs to a different resume payload.")
            }
            return previous
        }
        guard canDelegate(from: parentID) else { throw CoordinationError(message: "Worker orchestration is disabled.") }
        guard !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, instructions.utf8.count <= 65_536
        else {
            throw CoordinationError(message: "Provide explicit continuation instructions (1–65,536 UTF-8 bytes).")
        }
        guard task.status != .done, task.status != .awaitingApproval, task.status != .review else {
            throw CoordinationError(
                message:
                    "Task is submitted for review/approval or complete. Reopen it explicitly before resuming; resume never approves work."
            )
        }
        guard unfinishedDependencies(of: task).isEmpty,
            !handoffs.contains(where: { $0.taskID == taskID && $0.status.isOpen })
        else {
            throw CoordinationError(message: "Resolve dependencies and open handoffs before resuming.")
        }
        guard !worker.resumeStopped else {
            throw CoordinationError(
                message: "Worker was explicitly stopped. Use the user's Enable Resume action first.")
        }
        guard [.idle, .exited, .error].contains(status(of: workerID)) else {
            throw CoordinationError(
                message: "Worker is already active or waiting for input; no continuation was submitted.")
        }
        guard !workerResumes.requests.contains(where: { $0.workerID == workerID && $0.phase.reservesWorker }) else {
            throw CoordinationError(
                message:
                    "A resume is already pending, running or uncertain. Read its receipt; do not create a duplicate request."
            )
        }
        guard worker.cliProfileID == "codex", let checkpoint = resumeCheckpoint(for: worker),
            let conversationID = checkpoint.conversationID, UUID(uuidString: conversationID) != nil,
            let transport = workerResumeTransport
                ?? CodexResumeConnection.executable.map({ WorkerResumeTransport(executable: $0) })
        else {
            throw CoordinationError(
                message:
                    "Unsupported safe resume: requires Codex, an exact saved conversation identity and its existing shared app-server. No terminal input or new provider was created."
            )
        }
        guard
            activeWorkerCount(parentID: parentID, excluding: workerID)
                < SubagentLimits.clampedConcurrentWorkers(settings.maximumConcurrentSubagents)
        else {
            throw CoordinationError(message: "Concurrent worker limit reached (default 20).")
        }
        let request = WorkerResumeRequest(
            id: requestID, workerID: workerID, parentID: parentID, taskID: taskID,
            taskRevision: task.revision, generation: runtime[workerID]?.generation ?? 0,
            conversationID: conversationID, directory: worker.effectiveDirectory.expandingTilde,
            instructions: instructions)
        guard saveNow() else {
            throw CoordinationError(message: "Worker state could not persist; no continuation was accepted.")
        }
        try workerResumes.put(request)
        workerResumeRevision += 1
        workerResumeJobs[requestID] = Task.detached { [weak self] in
            await CodexWorkerResume.run(
                request, transport: transport,
                prepare: { [weak self] in
                    self?.prepareWorkerResume(request) == true
                },
                update: { [weak self] phase, turnID, queuedID, detail in
                    self?.recordWorkerResume(request, phase: phase, turnID: turnID, queuedID: queuedID, detail: detail)
                        == true
                })
            await self?.workerResumeJobFinished(requestID)
        }
        return request
    }

    func prepareWorkerResume(_ request: WorkerResumeRequest) -> Bool {
        guard let worker = session(request.workerID), worker.parentSessionID == request.parentID, !worker.resumeStopped,
            canDelegate(from: request.parentID), worker.cliProfileID == "codex",
            worker.effectiveDirectory.expandingTilde == request.directory,
            resumeCheckpoint(for: worker)?.conversationID == request.conversationID,
            [.idle, .exited, .error].contains(runtime[worker.id]?.status ?? .exited),
            runtime[worker.id]?.generation == request.generation,
            let task = tasks.first(where: { $0.id == request.taskID }), task.ownerSessionID == worker.id,
            task.revision == request.taskRevision,
            !handoffs.contains(where: { $0.taskID == task.id && $0.status.isOpen }),
            workerResumes.requests.first(where: { $0.id == request.id })?.phase == .checking
        else { return false }
        return recordWorkerResume(
            request, phase: .submitting, turnID: nil,
            detail: "Sending native provider request; start is not yet verified.")
    }

    @discardableResult
    func recordWorkerResume(
        _ original: WorkerResumeRequest, phase: WorkerResumePhase, turnID: String?, queuedID: String? = nil,
        detail: String
    ) -> Bool {
        guard var current = workerResumes.requests.first(where: { $0.id == original.id }),
            current.phase.reservesWorker
        else { return false }
        current.phase = phase
        current.turnID = turnID ?? current.turnID
        current.queuedSubmissionID = queuedID ?? current.queuedSubmissionID
        current.detail = String(detail.prefix(2048))
        current.updatedAt = Date()
        do { try workerResumes.put(current) } catch {
            lastError = "Resume receipt could not persist: \(error.localizedDescription). Do not retry."
            workerResumeJobs[original.id]?.cancel()
            return false
        }
        workerResumeRevision += 1
        let ownsTask =
            session(original.workerID)?.parentSessionID == original.parentID
            && tasks.first(where: { $0.id == original.taskID })?.ownerSessionID == original.workerID
            && runtime[original.workerID]?.generation == original.generation
        if (phase == .queued || phase == .started) && !ownsTask { return false }
        if phase == .started, ownsTask, var task = tasks.first(where: { $0.id == original.taskID }),
            [.todo, .inProgress, .blocked].contains(task.status)
        {
            task.status = .inProgress
            task.notes += "\n[AgentDeck] Explicit resume \(original.id) started provider turn \(turnID ?? "unknown")."
            updateTask(task, by: "AgentDeck")
            guard saveNow() else { return false }
        }
        if !phase.reservesWorker { workerResumeJobs[original.id] = nil }
        return true
    }

    func cancelWorkerResume(_ workerID: UUID) {
        for request in workerResumes.requests where request.workerID == workerID && request.phase.reservesWorker {
            if let job = workerResumeJobs[request.id] {
                job.cancel()
            } else if request.phase == .uncertain,
                let transport = workerResumeTransport
                    ?? CodexResumeConnection.executable.map({ WorkerResumeTransport(executable: $0) })
            {
                workerResumeJobs[request.id] = Task.detached { [weak self] in
                    do {
                        try CodexResumeRecovery.cancel(request, transport: transport)
                        await self?.recordWorkerResume(
                            request, phase: .cancelled, turnID: request.turnID,
                            detail:
                                "Reconciled: this request is absent from the provider queue and its thread is idle. Prior execution/completion is not inferred."
                        )
                    } catch {
                        await self?.recordWorkerResume(
                            request, phase: .uncertain, turnID: request.turnID, detail: error.localizedDescription)
                    }
                    await self?.workerResumeJobFinished(request.id)
                }
            }
        }
    }

    func workerResumeJobFinished(_ requestID: UUID) { workerResumeJobs[requestID] = nil }

    func enableWorkerResume(_ workerID: UUID) {
        guard var worker = session(workerID) else { return }
        worker.resumeStopped = false
        updateSession(worker)
        saveNow()
    }

    func activeWorkerCount(parentID: UUID, excluding: UUID? = nil) -> Int {
        sessions.filter { worker in
            worker.parentSessionID == parentID && worker.id != excluding
                && (!worker.subagentCompleted
                    || workerResumes.requests.contains(where: { $0.workerID == worker.id && $0.phase.reservesWorker }))
        }.count
    }
}
