import Foundation

extension AppStore {
    func subagentToolDefinitions(caller: UUID?) -> [[String: Any]] {
        guard let caller, let session = session(caller) else { return [] }
        if session.delegatedTaskID != nil {
            return [
                [
                    "name": "report_subagent_progress",
                    "description":
                        "Publish an unfinished checkpoint. Keeps task in progress, never submits completion, never wakes an idle parent.",
                    "inputSchema": [
                        "type": "object", "properties": ["summary": ["type": "string"]], "required": ["summary"],
                        "additionalProperties": false,
                    ],
                ],
                [
                    "name": "report_subagent_result",
                    "description":
                        "Publish your task result and notify the parent conversation without waiting. Completion approval stays with the user.",
                    "inputSchema": [
                        "type": "object",
                        "properties": ["summary": ["type": "string"], "blocked": ["type": "boolean"]],
                        "required": ["summary"], "additionalProperties": false,
                    ],
                ],
            ]
        }
        guard canDelegate(from: caller) else { return [] }
        return workerResumeToolDefinitions + [
            [
                "name": "delegate_task",
                "description":
                    "Assign a managed worker and return immediately. Repeated task_id calls return its identity without starting work; supplied continuation instructions are rejected with resume_worker guidance. Use resume_worker for explicit native continuation and read its receipt. Inbox acceptance never means execution. Cannot transfer another agent's work or bypass handoffs.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "task_id": ["type": "integer"], "title": ["type": "string"], "instructions": ["type": "string"],
                        "cli_profile": ["type": "string"],
                    ], "additionalProperties": false,
                ],
            ]
        ]
    }

    func subagentTool(name: String, args: [String: Any], caller: UUID) -> ToolResult? {
        if let result = workerResumeTool(name: name, args: args, caller: caller) { return result }
        do {
            switch name {
            case "delegate_task":
                if args["task_id"] != nil && args["task_id"] as? Int == nil {
                    throw CoordinationError(message: "task_id must be an integer.")
                }
                let child = try delegateTask(
                    from: caller, taskID: args["task_id"] as? Int, title: args["title"] as? String ?? "",
                    instructions: args["instructions"] as? String ?? "", profileID: args["cli_profile"] as? String)
                let task = tasks.first { $0.id == child.delegatedTaskID }
                let result: [String: Any] = [
                    "session_id": child.id.uuidString, "task_id": child.delegatedTaskID ?? 0,
                    "name": child.name,
                    "result_submitted": task.map { [.review, .awaitingApproval, .done].contains($0.status) } ?? false,
                    "task_status": task?.status.rawValue ?? "unknown",
                    "status": status(of: child.id).label,
                    "note":
                        "Worker identity returned. An existing worker was NOT resumed. Use resume_worker for continuation; only its started receipt verifies a provider turn. Inbox messages do not start turns.",
                ]
                return ToolResult(
                    text: String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self))
            case "report_subagent_progress":
                try reportSubagentProgress(caller: caller, summary: args["summary"] as? String ?? "")
                return ToolResult(
                    text:
                        "Unfinished checkpoint published. Task stays in progress; notification accepted into the parent inbox, not a provider turn."
                )
            case "report_subagent_result":
                try reportSubagentResult(
                    caller: caller, summary: args["summary"] as? String ?? "",
                    blocked: args["blocked"] as? Bool ?? false)
                return ToolResult(
                    text:
                        "Result published; the notification is queued in the parent inbox. Evidence remains on the board. User completion approval is unchanged."
                )
            default: return nil
            }
        } catch { return ToolResult(text: error.localizedDescription, isError: true) }
    }
}
