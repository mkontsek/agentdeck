import Foundation

enum CodexResumeRecovery {
    /// Explicit cancellation/reconciliation only. Reads metadata and queue IDs, never turn history.
    static func cancel(_ request: WorkerResumeRequest, transport: WorkerResumeTransport) throws {
        let connection = try CodexResumeConnection(executable: transport.executable, socket: transport.socket)
        defer { connection.close() }
        try connection.initialize()
        if let turnID = request.turnID {
            // An already-ended exact turn may reject interruption; the idle check below is authoritative.
            _ = try? connection.request("turn/interrupt", ["threadId": request.conversationID, "turnId": turnID])
        }
        var cursor: String?
        var exhausted = false
        for _ in 0..<8 {
            var params: [String: Any] = ["threadId": request.conversationID, "limit": 128]
            if let cursor { params["cursor"] = cursor }
            let page = try connection.request("thread/queue/list", params)
            guard let entries = page["data"] as? [[String: Any]] else {
                throw CoordinationError(message: "Provider queue metadata could not be verified.")
            }
            for entry in entries where entry["clientUserMessageId"] as? String == request.id.uuidString {
                guard let id = entry["id"] as? String else { throw CoordinationError(message: "Queue ID missing.") }
                let result = try connection.request(
                    "thread/queue/delete", ["threadId": request.conversationID, "queuedSubmissionId": id])
                guard result["deleted"] as? Bool == true else {
                    throw CoordinationError(
                        message: "Queued continuation changed during cancellation; verify provider state again.")
                }
            }
            cursor = page["nextCursor"] as? String
            if cursor == nil {
                exhausted = true
                break
            }
        }
        guard exhausted else {
            throw CoordinationError(message: "Provider queue exceeds the bounded reconciliation limit.")
        }
        let metadata = try connection.request(
            "thread/read", ["threadId": request.conversationID, "includeTurns": false])
        guard let thread = metadata["thread"] as? [String: Any], thread["id"] as? String == request.conversationID,
            let state = thread["status"] as? [String: Any], state["type"] as? String == "idle"
        else {
            throw CoordinationError(
                message:
                    "Provider is not verifiably idle. Unknown or other turns were not interrupted; inspect the provider, then reconcile again."
            )
        }
    }
}
