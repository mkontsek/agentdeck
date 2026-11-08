import Foundation

extension AppStore {
    func coordinationToolDefinitions() -> [[String: Any]] {
        let string: [String: Any] = ["type": "string"]
        return [
            [
                "name": "read_handoffs",
                "description":
                    "Read published handoff packages and delivery history. No terminal transcripts are included.",
                "inputSchema": ["type": "object", "properties": ["handoff_id": string], "additionalProperties": false],
            ],
            [
                "name": "accept_handoff",
                "description":
                    "Recipient explicitly accepts responsibility or declines an approved handoff. Acceptance changes task ownership; repeated acceptance is safe.",
                "inputSchema": [
                    "type": "object",
                    "properties": ["handoff_id": string, "accept": ["type": "boolean"], "reason": string],
                    "required": ["handoff_id", "accept"], "additionalProperties": false,
                ],
            ],
        ]
    }

    func coordinationTool(name: String, args: [String: Any], caller: UUID) -> ToolResult? {
        switch name {
        case "read_handoffs":
            var visible = handoffs.filter {
                $0.fromSessionID == caller
                    || ($0.status != .awaitingApproval
                        && ($0.targetSessionID == caller || session(caller)?.isOrchestrator == true))
            }
            if let ref = args["handoff_id"] as? String {
                guard let id = UUID(uuidString: ref), let item = visible.first(where: { $0.id == id }) else {
                    return ToolResult(
                        text: "Handoff is unknown, awaiting user approval, or caller is not a participant.",
                        isError: true)
                }
                visible = [item]
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(visible) else {
                return ToolResult(text: "Could not encode handoffs", isError: true)
            }
            return ToolResult(text: String(decoding: data, as: UTF8.self))
        case "accept_handoff":
            guard let ref = args["handoff_id"] as? String, let id = UUID(uuidString: ref),
                let accept = args["accept"] as? Bool
            else {
                return ToolResult(text: "handoff_id and accept are required", isError: true)
            }
            do {
                try acceptHandoff(id, caller: caller, accept: accept, reason: args["reason"] as? String ?? "")
                return ToolResult(
                    text: accept ? "Accepted; task ownership transferred." : "Declined; ownership unchanged.")
            } catch { return ToolResult(text: error.localizedDescription, isError: true) }
        default: return nil
        }
    }

    func updateTaskFromAgent(_ args: [String: Any], caller: UUID) throws -> BoardTask {
        guard let id = args["task_id"] as? Int, var task = tasks.first(where: { $0.id == id }) else {
            throw CoordinationError(message: "Unknown task_id.")
        }
        let claiming = task.ownerSessionID == nil && (args["owner"] as? String)?.lowercased() == "me"
        guard canEditTask(task, caller: caller) || claiming else {
            throw CoordinationError(
                message: "Only the owner or an orchestrator may update this task. Claim unassigned work with owner=me.")
        }
        if let owner = args["owner"] as? String {
            let requested =
                owner.lowercased() == "none" || owner.isEmpty ? nil : resolveSession(owner, from: caller)?.id
            if requested == nil && owner.lowercased() != "none" && !owner.isEmpty {
                throw CoordinationError(message: "Unknown owner.")
            }
            guard requested == nil || requested == caller || requested == task.ownerSessionID else {
                throw CoordinationError(message: "Use handoff to transfer work to another session.")
            }
            if requested != task.ownerSessionID,
                handoffs.contains(where: { $0.taskID == id && $0.status.isOpen })
            {
                throw CoordinationError(message: "Resolve the open handoff before changing ownership.")
            }
            task.ownerSessionID = requested
        }
        if let value = args["status"] as? String {
            guard let status = TaskStatus(rawValue: value) else { throw CoordinationError(message: "Invalid status.") }
            task.status = status == .done && task.requiresApproval ? .awaitingApproval : status
        }
        if let dependencies = args["dependencies"] as? [Int] {
            try validateDependencies(dependencies, for: id)
            task.dependencies = Array(Set(dependencies)).sorted()
        }
        if task.status == .inProgress || task.status == .review || task.status == .awaitingApproval
            || task.status == .done
        {
            guard unfinishedDependencies(of: task).isEmpty else {
                throw CoordinationError(message: "Dependencies are incomplete: \(unfinishedDependencies(of: task)).")
            }
        }
        if let note = args["notes"] as? String, !note.isEmpty { task.notes += "\n[\(name(of: caller))] \(note)" }
        if let title = args["title"] as? String, !title.isEmpty { task.title = title }
        if let description = args["description"] as? String { task.description = description }
        updateTask(task, by: name(of: caller))
        return tasks.first(where: { $0.id == id }) ?? task
    }
}
