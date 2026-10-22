import AppKit
import Foundation

/// browser_* MCP tools. Each CLI session drives only its own companion browser: a WebKit tab beside its terminal
/// with an isolated website data store, so agents never touch the user's browser or each other's.
extension AppStore {
    static let browserToolNames: Set<String> = [
        "browser_navigate", "browser_read", "browser_click", "browser_type", "browser_screenshot", "browser_eval",
    ]

    func agentBrowser(for ownerID: UUID) -> ManagedSession? { sessions.first { $0.agentOwnerID == ownerID } }

    /// The caller's private browser, created on first use without stealing focus from its terminal.
    func agentBrowserController(for ownerID: UUID) -> BrowserController? {
        guard let owner = session(ownerID), owner.kind == .cli else { return nil }
        let companion: ManagedSession
        if let existing = agentBrowser(for: ownerID) {
            companion = existing
        } else {
            var s = ManagedSession(name: "\(owner.name) browser", kind: .browser)
            s.agentOwnerID = owner.id
            s.browserProfileMode = .isolated
            s.url = "about:blank"
            s.paneID = owner.paneID
            s.paneSize = owner.paneSize
            s.canvasPosition = owner.canvasPosition
            s.zIndex = owner.zIndex
            s.autoInjectContext = false
            let focused = focusedSessionID
            let selected = selectedPaneTabs[owner.paneID]
            companion = addSession(s, start: true)
            selectedPaneTabs[owner.paneID] = selected ?? owner.id
            focusedSessionID = focused
            addLog(source: owner.name, message: "opened private browser tab \"\(companion.name)\"")
        }
        if runtime[companion.id]?.isRunning != true { startSession(companion.id) }
        return browsers.controllers[companion.id]
    }

    func browserToolDefinitions() -> [[String: Any]] {
        func tool(_ name: String, _ desc: String, _ props: [String: Any], required: [String] = []) -> [String: Any] {
            [
                "name": name, "description": desc,
                "inputSchema": [
                    "type": "object", "properties": props, "required": required, "additionalProperties": false,
                ],
            ]
        }
        let str = { (d: String) -> [String: Any] in ["type": "string", "description": d] }
        let int = { (d: String) -> [String: Any] in ["type": "integer", "description": d] }
        let wait = int("Settle time in ms after the action before reporting (default 500, max 10000)")
        let intro =
            "Your private browser inside AgentDeck (isolated profile, shown as a tab beside your terminal; never the user's own browser). "
        return [
            tool(
                "browser_navigate",
                intro + "Load a URL, wait for it to finish, and return url, title and a text preview.",
                ["url": str("http(s) URL"), "wait_ms": wait], required: ["url"]),
            tool(
                "browser_read",
                "Read the current page of your private browser: visible text (default), links (anchors with hrefs) or raw html.",
                [
                    "mode": str("text | links | html (default text)"),
                    "max_chars": int("Truncate output (default 20000)"),
                ]),
            tool(
                "browser_click",
                "Click an element in your private browser by CSS selector or by visible text (buttons, links, menu items). Reports url and title afterwards.",
                [
                    "selector": str("CSS selector"), "text": str("Visible text to match (exact first, then substring)"),
                    "wait_ms": wait,
                ]),
            tool(
                "browser_type",
                "Type into a field of your private browser (CSS selector, else the focused or first visible input). Replaces the current value; optionally presses Enter.",
                [
                    "text": str("Text to enter"), "selector": str("CSS selector of the field"),
                    "submit": ["type": "boolean", "description": "Press Enter / submit the form afterwards"],
                    "wait_ms": wait,
                ], required: ["text"]),
            tool(
                "browser_screenshot",
                "PNG screenshot of your private browser's current page. Needs the AgentDeck window on screen.", [:]),
            tool(
                "browser_eval", "Run JavaScript in your private browser's page and return the result as text or JSON.",
                ["script": str("JavaScript expression or IIFE")], required: ["script"]),
        ]
    }

