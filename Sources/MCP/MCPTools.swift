import Foundation

private let protocolVersions: Set<String> = ["2024-11-05", "2025-03-26", "2025-06-18"]

extension AppStore {
    // MARK: HTTP routing

    func handleHTTP(method: String, path: String, body: Data) -> (status: Int, body: Data, contentType: String) {
        func json(_ obj: Any, status: Int = 200) -> (Int, Data, String) {
            let d = (try? JSONSerialization.data(withJSONObject: obj, options: [])) ?? Data()
            return (status, d, "application/json")
        }
        if method == "GET", path == "/" || path == "/status" {
            return json(["app": "AgentDeck", "mcp": mcpBaseURL + "/mcp", "sessions": sessionInfos(caller: nil), "tasks": taskInfos()])
        }
        if method == "GET", path == "/board" { return json(["tasks": taskInfos()]) }
        guard path == "/mcp" || path.hasPrefix("/mcp/") else { return (404, Data("not found".utf8), "text/plain") }
        let caller = UUID(uuidString: String(path.dropFirst("/mcp/".count)))
        switch method {
        case "GET": return (405, Data("SSE streams are not supported; POST JSON-RPC here.".utf8), "text/plain")
        case "DELETE": return (200, Data(), "text/plain")
        case "POST": break
        default: return (405, Data(), "text/plain")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: body) else {
            return json(rpcError(id: nil, code: -32700, message: "parse error"), status: 400)
        }
        if obj is [Any] { return json(rpcError(id: nil, code: -32600, message: "batching is not supported"), status: 400) }
        guard let req = obj as? [String: Any], let m = req["method"] as? String else {
            return json(rpcError(id: nil, code: -32600, message: "invalid request"), status: 400)
        }
        let id = req["id"]
        let params = req["params"] as? [String: Any] ?? [:]
        if id == nil || id is NSNull {
            // Notification (e.g. notifications/initialized): acknowledge, no body.
            return (202, Data(), "application/json")
        }
        switch m {
        case "initialize":
            let requested = params["protocolVersion"] as? String ?? "2025-06-18"
            let v = protocolVersions.contains(requested) ? requested : "2025-06-18"
            return json(rpcResult(id: id!, [
                "protocolVersion": v,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "agentdeck", "version": "0.1.0"],
                "instructions": "AgentDeck coordinates several AI agent sessions. Use list_sessions and read_board to see the others, update_task to claim/finish work, handoff to delegate a task to another session, send_message for a free-form note.",
            ]))
        case "ping": return json(rpcResult(id: id!, [:]))
        case "tools/list": return json(rpcResult(id: id!, ["tools": toolDefinitions(caller: caller)]))
        case "resources/list": return json(rpcResult(id: id!, ["resources": []]))
        case "prompts/list": return json(rpcResult(id: id!, ["prompts": []]))
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            let r = callTool(name: name, args: args, caller: caller)
            return json(rpcResult(id: id!, ["content": [["type": "text", "text": r.text]], "isError": r.isError]))
        default:
            return json(rpcError(id: id, code: -32601, message: "method not found: \(m)"))
        }
    }

    private func rpcResult(id: Any, _ result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private func rpcError(id: Any?, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }

    // MARK: DTOs

    func sessionInfos(caller: UUID?) -> [[String: Any]] {
        sessions.map { s in
            let rt = runtime[s.id]
            var d: [String: Any] = [
                "id": s.id.uuidString, "name": s.name, "kind": s.kind.rawValue,
                "status": (rt?.status ?? .exited).rawValue, "directory": s.effectiveDirectory,
                "is_orchestrator": s.isOrchestrator, "is_self": s.id == caller,
            ]
            if let p = profile(for: s) { d["cli"] = p.name }
            if let b = s.worktreeBranch { d["worktree_branch"] = b }
            if let u = s.url { d["url"] = u }
            if let q = rt?.pendingQuestion { d["pending_question"] = q }
            if let t = rt?.title, !t.isEmpty { d["title"] = t }
            d["open_tasks"] = tasks.filter { $0.ownerSessionID == s.id && $0.status != .done }.map(\.id)
            return d
        }
    }

    func taskInfos(status: TaskStatus? = nil) -> [[String: Any]] {
        let f = ISO8601DateFormatter()
        return tasks.filter { status == nil || $0.status == status }.map { t in
            var d: [String: Any] = [
                "id": t.id, "title": t.title, "description": t.description, "status": t.status.rawValue,
                "notes": t.notes, "created_by": t.createdBy, "updated_at": f.string(from: t.updatedAt),
            ]
            d["owner"] = t.ownerSessionID.map(self.name(of:)) ?? NSNull()
            d["owner_id"] = t.ownerSessionID?.uuidString ?? NSNull()
            return d
        }
    }

    // MARK: Tool definitions

    func toolDefinitions(caller: UUID?) -> [[String: Any]] {
        func tool(_ name: String, _ desc: String, _ props: [String: Any], required: [String] = []) -> [String: Any] {
            ["name": name, "description": desc,
             "inputSchema": ["type": "object", "properties": props, "required": required, "additionalProperties": false]]
        }
        let str = { (d: String) -> [String: Any] in ["type": "string", "description": d] }
        let sessionRef = str("Target session: its name, id, or \"me\".")
        var tools: [[String: Any]] = [
            tool("whoami", "Describe the calling session (name, id, directory, role).", [:]),
            tool("list_sessions", "List every session AgentDeck manages, with live status and open task ids.", [:]),
            tool("read_board", "Read the shared task board.", ["status": str("Filter: todo | in-progress | done | blocked")]),
            tool("create_task", "Add a task to the shared board.", [
                "title": str("Short title"), "description": str("What needs to be done"),
                "owner": sessionRef, "status": str("todo | in-progress | done | blocked (default todo)"),
                "notes": str("Initial notes"),
            ], required: ["title"]),
            tool("update_task", "Update a task: claim it (owner=me), change status, append a note.", [
                "task_id": ["type": "integer", "description": "Task id from read_board"],
                "status": str("todo | in-progress | done | blocked"), "owner": str("Session name/id, \"me\", or \"none\" to unassign"),
                "notes": str("Appended to the task notes"), "title": str("New title"), "description": str("New description"),
            ], required: ["task_id"]),
            tool("handoff", "Hand a task to another session. Assigns the task to it and delivers a message into that session's input (queued if it is busy).", [
                "target_session": sessionRef, "task_id": ["type": "integer", "description": "Existing task to hand off"],
                "title": str("Title for a new task if task_id is not given"), "description": str("Details for a new task"),
                "note": str("Extra context for the receiving agent"),
            ], required: ["target_session"]),
            tool("send_message", "Type a free-form message into another CLI session as if the user typed it (queued if busy).", [
                "target_session": sessionRef, "text": str("Single-line message"),
            ], required: ["target_session", "text"]),
            tool("log", "Append a line to the orchestration log shown in the app.", [
                "message": str("Text"), "level": str("info | warn | error"),
            ], required: ["message"]),
        ]
        if let caller, session(caller)?.isOrchestrator == true {
            tools.append(tool("recruit_session", "Orchestrator only: ask the user to approve spawning a new managed session. Returns a request id; poll recruit_status.", [
                "name": str("Session name"), "kind": str("cli | browser (default cli)"),
                "cli_profile": str("claude | codex | gemini | opencode | grok | shell (default claude)"),
                "working_directory": str("Directory for the new CLI session (default: your directory)"),
                "use_worktree": ["type": "boolean", "description": "Create an isolated git worktree for it"],
                "url": str("Start URL for a browser session"), "initial_prompt": str("First message delivered when the session is ready"),
                "reason": str("Why you need it (shown to the user)"),
            ], required: ["name"]))
            tools.append(tool("recruit_status", "Check a recruit request.", ["request_id": str("Id returned by recruit_session")], required: ["request_id"]))
        }
        return tools
    }

    // MARK: Tool calls

    struct ToolResult { var text: String; var isError: Bool = false }

    private func ok(_ obj: Any) -> ToolResult {
        if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
            return ToolResult(text: String(decoding: d, as: UTF8.self))
        }
        return ToolResult(text: "\(obj)")
    }

    private func fail(_ msg: String) -> ToolResult { ToolResult(text: msg, isError: true) }

    func callTool(name: String, args: [String: Any], caller: UUID?) -> ToolResult {
        let callerName = caller.map(self.name(of:)) ?? "unknown"
        let argSummary = args.map { "\($0.key)=\(String(describing: $0.value).prefix(40))" }.sorted().joined(separator: ", ")
        addLog(source: callerName, message: "mcp \(name)(\(argSummary))")
        switch name {
        case "whoami":
            guard let caller, let s = session(caller) else {
                return fail("Caller unknown: connect to \(mcpBaseURL)/mcp/<session-id> (see $AGENTDECK_MCP_URL).")
            }
            return ok(sessionInfos(caller: caller).first { ($0["id"] as? String) == s.id.uuidString } ?? [:])
        case "list_sessions":
            return ok(["sessions": sessionInfos(caller: caller)])
        case "read_board":
            let st = (args["status"] as? String).flatMap(TaskStatus.init(rawValue:))
            return ok(["tasks": taskInfos(status: st)])
        case "create_task":
            guard let title = args["title"] as? String, !title.isEmpty else { return fail("title is required") }
            let owner = (args["owner"] as? String).flatMap { resolveSession($0, from: caller) }?.id
            let st = (args["status"] as? String).flatMap(TaskStatus.init(rawValue:)) ?? .todo
            let t = createTask(title: title, description: args["description"] as? String ?? "", owner: owner, status: st,
                               notes: args["notes"] as? String ?? "", createdBy: callerName)
            return ok(taskInfos().first { ($0["id"] as? Int) == t.id } ?? [:])
        case "update_task":
            guard let tid = args["task_id"] as? Int, var t = tasks.first(where: { $0.id == tid }) else { return fail("unknown task_id") }
            if let s = args["status"] as? String {
                guard let st = TaskStatus(rawValue: s) else { return fail("invalid status \(s)") }
                t.status = st
            }
            if let o = args["owner"] as? String {
                if o.lowercased() == "none" || o.isEmpty { t.ownerSessionID = nil }
                else if let s = resolveSession(o, from: caller) { t.ownerSessionID = s.id }
                else { return fail("unknown session \(o)") }
            }
            if let n = args["notes"] as? String, !n.isEmpty { t.notes += (t.notes.isEmpty ? "" : "\n") + "[\(callerName)] \(n)" }
            if let v = args["title"] as? String, !v.isEmpty { t.title = v }
            if let v = args["description"] as? String { t.description = v }
            updateTask(t, by: callerName)
            return ok(taskInfos().first { ($0["id"] as? Int) == tid } ?? [:])
        case "handoff":
            guard let ref = args["target_session"] as? String, let target = resolveSession(ref, from: caller) else {
                return fail("unknown target_session; call list_sessions")
            }
            if target.id == caller { return fail("cannot hand off to yourself") }
            do {
                let r = try handoff(from: caller, to: target, taskID: args["task_id"] as? Int, title: args["title"] as? String,
                                    description: args["description"] as? String, note: args["note"] as? String)
                return ok(["task_id": r.task.id, "target": target.name, "delivered": r.delivered ? "now" : (target.kind == .cli ? "queued until idle" : "assigned only (browser session)")])
            } catch { return fail(error.localizedDescription) }
        case "send_message":
            guard let ref = args["target_session"] as? String, let target = resolveSession(ref, from: caller) else {
                return fail("unknown target_session; call list_sessions")
            }
            guard let text = args["text"] as? String, !text.isEmpty else { return fail("text is required") }
            guard target.kind == .cli else { return fail("\(target.name) is a browser session; messages can only be typed into CLI sessions") }
            let delivered = inject(target.id, text: "[message from \(callerName)] \(text)", source: callerName, queueIfBusy: true)
            return delivered ? ok(["delivered": runtime[target.id]?.status.acceptsInjection == true ? "now" : "queued until idle"]) : fail("session is not running")
        case "log":
            guard let m = args["message"] as? String else { return fail("message is required") }
            addLog(source: callerName, message: m, level: LogLevel(rawValue: args["level"] as? String ?? "info") ?? .info)
            return ok(["logged": true])
        case "recruit_session":
            guard let caller, let me = session(caller), me.isOrchestrator else { return fail("only the Orchestrator session may recruit") }
            guard let name = args["name"] as? String, !name.isEmpty else { return fail("name is required") }
            let kind = SessionKind(rawValue: args["kind"] as? String ?? "cli") ?? .cli
            let req = RecruitRequest(requestedBy: caller, requestedByName: me.name, kind: kind, name: name,
                                     cliProfileID: args["cli_profile"] as? String ?? "claude",
                                     workingDirectory: args["working_directory"] as? String ?? me.effectiveDirectory,
                                     useWorktree: args["use_worktree"] as? Bool ?? false, url: args["url"] as? String,
                                     initialPrompt: args["initial_prompt"] as? String, reason: args["reason"] as? String ?? "")
            requestRecruit(req)
            return ok(["request_id": req.id.uuidString, "status": "pending", "note": "The user must approve this in AgentDeck. Poll recruit_status."])
        case "recruit_status":
            guard let rid = (args["request_id"] as? String).flatMap(UUID.init(uuidString:)), let r = recruits.first(where: { $0.id == rid }) else {
                return fail("unknown request_id")
            }
            var d: [String: Any] = ["request_id": r.id.uuidString, "status": r.status.rawValue]
            if let sid = r.createdSessionID { d["session_id"] = sid.uuidString; d["session_name"] = self.name(of: sid) }
            return ok(d)
        default:
            return fail("unknown tool \(name)")
        }
    }
}
