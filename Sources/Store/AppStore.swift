import AppKit
import Combine
import Foundation

@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published var sessions: [ManagedSession] = []
    @Published var runtime: [UUID: SessionRuntime] = [:]
    @Published var tasks: [BoardTask] = []
    @Published var log: [LogEntry] = []
    @Published var settings = AppSettings() {
        didSet {
            guard loaded else { return }
            applyFonts()
            if oldValue.appearance != settings.appearance { applyAppearance() }
            scheduleSave()
        }
    }
    @Published var cliProfiles: [CLIProfile] = CLIProfile.builtins { didSet { if loaded { scheduleSave() } } }
    @Published var focusedSessionID: UUID? {
        didSet {
            guard loaded else { return }
            if let id = focusedSessionID { raisePane(id) }
            scheduleSave()
        }
    }
    @Published var maximizedSessionID: UUID?
    @Published var recruits: [RecruitRequest] = []
    @Published var mcpStatus: String = "stopped"
    @Published var showNewSession = false
    @Published var showInjectSheet = false
    @Published var lastError: String?

    private(set) var nextTaskID = 1
    let terminals = TerminalHost()
    let browsers = BrowserHost()
    private var mcp: MCPServer?
    private var saveTask: Task<Void, Never>?
    private var statusTimer: Timer?
    private var contextTimer: Timer?
    private var loaded = false
    private var pendingInjections: [UUID: [String]] = [:]
    private var appearanceObserver: NSKeyValueObservation?

    static let supportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("AgentDeck", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    static var stateURL: URL { supportDir.appendingPathComponent("state.json") }
    static var mcpConfigDir: URL {
        let d = supportDir.appendingPathComponent("mcp", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    init() {
        load()
        wireHosts()
        loaded = true
    }

    // MARK: Lifecycle

    func bootstrap() {
        applyAppearance()
        appearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.applyTerminalTheme() }
        }
        startMCP()
        for s in sessions where s.autoStart { startSession(s.id) }
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.statusTick() }
        }
        contextTimer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.contextTick() }
        }
        addLog(source: "app", message: "AgentDeck started. MCP endpoint: \(mcpBaseURL)/mcp")
    }

    func shutdown() {
        saveNow()
        for s in sessions { terminals.terminate(id: s.id) }
        mcp?.stop()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: Self.stateURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let st = try? dec.decode(PersistedState.self, from: data) else { return }
        sessions = st.sessions
        tasks = st.tasks
        nextTaskID = max(st.nextTaskID, (tasks.map(\.id).max() ?? 0) + 1)
        log = Array(st.log.suffix(500))
        settings = st.settings
        cliProfiles = st.cliProfiles.isEmpty ? CLIProfile.builtins : st.cliProfiles
        // Make sure new built-in profiles show up for users with an older profile list.
        for b in CLIProfile.builtins where !cliProfiles.contains(where: { $0.id == b.id }) { cliProfiles.append(b) }
        focusedSessionID = st.focusedSessionID
        for s in sessions { runtime[s.id] = SessionRuntime(status: .exited) }
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        var st = PersistedState()
        st.sessions = sessions
        st.tasks = tasks
        st.nextTaskID = nextTaskID
        st.log = Array(log.suffix(500))
        st.settings = settings
        st.cliProfiles = cliProfiles
        st.focusedSessionID = focusedSessionID
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(st) { try? data.write(to: Self.stateURL, options: .atomic) }
    }

    // MARK: Hosts

    private func wireHosts() {
        terminals.onOutput = { [weak self] id in
            guard let self else { return }
            self.runtime[id]?.lastOutputAt = Date()
        }
        terminals.onExit = { [weak self] id, code in
            guard let self else { return }
            self.runtime[id]?.isRunning = false
            self.runtime[id]?.exitCode = code
            self.setStatus(id, (code ?? 0) == 0 ? .exited : .error)
            self.addLog(source: self.name(of: id), message: "process exited (code \(code.map(String.init) ?? "signal"))",
                        level: (code ?? 0) == 0 ? .info : .warn)
        }
        terminals.onTitle = { [weak self] id, title in self?.runtime[id]?.title = title }
        terminals.onFocus = { [weak self] id in
            guard let self, self.focusedSessionID != id else { return }
            self.focusedSessionID = id
        }
        terminals.onProgramStatus = { [weak self] id, state, message in
            self?.runtime[id]?.programState = state
            self?.runtime[id]?.programMessage = message
        }
        browsers.onStateChange = { [weak self] id in
            guard let self, let c = self.browsers.controllers[id] else { return }
            self.runtime[id]?.title = c.title
            self.runtime[id]?.lastOutputAt = Date()
            self.setStatus(id, c.isLoading ? .working : .idle)
        }
    }

    // MARK: Sessions

    func session(_ id: UUID?) -> ManagedSession? {
        guard let id else { return nil }
        return sessions.first { $0.id == id }
    }

    func name(of id: UUID) -> String { session(id)?.name ?? id.uuidString.prefix(8).description }

    func profile(for session: ManagedSession) -> CLIProfile? {
        cliProfiles.first { $0.id == session.cliProfileID }
    }

    func status(of id: UUID) -> SessionStatus { runtime[id]?.status ?? .exited }

    func resolveSession(_ ref: String, from caller: UUID? = nil) -> ManagedSession? {
        let r = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        if r.lowercased() == "me" || r.lowercased() == "self", let caller { return session(caller) }
        if let u = UUID(uuidString: r), let s = session(u) { return s }
        if let s = sessions.first(where: { $0.name.caseInsensitiveCompare(r) == .orderedSame }) { return s }
        if let s = sessions.first(where: { $0.id.uuidString.lowercased().hasPrefix(r.lowercased()) && r.count >= 6 }) { return s }
        let candidates = sessions.filter { $0.name.lowercased().hasPrefix(r.lowercased()) }
        return candidates.count == 1 ? candidates.first : nil
    }

    func font(for session: ManagedSession) -> NSFont {
        let size = session.fontSizeOverride ?? settings.globalFontSize
        return NSFont(name: settings.fontName, size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    func applyFonts() {
        for s in sessions where s.kind == .cli { terminals.setFont(id: s.id, font(for: s)) }
    }

    @discardableResult
    func addSession(_ s: ManagedSession, start: Bool = true) -> ManagedSession {
        var s = s
        if s.kind == .cli, let p = profile(for: s), !p.supportsMCP { s.autoInjectContext = false }
        sessions.append(s)
        runtime[s.id] = SessionRuntime()
        focusedSessionID = s.id
        addLog(source: "app", message: "session \"\(s.name)\" added (\(s.kind.label))")
        if start { startSession(s.id) }
        scheduleSave()
        return s
    }

    func updateSession(_ s: ManagedSession) {
        guard let i = sessions.firstIndex(where: { $0.id == s.id }) else { return }
        sessions[i] = s
        if s.kind == .cli { terminals.setFont(id: s.id, font(for: s)) }
        scheduleSave()
    }

    var mcpBaseURL: String { "http://127.0.0.1:\(settings.mcpPort)" }
    func mcpURL(for id: UUID) -> String { "\(mcpBaseURL)/mcp/\(id.uuidString)" }
    func mcpConfigPath(for id: UUID) -> String { Self.mcpConfigDir.appendingPathComponent("\(id.uuidString).json").path }

    private func writeMCPConfig(for id: UUID) {
        let cfg: [String: Any] = ["mcpServers": ["agentdeck": ["type": "http", "url": mcpURL(for: id)]]]
        if let d = try? JSONSerialization.data(withJSONObject: cfg, options: [.prettyPrinted]) {
            try? d.write(to: URL(fileURLWithPath: mcpConfigPath(for: id)))
        }
    }

    func launchCommand(for s: ManagedSession) -> String {
        let p = profile(for: s) ?? CLIProfile.builtins.last!
        return p.command
            .replacingOccurrences(of: "{mcpUrl}", with: mcpURL(for: s.id))
            .replacingOccurrences(of: "{mcpConfigPath}", with: mcpConfigPath(for: s.id))
            .replacingOccurrences(of: "{sessionId}", with: s.id.uuidString)
            .replacingOccurrences(of: "{sessionName}", with: s.name)
            .replacingOccurrences(of: "{cwd}", with: s.effectiveDirectory)
    }

    func environment(for s: ManagedSession) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Nested launches: a parent Claude Code / Codex session must not leak its markers into the child.
        for k in env.keys where k.hasPrefix("CLAUDE") || k.hasPrefix("CODEX_") { env[k] = nil }
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "AgentDeck"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        env["AGENTDECK_SESSION_ID"] = s.id.uuidString
        env["AGENTDECK_SESSION_NAME"] = s.name
        env["AGENTDECK_MCP_URL"] = mcpURL(for: s.id)
        env["AGENTDECK_MCP_CONFIG"] = mcpConfigPath(for: s.id)
        return env
    }

    func startSession(_ id: UUID) {
        guard let s = session(id) else { return }
        var rt = runtime[id] ?? SessionRuntime()
        rt.status = .starting
        rt.statusSince = Date()
        rt.startedAt = Date()
        rt.exitCode = nil
        rt.pendingQuestion = nil
        rt.programState = nil
        rt.initialPromptSent = false
        rt.lastContextHash = nil
        rt.isRunning = true
        runtime[id] = rt
        switch s.kind {
        case .cli:
            writeMCPConfig(for: id)
            let cwd = s.effectiveDirectory.expandingTilde
            if !FileManager.default.fileExists(atPath: cwd) {
                try? FileManager.default.createDirectory(atPath: cwd, withIntermediateDirectories: true)
            }
            terminals.start(id: id, command: launchCommand(for: s), cwd: cwd, environment: environment(for: s), font: font(for: s))
            addLog(source: s.name, message: "launched: \(launchCommand(for: s)) in \(cwd.abbreviatingHome)")
        case .browser:
            _ = browsers.controller(for: s)
            setStatus(id, .idle)
            addLog(source: s.name, message: "browser profile opened: \(s.url ?? "")")
        }
    }

    func restartSession(_ id: UUID) {
        guard let s = session(id) else { return }
        pendingInjections[id] = nil
        switch s.kind {
        case .cli: terminals.dispose(id: id)
        case .browser: browsers.dispose(id: id)
        }
        runtime[id]?.generation += 1
        startSession(id)
    }

    func stopSession(_ id: UUID) {
        guard let s = session(id) else { return }
        switch s.kind {
        case .cli: terminals.terminate(id: id)
        case .browser:
            browsers.dispose(id: id)
            runtime[id]?.isRunning = false
            setStatus(id, .exited)
        }
    }

    func removeSession(_ id: UUID, deleteWorktree: Bool = false, deleteBrowserProfile: Bool = false) {
        guard let s = session(id) else { return }
        terminals.dispose(id: id)
        browsers.dispose(id: id)
        if deleteWorktree, let repo = s.worktreeRepo, let path = s.worktreePath {
            do { try Worktree.remove(repo: repo, path: path) } catch { lastError = "Worktree removal failed: \(error.localizedDescription)" }
        }
        if deleteBrowserProfile, s.kind == .browser { BrowserHost.deleteProfile(s.browserProfileID) }
        try? FileManager.default.removeItem(atPath: mcpConfigPath(for: id))
        sessions.removeAll { $0.id == id }
        runtime[id] = nil
        pendingInjections[id] = nil
        if focusedSessionID == id { focusedSessionID = sessions.first?.id }
        if maximizedSessionID == id { maximizedSessionID = nil }
        for i in tasks.indices where tasks[i].ownerSessionID == id { tasks[i].ownerSessionID = nil }
        addLog(source: "app", message: "session \"\(s.name)\" removed")
        scheduleSave()
    }

    func setStatus(_ id: UUID, _ st: SessionStatus) {
        guard var rt = runtime[id], rt.status != st else { return }
        rt.status = st
        rt.statusSince = Date()
        runtime[id] = rt
        switch st {
        case .waitingForUser, .stalled, .quotaWarning, .error:
            addLog(source: name(of: id), message: "status: \(st.label)", level: st == .error ? .error : .warn)
        default: break
        }
    }

    // MARK: Appearance

    var isDarkTheme: Bool {
        switch settings.appearance {
        case .light: return false
        case .dark: return true
        case .system: return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }

    func applyAppearance() {
        switch settings.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        applyTerminalTheme()
    }

    func applyTerminalTheme() {
        terminals.applyTheme(dark: isDarkTheme)
    }

    /// Flip between light and dark (from System, go to the opposite of what is showing now).
    func toggleTheme() {
        settings.appearance = isDarkTheme ? .light : .dark
    }

    // MARK: Font & size controls

    func adjustFont(for id: UUID?, by delta: Double) {
        guard let id, var s = session(id) else { return }
        let base = s.fontSizeOverride ?? settings.globalFontSize
        s.fontSizeOverride = min(40, max(8, base + delta))
        updateSession(s)
    }

    func resetFont(for id: UUID?) {
        guard let id, var s = session(id) else { return }
        s.fontSizeOverride = nil
        updateSession(s)
    }

    func setPaneSize(for id: UUID, _ size: PaneSize?) {
        guard var s = session(id) else { return }
        s.paneSize = size
        updateSession(s)
    }

    func paneSize(for s: ManagedSession) -> PaneSize { s.paneSize ?? settings.defaultPanePreset.size }

    // MARK: Canvas

    static let canvasSpacing: Double = 16

    /// Bring a pane to the front of the canvas.
    func raisePane(_ id: UUID) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        let top = sessions.map(\.zIndex).max() ?? 0
        if sessions[i].zIndex < top || sessions.filter({ $0.zIndex == top }).count > 1 {
            sessions[i].zIndex = top + 1
            scheduleSave()
        }
    }

    func setCanvasPosition(for id: UUID, _ p: PanePoint?) {
        guard var s = session(id) else { return }
        s.canvasPosition = p.map { PanePoint(x: max(0, $0.x), y: max(0, $0.y)) }
        updateSession(s)
    }

    /// Give every pane that has no canvas position one, flowing after the existing panes.
    func ensureCanvasPositions(viewportWidth: Double) {
        let missing = sessions.filter { $0.canvasPosition == nil }
        // A tiny width means the window has not been laid out yet; wait for the real size.
        guard !missing.isEmpty, viewportWidth > 500 else { return }
        let placed = sessions.filter { $0.canvasPosition != nil }
        var y = placed.map { ($0.canvasPosition?.y ?? 0) + paneSize(for: $0).height }.max().map { $0 + Self.canvasSpacing } ?? Self.canvasSpacing
        var x = Self.canvasSpacing
        var rowH = 0.0
        let width = viewportWidth
        for s in missing {
            let size = paneSize(for: s)
            if x > Self.canvasSpacing, x + size.width > width { x = Self.canvasSpacing; y += rowH + Self.canvasSpacing; rowH = 0 }
            setCanvasPosition(for: s.id, PanePoint(x: x, y: y))
            x += size.width + Self.canvasSpacing
            rowH = max(rowH, size.height)
        }
    }

    /// Re-pack all panes left-to-right into the viewport width, keeping their sizes.
    func tidyCanvas(viewportWidth: Double) {
        var x = Self.canvasSpacing, y = Self.canvasSpacing, rowH = 0.0
        let width = max(viewportWidth, 600)
        for s in sessions.sorted(by: { $0.zIndex < $1.zIndex }) {
            let size = paneSize(for: s)
            if x > Self.canvasSpacing, x + size.width > width { x = Self.canvasSpacing; y += rowH + Self.canvasSpacing; rowH = 0 }
            setCanvasPosition(for: s.id, PanePoint(x: x, y: y))
            x += size.width + Self.canvasSpacing
            rowH = max(rowH, size.height)
        }
    }

    // MARK: Injection

    /// Type `text` into a CLI session as if the user had typed it. Multi-line text is collapsed to one line.
    func inject(_ id: UUID, text: String, submit: Bool = true, source: String = "user", queueIfBusy: Bool = false) -> Bool {
        guard let s = session(id), s.kind == .cli else { return false }
        let line = text.singleLine
        guard !line.isEmpty else { return false }
        if queueIfBusy, !(runtime[id]?.status.acceptsInjection ?? false) {
            pendingInjections[id, default: []].append(line)
            addLog(source: source, message: "queued message for \"\(s.name)\" (busy): \(line.prefix(80))")
            return true
        }
        guard runtime[id]?.isRunning == true else { return false }
        let delay = Double(profile(for: s)?.submitDelayMs ?? 150) / 1000
        terminals.send(id: id, text: line)
        if submit {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.terminals.send(id: id, text: "\r") }
        }
        runtime[id]?.lastOutputAt = Date()
        addLog(source: source, message: "→ \(s.name): \(line.prefix(120))")
        return true
    }

    private func flushPending(_ id: UUID) {
        guard let q = pendingInjections[id], !q.isEmpty, runtime[id]?.status.acceptsInjection == true else { return }
        pendingInjections[id] = nil
        _ = inject(id, text: q.joined(separator: " || "), source: "queue")
    }

    // MARK: Status monitoring

    private func statusTick() {
        let now = Date()
        for s in sessions where s.kind == .cli {
            guard var rt = runtime[s.id], rt.isRunning else { continue }
            let lines = terminals.visibleLines(id: s.id)
            rt.lastLines = Array(lines.suffix(12))
            let ev = StatusHeuristics.evaluate(lines: lines, lastOutputAt: rt.lastOutputAt, startedAt: rt.startedAt,
                                               settings: settings, programState: rt.programState, now: now)
            var st = ev.status
            if rt.status == .starting, now.timeIntervalSince(rt.startedAt ?? now) < 2 { st = .starting }
            rt.pendingQuestion = ev.pendingQuestion
            let stats = StatusHeuristics.modelStats(lines: lines)
            if let m = stats.model { rt.modelName = m }
            if let c = stats.context { rt.contextInfo = c }
            runtime[s.id] = rt
            setStatus(s.id, st)
            if st == .idle { deliverFirstMessageIfNeeded(s); flushPending(s.id) }
        }
    }

    private func deliverFirstMessageIfNeeded(_ s: ManagedSession) {
        guard var rt = runtime[s.id], !rt.initialPromptSent else { return }
        rt.initialPromptSent = true
        runtime[s.id] = rt
        let canBrief = s.autoInjectContext && settings.contextInjectionEnabled && (profile(for: s)?.supportsMCP ?? false)
        var parts: [String] = []
        if canBrief { parts.append(briefing(for: s)); parts.append(contextSummary(for: s)) }
        if let p = s.initialPrompt?.singleLine, !p.isEmpty { parts.append(canBrief ? "Your first task: \(p)" : p) }
        guard !parts.isEmpty else { return }
        if inject(s.id, text: parts.joined(separator: " "), source: "context") {
            runtime[s.id]?.lastContextHash = contextHash()
            runtime[s.id]?.lastContextAt = Date()
        }
    }

    // MARK: Context awareness

    func briefing(for s: ManagedSession) -> String {
        let role = s.isOrchestrator ? "You are the Orchestrator: you may also call recruit_session (user approves) and assign work." : ""
        return "[AgentDeck] You are managed session \"\(s.name)\" (\(profile(for: s)?.name ?? "CLI")) in \(s.effectiveDirectory.abbreviatingHome). Other agents run in sibling sessions. Coordinate only through the agentdeck MCP tools: list_sessions, read_board, create_task, update_task, handoff, send_message, log. Claim a task with update_task(owner=me, status=in-progress) before working on it and mark it done when finished. \(role)".singleLine
    }

    func contextSummary(for target: ManagedSession) -> String {
        let sess = sessions.map { s -> String in
            let st = status(of: s.id).label.lowercased()
            return s.id == target.id ? "\(s.name) (\(st), you)" : "\(s.name) (\(st)\(s.kind == .browser ? ", browser" : ""))"
        }.joined(separator: ", ")
        let open = tasks.filter { $0.status != .done }
        let tl = open.prefix(8).map { t -> String in
            let owner = t.ownerSessionID.map { $0 == target.id ? "you" : name(of: $0) } ?? "unassigned"
            return "#\(t.id) \"\(t.title)\" (\(t.status.rawValue), \(owner))"
        }.joined(separator: "; ")
        let mine = open.filter { $0.ownerSessionID == target.id }.map { "#\($0.id)" }.joined(separator: ", ")
        var out = "[AgentDeck status] Sessions: \(sess). Open tasks: \(open.count)" + (tl.isEmpty ? "." : " — \(tl).")
        if !mine.isEmpty { out += " Assigned to you: \(mine)." }
        out += " Use read_board / update_task / handoff to coordinate."
        return out
    }

    func contextHash() -> Int {
        var h = Hasher()
        for s in sessions { h.combine(s.id); h.combine(s.name) }
        for t in tasks { h.combine(t.id); h.combine(t.status); h.combine(t.ownerSessionID); h.combine(t.title) }
        return h.finalize()
    }

    private func contextTick() {
        guard settings.contextInjectionEnabled else { return }
        let hash = contextHash()
        for s in sessions where s.kind == .cli && s.autoInjectContext {
            guard let rt = runtime[s.id], rt.isRunning, rt.status.acceptsInjection, rt.initialPromptSent,
                  profile(for: s)?.supportsMCP ?? false else { continue }
            if rt.lastContextHash == hash { continue }
            if let last = rt.lastContextAt, Date().timeIntervalSince(last) < settings.contextInjectionIntervalSeconds { continue }
            if inject(s.id, text: contextSummary(for: s), source: "context") {
                runtime[s.id]?.lastContextHash = hash
                runtime[s.id]?.lastContextAt = Date()
            }
        }
    }

    func injectContextNow(_ id: UUID) {
        guard let s = session(id) else { return }
        if inject(id, text: contextSummary(for: s), source: "context", queueIfBusy: true) {
            runtime[id]?.lastContextHash = contextHash()
            runtime[id]?.lastContextAt = Date()
        }
    }

    // MARK: Task board

    @discardableResult
    func createTask(title: String, description: String = "", owner: UUID? = nil, status: TaskStatus = .todo,
                    notes: String = "", createdBy: String = "user") -> BoardTask {
        let t = BoardTask(id: nextTaskID, title: title, description: description, ownerSessionID: owner,
                          status: status, notes: notes, createdBy: createdBy)
        nextTaskID += 1
        tasks.append(t)
        addLog(source: createdBy, message: "task #\(t.id) created: \(title)")
        scheduleSave()
        return t
    }

    func updateTask(_ t: BoardTask, by source: String = "user") {
        guard let i = tasks.firstIndex(where: { $0.id == t.id }) else { return }
        var n = t
        n.updatedAt = Date()
        let old = tasks[i]
        tasks[i] = n
        if old.status != n.status { addLog(source: source, message: "task #\(n.id) → \(n.status.label)") }
        if old.ownerSessionID != n.ownerSessionID {
            addLog(source: source, message: "task #\(n.id) owner → \(n.ownerSessionID.map(name(of:)) ?? "unassigned")")
        }
        scheduleSave()
    }

    func deleteTask(_ id: Int) {
        tasks.removeAll { $0.id == id }
        scheduleSave()
    }

    // MARK: Handoff

    enum HandoffError: Error, LocalizedError {
        case noTask
        var errorDescription: String? { "handoff needs task_id or title" }
    }

    @discardableResult
    func handoff(from caller: UUID?, to target: ManagedSession, taskID: Int?, title: String?, description: String?,
                 note: String?) throws -> (task: BoardTask, delivered: Bool) {
        let source = caller.map(name(of:)) ?? "user"
        var task: BoardTask
        if let taskID, let existing = tasks.first(where: { $0.id == taskID }) {
            task = existing
            task.ownerSessionID = target.id
            if task.status == .done { task.status = .todo }
            if let d = description, !d.isEmpty { task.description = d }
            if let note, !note.isEmpty { task.notes += (task.notes.isEmpty ? "" : "\n") + "[\(source)] \(note)" }
            updateTask(task, by: source)
        } else if let title, !title.isEmpty {
            task = createTask(title: title, description: description ?? "", owner: target.id,
                              notes: note.map { "[\(source)] \($0)" } ?? "", createdBy: source)
        } else {
            throw HandoffError.noTask
        }
        addLog(source: source, message: "handoff task #\(task.id) → \(target.name)")
        var msg = "[AgentDeck handoff from \(source)] Task #\(task.id): \(task.title)."
        if !task.description.isEmpty { msg += " \(task.description)" }
        if let note, !note.isEmpty { msg += " Note: \(note)" }
        msg += " Please take it: update_task(task_id=\(task.id), status=in-progress, owner=me), then mark it done."
        var delivered = false
        if target.kind == .cli {
            delivered = runtime[target.id]?.status.acceptsInjection == true
            _ = inject(target.id, text: msg, source: source, queueIfBusy: true)
            runtime[target.id]?.lastContextHash = contextHash()
        }
        return (task, delivered)
    }

    // MARK: Recruits

    func requestRecruit(_ r: RecruitRequest) {
        recruits.append(r)
        addLog(source: r.requestedByName, message: "requests a new session \"\(r.name)\" (\(r.kind.label)) — approve in the sidebar", level: .warn)
        NSApp.requestUserAttention(.informationalRequest)
    }

    func approveRecruit(_ id: UUID) {
        guard let i = recruits.firstIndex(where: { $0.id == id }) else { return }
        var r = recruits[i]
        var s = ManagedSession(name: r.name, kind: r.kind)
        if r.kind == .cli {
            s.cliProfileID = r.cliProfileID
            s.workingDirectory = r.workingDirectory
            s.initialPrompt = r.initialPrompt
            if r.useWorktree {
                do {
                    let wt = try Worktree.create(repoDir: r.workingDirectory, slug: r.name.slug, root: settings.worktreeRoot)
                    s.worktreePath = wt.path; s.worktreeBranch = wt.branch; s.worktreeRepo = wt.repo
                } catch { lastError = "Worktree creation failed: \(error.localizedDescription)" }
            }
        } else {
            s.url = r.url ?? BrowserPreset.chatgpt.url
        }
        let created = addSession(s)
        r.status = .approved
        r.createdSessionID = created.id
        recruits[i] = r
        if let by = r.requestedBy {
            _ = inject(by, text: "[AgentDeck] Your recruit request was approved: session \"\(created.name)\" (id \(created.id.uuidString)) is starting. Use handoff to give it work.",
                       source: "app", queueIfBusy: true)
        }
    }

    func denyRecruit(_ id: UUID) {
        guard let i = recruits.firstIndex(where: { $0.id == id }) else { return }
        recruits[i].status = .denied
        if let by = recruits[i].requestedBy {
            _ = inject(by, text: "[AgentDeck] Your recruit request \"\(recruits[i].name)\" was denied by the user.", source: "app", queueIfBusy: true)
        }
        addLog(source: "user", message: "denied recruit request \"\(recruits[i].name)\"")
    }

    // MARK: Log

    func addLog(source: String, message: String, level: LogLevel = .info) {
        log.append(LogEntry(source: source, message: message, level: level))
        if log.count > 1000 { log.removeFirst(log.count - 1000) }
        scheduleSave()
    }

    // MARK: MCP

    func startMCP() {
        mcp?.stop()
        let server = MCPServer(port: UInt16(settings.mcpPort)) { [weak self] method, path, body in
            guard let self else { return (500, Data(), "text/plain") }
            return self.handleHTTP(method: method, path: path, body: body)
        }
        do {
            try server.start()
            mcp = server
            mcpStatus = "listening on \(mcpBaseURL)"
        } catch {
            mcpStatus = "failed: \(error.localizedDescription)"
            addLog(source: "mcp", message: "server failed to start: \(error.localizedDescription)", level: .error)
        }
    }
}