    func callBrowserTool(name: String, args: [String: Any], caller: UUID) async -> ToolResult {
        guard let controller = agentBrowserController(for: caller) else {
            return ToolResult(text: "browser tools are only available to CLI sessions", isError: true)
        }
        controller.ensureInWindow()
        let waitMs = min(max(args["wait_ms"] as? Int ?? 500, 0), 10_000)
        switch name {
        case "browser_navigate":
            guard let url = args["url"] as? String, !url.isEmpty else {
                return ToolResult(text: "url is required", isError: true)
            }
            if let error = await controller.navigate(url) {
                return ToolResult(text: "navigation failed: \(error)", isError: true)
            }
            try? await Task.sleep(for: .milliseconds(waitMs))
            return json(await pageState(controller))
        case "browser_read":
            let mode = args["mode"] as? String ?? "text"
            let maxChars = min(max(args["max_chars"] as? Int ?? 20_000, 200), 500_000)
            let script: String
            switch mode {
            case "text": script = BrowserScripts.text
            case "links": script = BrowserScripts.links
            case "html": script = BrowserScripts.html
            default: return ToolResult(text: "mode must be text | links | html", isError: true)
            }
            switch await controller.evaluate(script) {
            case .failure(let error): return ToolResult(text: error.message, isError: true)
            case .success(let content):
                var d = await pageState(controller, preview: false)
                d["mode"] = mode
                d["truncated"] = content.count > maxChars
                d["content"] = String(content.prefix(maxChars))
                return json(d)
            }
        case "browser_click":
            let selector = args["selector"] as? String ?? ""
            let text = args["text"] as? String ?? ""
            guard !selector.isEmpty || !text.isEmpty else {
                return ToolResult(text: "selector or text is required", isError: true)
            }
            return await perform(BrowserScripts.click(selector: selector, text: text), on: controller, waitMs: waitMs)
        case "browser_type":
            guard let text = args["text"] as? String else { return ToolResult(text: "text is required", isError: true) }
            let script = BrowserScripts.type(
                selector: args["selector"] as? String ?? "", text: text, submit: args["submit"] as? Bool ?? false)
            return await perform(script, on: controller, waitMs: waitMs)
        case "browser_screenshot":
            guard let png = await controller.snapshot() else {
                return ToolResult(
                    text: "screenshot failed: WebKit only renders while the AgentDeck window is on screen",
                    isError: true)
            }
            let state = await pageState(controller, preview: false)
            let caption = "\(state["title"] ?? "") — \(state["url"] ?? "")"
            return ToolResult(content: [
                ["type": "image", "data": png.base64EncodedString(), "mimeType": "image/png"],
                ["type": "text", "text": caption],
            ])
        case "browser_eval":
            guard let script = args["script"] as? String, !script.isEmpty else {
                return ToolResult(text: "script is required", isError: true)
            }
            switch await controller.evaluate(script) {
            case .failure(let error): return ToolResult(text: error.message, isError: true)
            case .success(let result): return ToolResult(text: result)
            }
        default:
            return ToolResult(text: "unknown tool \(name)", isError: true)
        }
    }

    /// Run an action script that returns `{error}` or a result object, then report the page state.
    private func perform(_ script: String, on controller: BrowserController, waitMs: Int) async -> ToolResult {
        switch await controller.evaluate(script) {
        case .failure(let error): return ToolResult(text: error.message, isError: true)
        case .success(let raw):
            let outcome = Self.object(from: raw)
            if let error = outcome["error"] as? String { return ToolResult(text: error, isError: true) }
            try? await Task.sleep(for: .milliseconds(waitMs))
            var d = await pageState(controller)
            d.merge(outcome) { _, action in action }
            return json(d)
        }
    }

    private func pageState(_ controller: BrowserController, preview: Bool = true) async -> [String: Any] {
        var d: [String: Any] = [
            "url": controller.webView.url?.absoluteString ?? "about:blank", "title": controller.webView.title ?? "",
        ]
        if preview, case .success(let raw) = await controller.evaluate(BrowserScripts.state) {
            d.merge(Self.object(from: raw)) { _, fresh in fresh }
        }
        return d
    }

    private static func object(from json: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
    }

    private func json(_ obj: [String: Any]) -> ToolResult {
        if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
            return ToolResult(text: String(decoding: d, as: UTF8.self))
        }
        return ToolResult(text: "\(obj)")
    }
}
