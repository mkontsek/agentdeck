import Foundation

extension AppStore {
    var workerResumeToolDefinitions: [[String: Any]] {
        [
            [
                "name": "resume_worker",
                "description":
                    "Explicitly continue your own idle assigned worker without terminal input. Supported: exact saved Codex thread already loaded in its shared app-server. Other providers/standalone or unknown threads fail safely. Returns checking (accepted only); read worker_resume_status until started, ended, failed or uncertain. Reuse request_id and identical instructions on retries. Never replay uncertain requests; never approves or auto-resumes tasks.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "worker_id": ["type": "string"], "request_id": ["type": "string"],
                        "instructions": ["type": "string"],
                    ], "required": ["worker_id", "request_id", "instructions"], "additionalProperties": false,
                ],
            ],
            [
                "name": "worker_resume_status",
                "description":
                    "Read a resume receipt. started means a provider acknowledged a turn; ended is not task completion. Unknown outcomes must never be blindly replayed.",
                "inputSchema": [
                    "type": "object", "properties": ["request_id": ["type": "string"]], "required": ["request_id"],
                    "additionalProperties": false,
                ],
            ],
            [
                "name": "cancel_worker_resume",
                "description":
                    "Cancel your own explicit continuation. Interruption targets only its verified provider turn ID. After restart/uncertainty, explicitly reconcile: remove only this request's queue entry and require the provider thread to be idle. Other or unknown active turns are not interrupted. Read the receipt; acceptance is not verified cancellation.",
                "inputSchema": [
                    "type": "object", "properties": ["request_id": ["type": "string"]], "required": ["request_id"],
                    "additionalProperties": false,
                ],
            ],
        ]
    }

    func workerResumeTool(name: String, args: [String: Any], caller: UUID) -> ToolResult? {
        guard ["resume_worker", "worker_resume_status", "cancel_worker_resume"].contains(name) else { return nil }
        do {
            guard let rawID = args["request_id"] as? String, let id = UUID(uuidString: rawID) else {
                throw CoordinationError(
                    message: "request_id must be a caller-generated UUID, reused unchanged on retry.")
            }
            let request: WorkerResumeRequest
            if name == "resume_worker" {
                guard let rawWorker = args["worker_id"] as? String, let workerID = UUID(uuidString: rawWorker),
                    let instructions = args["instructions"] as? String
                else {
                    throw CoordinationError(message: "worker_id UUID and explicit instructions are required.")
                }
                request = try resumeWorker(from: caller, workerID: workerID, requestID: id, instructions: instructions)
            } else {
                guard let existing = workerResumes.requests.first(where: { $0.id == id }), existing.parentID == caller,
                    session(existing.workerID)?.parentSessionID == caller,
                    tasks.first(where: { $0.id == existing.taskID })?.ownerSessionID == existing.workerID
                else {
                    throw CoordinationError(
                        message: "Only the current parent/owner may read or cancel this worker's resume.")
                }
                if name == "cancel_worker_resume", existing.phase.reservesWorker {
                    cancelWorkerResume(existing.workerID)
                }
                request = existing
            }
            return ToolResult(text: String(decoding: try JSONEncoder().encode(request), as: UTF8.self))
        } catch { return ToolResult(text: error.localizedDescription, isError: true) }
    }
}
