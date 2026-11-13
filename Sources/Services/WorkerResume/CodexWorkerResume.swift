import Foundation

struct WorkerResumeTransport: Sendable {
    var executable: String
    var socket: String?
}

enum CodexWorkerResume {
    /// All blocking pipe/process operations run on the detached worker, never on the main actor.
    static func run(
        _ request: WorkerResumeRequest, transport: WorkerResumeTransport,
        prepare: @escaping @MainActor @Sendable () -> Bool,
        update: @escaping @MainActor @Sendable (WorkerResumePhase, String?, String?, String) -> Bool
    ) async {
        var submitted = false
        var turnID: String?
        var queuedID: String?
        do {
            let connection = try CodexResumeConnection(executable: transport.executable, socket: transport.socket)
            defer { connection.close() }
            try connection.initialize()
            let metadata = try connection.request(
                "thread/read", ["threadId": request.conversationID, "includeTurns": false])
            try validate(metadata, request: request)
            // Subscribe to the SAME already-loaded provider. Never hydrate an unloaded thread alongside a TUI.
            let joined = try connection.request(
                "thread/resume", ["threadId": request.conversationID, "excludeTurns": true])
            try validate(joined, request: request)
            try Task.checkCancellation()
            guard await prepare() else { throw CancellationError() }
            try Task.checkCancellation()
            submitted = true
            let queued = try connection.request(
                "thread/queue/add",
                [
                    "threadId": request.conversationID, "clientUserMessageId": request.id.uuidString,
                    "input": [["type": "text", "text": request.instructions]],
                ])
            guard let submission = queued["queuedSubmission"] as? [String: Any],
                let queueID = submission["id"] as? String,
                submission["clientUserMessageId"] as? String == request.id.uuidString
            else {
                throw CoordinationError(message: "Provider queue identity could not be verified.")
            }
            queuedID = queueID
            guard
                await update(
                    .queued, nil, queueID, "Provider accepted this exact queued submission; no turn start is claimed.")
            else {
                throw CancellationError()
            }
            try Task.checkCancellation()
            let id = try startQueued(connection, request: request, queueID: queueID)
            turnID = id
            guard
                await update(
                    .started, id, queueID, "Provider acknowledged turn \(id). This is execution, not task completion.")
            else {
                throw CancellationError()
            }
            let deadline = Date().addingTimeInterval(3600)
            while Date() < deadline {
                let event = try connection.nextEvent(deadline: deadline)
                guard event["method"] as? String == "turn/completed",
                    let params = event["params"] as? [String: Any],
                    params["threadId"] as? String == request.conversationID,
                    let completed = params["turn"] as? [String: Any], completed["id"] as? String == id
                else { continue }
                let status = completed["status"] as? String ?? "unknown"
                _ = await update(
                    .ended, id, queueID,
                    "Provider turn ended (\(status)); task remains unfinished unless explicitly reported as a result.")
                return
            }
            throw CoordinationError(message: "Turn observation timed out; inspect the provider before retrying.")
        } catch {
            if error is CodexResumeRPCError, queuedID == nil {
                _ = await update(
                    .failed, nil, nil,
                    "Provider rejected continuation before queue acceptance: \(error.localizedDescription)")
            } else if error is CancellationError, !submitted {
                _ = await update(.cancelled, nil, nil, "Cancelled before provider submission; no turn started.")
            } else if error is CancellationError, let turnID {
                let cancelled = await Task.detached {
                    interrupt(request.conversationID, turnID: turnID, transport: transport)
                }.value
                _ = await update(
                    cancelled ? .cancelled : .uncertain, turnID, queuedID,
                    cancelled
                        ? "Provider confirmed interruption of this exact turn."
                        : "Cancellation could not be verified. Do not replay this request.")
            } else if let queuedID, turnID == nil {
                let deleted = await Task.detached {
                    deleteQueued(request.conversationID, queuedID: queuedID, transport: transport)
                }.value
                _ = await update(
                    deleted ? .failed : .uncertain, nil, queuedID,
                    deleted
                        ? "Continuation did not start; its exact queued input was removed. \(error.localizedDescription)"
                        : "Queue/start outcome is uncertain; no replay. \(error.localizedDescription)")
            } else {
                _ = await update(
                    submitted ? .uncertain : .failed, turnID, queuedID,
                    submitted
                        ? "Submission outcome is uncertain: \(error.localizedDescription). Do not retry with a new ID."
                        : error.localizedDescription)
            }
        }
    }

    private static func startQueued(_ connection: CodexResumeConnection, request: WorkerResumeRequest, queueID: String)
        throws -> String
    {
        do {
            let receipt = try connection.request(
                "thread/queue/start", ["threadId": request.conversationID, "queuedSubmissionId": queueID])
            guard let turn = receipt["turn"] as? [String: Any], let id = turn["id"] as? String, !id.isEmpty,
                turn["status"] as? String == "inProgress"
            else {
                throw CoordinationError(message: "Provider did not return a verified running turn identity.")
            }
            return id
        } catch let error as CodexResumeRPCError where error.message.contains("queued submission not found") {
            // An attached TUI may consume the native queue first. Never start a duplicate: require
            // the provider's live userMessage event carrying OUR client ID and its actual turn ID.
            let deadline = Date().addingTimeInterval(15)
            while Date() < deadline {
                let event = try connection.nextEvent(deadline: deadline)
                guard let params = event["params"] as? [String: Any],
                    params["threadId"] as? String == request.conversationID,
                    let item = params["item"] as? [String: Any], item["type"] as? String == "userMessage",
                    item["clientId"] as? String == request.id.uuidString,
                    let id = params["turnId"] as? String
                else { continue }
                return id
            }
            throw CoordinationError(
                message: "Native queue was consumed, but this request's actual turn could not be verified.")
        }
    }

    private static func deleteQueued(_ threadID: String, queuedID: String, transport: WorkerResumeTransport) -> Bool {
        do {
            let connection = try CodexResumeConnection(executable: transport.executable, socket: transport.socket)
            defer { connection.close() }
            try connection.initialize()
            let result = try connection.request(
                "thread/queue/delete", ["threadId": threadID, "queuedSubmissionId": queuedID])
            return result["deleted"] as? Bool == true
        } catch { return false }
    }

    private static func validate(_ response: [String: Any], request: WorkerResumeRequest) throws {
        guard let thread = response["thread"] as? [String: Any], thread["id"] as? String == request.conversationID,
            let cwd = thread["cwd"] as? String,
            URL(fileURLWithPath: cwd).standardizedFileURL.path
                == URL(fileURLWithPath: request.directory).standardizedFileURL.path
        else { throw CoordinationError(message: "Provider thread identity/directory did not match this worker.") }
        guard let status = thread["status"] as? [String: Any], status["type"] as? String == "idle" else {
            throw CoordinationError(
                message:
                    "Provider thread is active, unloaded or unavailable. Resume requires an idle thread in the existing shared Codex server; no second provider was launched."
            )
        }
    }

    private static func interrupt(_ threadID: String, turnID: String, transport: WorkerResumeTransport) -> Bool {
        do {
            let connection = try CodexResumeConnection(executable: transport.executable, socket: transport.socket)
            defer { connection.close() }
            try connection.initialize()
            _ = try connection.request("turn/interrupt", ["threadId": threadID, "turnId": turnID])
            let metadata = try connection.request("thread/read", ["threadId": threadID, "includeTurns": false])
            guard let thread = metadata["thread"] as? [String: Any], thread["id"] as? String == threadID,
                let status = thread["status"] as? [String: Any]
            else { return false }
            return status["type"] as? String == "idle"
        } catch { return false }
    }
}
