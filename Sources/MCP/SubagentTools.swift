import Foundation

extension AppStore {
    func subagentToolDefinitions(caller: UUID?) -> [[String: Any]] {
        guard let caller, let session = session(caller) else { return [] }
        if session.delegatedTaskID != nil {
            return [
                [
                    "name": "report_subagent_result",
                    "description":
                        "Publish your task result and notify the parent conversation without waiting. Completion approval stays with the user.",
                    "inputSchema": [
                        "type": "object",
                        "properties": ["summary": ["type": "string"], "blocked": ["type": "boolean"]],
                        "required": ["summary"], "additionalProperties": false,
                    ],
                ]
            ]
        }
        guard canDelegate(from: caller) else { return [] }
        return [
            [
                "name": "delegate_task",
                "description":
                    "Start a managed subagent mini-window for substantial work and return immediately. Give clear scope, constraints and expected evidence; then end your main turn so the user can keep prompting. Results are queued durably and attached to your next AgentDeck tool result; idle CLIs are not woken. Repeated calls for the same task_id reuse its worker. Cannot transfer another agent's work or bypass a pending handoff.",
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
        do {
            switch name {
            case "delegate_task":
                if args["task_id"] != nil && args["task_id"] as? Int == nil {
                    throw CoordinationError(message: "task_id must be an integer.")
                }
                let child = try delegateTask(
                    from: caller, taskID: args["task_id"] as? Int, title: args["title"] as? String ?? "",
                    instructions: args["instructions"] as? String ?? "", profileID: args["cli_profile"] as? String)
                let result: [String: Any] = [
                    "session_id": child.id.uuidString, "task_id": child.delegatedTaskID ?? 0,
                    "name": child.name,
                    "result_submitted": child.subagentCompleted,
                    "status": status(of: child.id).label,
                    "note":
                        "Worker assigned in a connected mini-window (an existing task reuses its worker). End this turn; keep the main conversation available. Results enter your durable inbox and appear on your next AgentDeck tool call; check the board if result_submitted is true.",
                ]
                return ToolResult(
                    text: String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self))
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
