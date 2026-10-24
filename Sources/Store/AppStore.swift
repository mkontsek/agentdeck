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
            if oldValue.skillDirectories != settings.skillDirectories
                || oldValue.disabledSkillIDs != settings.disabledSkillIDs
            {
                reloadSkills()
            }
            scheduleSave()
        }
    }
    @Published var cliProfiles: [CLIProfile] = CLIProfile.builtins { didSet { if loaded { scheduleSave() } } }
    @Published var selectedPaneTabs: [UUID: UUID] = [:]
    @Published var focusedSessionID: UUID? {
        didSet {
            guard loaded else { return }
            if let id = focusedSessionID, let session = session(id) {
                selectedPaneTabs[session.paneID] = id
                if maximizedSessionID != nil { maximizedSessionID = id }
                raisePane(id)
            }
            scheduleSave()
        }
    }
    @Published var maximizedSessionID: UUID?
    @Published var canvasViewport: CGSize = .zero
    @Published var recruits: [RecruitRequest] = []
    @Published var mcpStatus: String = "stopped"
    @Published var showNewSession = false
    @Published var showInjectSheet = false
    @Published var lastError: String?

    private(set) var nextTaskID = 1
    let terminals = TerminalHost()
    let browsers = BrowserHost()
    let skillLibrary = SkillLibrary()
    private var bootstrapTask: Task<Void, Never>?
    private var bootstrapped = false
    private var mcp: MCPServer?
    private var saveTask: Task<Void, Never>?
    private var statusTimer: Timer?
    /// Last PTY output per session. Deliberately not published: output arrives many times per keystroke and must
    /// not re-render the whole window; `statusTick` folds it into `runtime` once a second.
    private var outputTimes: [UUID: Date] = [:]
    private var loaded = false
    private var pendingInjections: [UUID: [String]] = [:]
    private var appearanceObserver: NSKeyValueObservation?
    private let storageURL: URL
    private var canSave = true
    private var approvingRecruits: Set<UUID> = []

    static let supportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("AgentDeck", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    static var stateURL: URL { supportDir.appendingPathComponent("state.json") }

    init(stateURL: URL? = nil) {
        storageURL = stateURL ?? Self.stateURL
        load()
        wireHosts()
        loaded = true
    }

    // MARK: Lifecycle

    func bootstrap() {
        guard !bootstrapped else { return }
        bootstrapped = true
        applyAppearance()
        appearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.applyTerminalTheme() }
        }
        startMCP()
        reloadSkills()
        bootstrapTask = Task { [weak self] in
            guard let self else { return }
            await skillLibrary.waitUntilLoaded()
            guard !Task.isCancelled else { return }
            if settings.openDefaultsWhenEmpty { openDefaultSessions(start: false) }
            for session in sessions where session.autoStart { startSession(session.id) }
        }
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.statusTick() }
        }
        addLog(source: "app", message: "AgentDeck started. MCP endpoint: \(mcpBaseURL)/mcp")
    }

    func shutdown() {
        bootstrapTask?.cancel()
        skillLibrary.stop()
        bootstrapped = false
        statusTimer?.invalidate()
        appearanceObserver = nil
        saveTask?.cancel()
        saveNow()
        for s in sessions {
            terminals.dispose(id: s.id)
            browsers.dispose(id: s.id)
        }
        mcp?.stop()
    }

    func openDefaultSessions(start: Bool = true) {
        guard canSave, sessions.isEmpty else { return }
        for session in DefaultSessions.make(profiles: cliProfiles, workingDirectory: settings.defaultWorkingDirectory) {
            addSession(session, start: start)
        }
        focusedSessionID = sessions.first?.id
    }

    var skillsCatalogURL: URL {
        storageURL.deletingLastPathComponent().appendingPathComponent("skills/catalog.md")
    }

    func reloadSkills() {
        skillLibrary.reload(
            directories: settings.skillDirectories, disabledIDs: settings.disabledSkillIDs, catalogURL: skillsCatalogURL
        )
    }

    // MARK: Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let st: PersistedState
        do {
            st = try dec.decode(PersistedState.self, from: Data(contentsOf: storageURL))
        } catch {
            canSave = false
            lastError =
                "Could not load saved state at \(storageURL.path). The original file is preserved: \(error.localizedDescription)"
            return
        }
        sessions = SessionOrdering.ordered(st.sessions)
        tasks = st.tasks
        nextTaskID = max(st.nextTaskID, (tasks.map(\.id).max() ?? 0) + 1)
        log = Array(st.log.suffix(500))
        settings = st.settings
        cliProfiles = st.cliProfiles.isEmpty ? CLIProfile.builtins : st.cliProfiles
        if !st.unrestrictedCLIDefaultsApplied {
            cliProfiles = cliProfiles.map { $0.migratingUnrestrictedDefault() }
        }
        // Make sure new built-in profiles show up for users with an older profile list.
        for b in CLIProfile.builtins where !cliProfiles.contains(where: { $0.id == b.id }) { cliProfiles.append(b) }
        selectedPaneTabs = st.selectedPaneTabs
        focusedSessionID = session(st.focusedSessionID)?.id
        if let focused = session(focusedSessionID) { selectedPaneTabs[focused.paneID] = focused.id }
        cliProfiles = cliProfiles.map { $0.adoptingBriefingAndResumeDefaults() }
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
        guard canSave else { return }
        var st = PersistedState()
        st.sessions = sessions
        st.tasks = tasks
        st.nextTaskID = nextTaskID
        st.log = Array(log.suffix(500))
        st.settings = settings
        st.cliProfiles = cliProfiles
        st.focusedSessionID = focusedSessionID
        st.selectedPaneTabs = selectedPaneTabs
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try enc.encode(st).write(to: storageURL, options: .atomic)
        } catch {
            lastError = "Could not save state: \(error.localizedDescription)"
        }
    }

    // MARK: Hosts

    private func wireHosts() {
        terminals.onOutput = { [weak self] id in
            self?.outputTimes[id] = Date()
        }
        terminals.onExit = { [weak self] id, code in
            guard let self else { return }
            self.runtime[id]?.isRunning = false
            self.runtime[id]?.exitCode = code
            self.setStatus(id, (code ?? 0) == 0 ? .exited : .error)
            self.addLog(
                source: self.name(of: id), message: "process exited (code \(code.map(String.init) ?? "signal"))",
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
        guard !r.isEmpty else { return nil }
        if r.lowercased() == "me" || r.lowercased() == "self", let caller { return session(caller) }
        if let u = UUID(uuidString: r), let s = session(u) { return s }
        if let s = sessions.first(where: { $0.name.caseInsensitiveCompare(r) == .orderedSame }) { return s }
        if let s = sessions.first(where: { $0.id.uuidString.lowercased().hasPrefix(r.lowercased()) && r.count >= 6 }) {
            return s
        }
        let candidates = sessions.filter { $0.name.lowercased().hasPrefix(r.lowercased()) }
        return candidates.count == 1 ? candidates.first : nil
    }

    func font(for session: ManagedSession) -> NSFont {
        let size = session.fontSizeOverride ?? settings.globalFontSize
        return NSFont(name: settings.fontName, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    func applyFonts() {
        for s in sessions where s.kind == .cli { terminals.setFont(id: s.id, font(for: s)) }
    }

    @discardableResult
    func addSession(_ s: ManagedSession, start: Bool = true) -> ManagedSession {
        var s = s
        if s.kind == .cli, let p = profile(for: s), !p.supportsMCP { s.autoInjectContext = false }
        sessions.append(s)
        sessions = SessionOrdering.ordered(sessions)
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
    func mcpConfigPath(for id: UUID) -> String {
        storageURL.deletingLastPathComponent().appendingPathComponent("mcp").appendingPathComponent(
            "\(id.uuidString).json"
        ).path
    }

    private func writeMCPConfig(for id: UUID) throws {
        let cfg: [String: Any] = ["mcpServers": ["agentdeck": ["type": "http", "url": mcpURL(for: id)]]]
        let data = try JSONSerialization.data(withJSONObject: cfg, options: [.prettyPrinted])
        let url = URL(fileURLWithPath: mcpConfigPath(for: id))
    func briefingPath(for id: UUID) -> String {
        storageURL.deletingLastPathComponent().appendingPathComponent("briefing").appendingPathComponent(
            "\(id.uuidString).md"
        ).path
    }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// True when this launch should run the profile's resume command: the session asks for it, the profile has
    /// one, and the provider's storage shows a conversation for the directory (or cannot be inspected).
    func shouldResume(_ s: ManagedSession) -> Bool {
        guard s.resumeLastConversation, let profile = profile(for: s), profile.canResume else { return false }
        return ResumeDetection.hasPriorConversation(profileID: profile.id, cwd: s.effectiveDirectory) ?? true
    }

    func launchCommand(for s: ManagedSession, resume: Bool? = nil) -> String {
        guard let profile = profile(for: s) else { return "" }
        return CommandTemplate.expand(
            template,
            values: [
                "mcpUrl": mcpURL(for: s.id), "mcpConfigPath": mcpConfigPath(for: s.id),
                "sessionId": s.id.uuidString, "sessionName": s.name, "cwd": s.effectiveDirectory,
        let template = (resume ?? shouldResume(s)) ? (profile.resumeCommand ?? profile.command) : profile.command
            ])
    }

    func environment(for s: ManagedSession) -> [String: String] {
                "briefingPath": briefingPath(for: s.id),
        var env = ProcessInfo.processInfo.environment
        // Nested launches: a parent Claude Code / Codex session must not leak its markers into the child.
        for k in env.keys where k.hasPrefix("CLAUDE") || k.hasPrefix("CODEX_") { env[k] = nil }
        env["TERM"] = "xterm-256color"
    /// The start-up briefing as a file, so a provider can take it as a system prompt instead of a typed message.
    func briefingText(for s: ManagedSession) -> String {
        var parts = [briefing(for: s)]
        if s.autoInjectContext { parts.append(contextSummary(for: s)) }
        if !skillLibrary.enabledSkills.isEmpty { parts.append(skillsInstruction) }
        return parts.joined(separator: "\n\n") + "\n"
    }

    private var skillsInstruction: String {
        "[AgentDeck skills] Read the skill catalog at \(skillsCatalogURL.path) and load relevant SKILL.md instructions before working. MCP clients can also call list_skills and read_skill. Relative skill references resolve against the skill's own directory."
    }

    private func writeBriefing(for s: ManagedSession) throws {
        let url = URL(fileURLWithPath: briefingPath(for: s.id))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(briefingText(for: s).utf8).write(to: url, options: .atomic)
    }

        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "AgentDeck"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        env["AGENTDECK_SESSION_ID"] = s.id.uuidString
        env["AGENTDECK_SESSION_NAME"] = s.name
        env["AGENTDECK_MCP_URL"] = mcpURL(for: s.id)
        env["AGENTDECK_MCP_CONFIG"] = mcpConfigPath(for: s.id)
        env["AGENTDECK_SKILLS_FILE"] = skillsCatalogURL.path
        env["AGENTDECK_SKILL_DIRECTORIES"] =
            (try? String(data: JSONEncoder().encode(settings.skillDirectories.map(\.expandingTilde)), encoding: .utf8))
            ?? "[]"
        let additionalPaths = [
        env["AGENTDECK_BRIEFING"] = briefingPath(for: s.id)
            NSHomeDirectory() + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
        ]
        env["PATH"] = ([env["PATH"] ?? ""] + additionalPaths).joined(separator: ":")
        return env
    }

    func startSession(_ id: UUID) {
        guard let s = session(id), runtime[id]?.isRunning != true else { return }
        var rt = runtime[id] ?? SessionRuntime()
        rt.status = .starting
        rt.statusSince = Date()
        rt.startedAt = Date()
        rt.exitCode = nil
        rt.pendingQuestion = nil
        rt.programState = nil
        rt.initialPromptSent = false
        rt.lastOutputAt = nil
        outputTimes[id] = nil
        rt.programMessage = nil
        rt.modelName = nil
        rt.contextInfo = nil
        rt.resumed = false
        rt.injectionReadyAt = nil
        rt.generation += 1
        rt.isRunning = true
        runtime[id] = rt
        switch s.kind {
        case .cli:
            // A prior child may still be winding down after Stop or natural exit.
            terminals.dispose(id: id)
            let cwd = s.effectiveDirectory.expandingTilde
            do {
                guard profile(for: s) != nil else {
                    throw ShellError.failed("Select an existing CLI profile before starting this session")
                }
                try writeMCPConfig(for: id)
                try FileManager.default.createDirectory(atPath: cwd, withIntermediateDirectories: true)
            } catch {
                runtime[id]?.isRunning = false
                setStatus(id, .error)
                lastError = "Session could not start: \(error.localizedDescription)"
                return
            }
                if profile(for: s)?.supportsMCP == true { try writeBriefing(for: s) }
            let resume = shouldResume(s)
            runtime[id]?.resumed = resume
            let command = launchCommand(for: s, resume: resume)
            terminals.start(id: id, command: command, cwd: cwd, environment: environment(for: s), font: font(for: s))
            addLog(
                source: s.name,
                message: "\(resume ? "resumed" : "launched"): \(command) in \(cwd.abbreviatingHome)")
        case .browser:
            _ = browsers.controller(for: s, sharedProfileID: settings.sharedBrowserProfileID)
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
        runtime[id]?.isRunning = false
        startSession(id)
    }

    func stopSession(_ id: UUID) {
        guard let s = session(id) else { return }
        pendingInjections[id] = nil
        runtime[id]?.generation += 1
        runtime[id]?.isRunning = false
        setStatus(id, .exited)
        switch s.kind {
        case .cli: terminals.terminate(id: id)
        case .browser:
            browsers.dispose(id: id)
            runtime[id]?.isRunning = false
            setStatus(id, .exited)
        }
    }

    func setBrowserProfileMode(_ mode: BrowserProfileMode, for id: UUID) {
        guard var session = session(id), session.kind == .browser, session.browserProfileMode != mode else { return }
        let wasRunning = browsers.isRunning(id)
        session.browserProfileMode = mode
        updateSession(session)
        if wasRunning { restartSession(id) }
    }

    func removeSession(_ id: UUID, deleteWorktree: Bool = false, deleteBrowserProfile: Bool = false) {
        guard let s = session(id) else { return }
        if deleteWorktree, let repo = s.worktreeRepo, let path = s.worktreePath {
            guard
                !sessions.contains(where: { $0.id != id && $0.effectiveDirectory.expandingTilde == path.expandingTilde }
                )
            else {
                lastError = "This worktree is used by another session. Remove those sessions before deleting it."
                return
            }
            stopSession(id)
            Task {
                do {
                    try await Worktree.remove(repo: repo, path: path)
                    removeSession(id, deleteBrowserProfile: deleteBrowserProfile)
                } catch { lastError = "Worktree removal failed; session retained: \(error.localizedDescription)" }
            }
            return
        }
        terminals.dispose(id: id)
        browsers.dispose(id: id)
        if deleteBrowserProfile, s.kind == .browser, s.browserProfileMode == .isolated,
            s.browserProfileID != settings.sharedBrowserProfileID,
            !sessions.contains(where: { $0.id != id && $0.browserProfileID == s.browserProfileID })
        {
            BrowserHost.deleteProfile(s.browserProfileID)
        }
        try? FileManager.default.removeItem(atPath: mcpConfigPath(for: id))
        let tabs = pane(containing: id)?.tabs ?? []
        let index = tabs.firstIndex(where: { $0.id == id }) ?? 0
        let remaining = tabs.filter { $0.id != id }
        let replacement = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
        sessions.removeAll { $0.id == id }
        runtime[id] = nil
        pendingInjections[id] = nil
        try? FileManager.default.removeItem(atPath: briefingPath(for: id))
        if selectedPaneTabs[s.paneID] == id { selectedPaneTabs[s.paneID] = replacement }
        if remaining.isEmpty { selectedPaneTabs[s.paneID] = nil }
        if maximizedSessionID == id { maximizedSessionID = replacement }
        if focusedSessionID == id { focusedSessionID = replacement ?? sessions.first?.id }
        for i in tasks.indices where tasks[i].ownerSessionID == id { tasks[i].ownerSessionID = nil }
        addLog(source: "app", message: "session \"\(s.name)\" removed")
        scheduleSave()
        // A CLI session's private browser goes with it, profile included.
        for companion in sessions.filter({ $0.agentOwnerID == id }) {
            removeSession(companion.id, deleteBrowserProfile: true)
        }
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
        case .system:
            return (NSApp as NSApplication?)?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }

    func applyAppearance() {
        switch settings.appearance {
        case .system: app.appearance = nil
        case .light: app.appearance = NSAppearance(named: .aqua)
        case .dark: app.appearance = NSAppearance(named: .darkAqua)
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
        guard let s = session(id) else { return }
        for index in sessions.indices where sessions[index].paneID == s.paneID { sessions[index].paneSize = size }
        scheduleSave()
    }

    func paneSize(for s: ManagedSession) -> PaneSize { s.paneSize ?? settings.defaultPanePreset.size }

    // MARK: Canvas

    static let canvasSpacing = CanvasLayout.spacing

    /// Bring a pane to the front of the canvas.
    func raisePane(_ id: UUID) {
        guard let s = session(id) else { return }
        let top = sessions.map(\.zIndex).max() ?? 0
        if s.zIndex < top || panes.filter({ $0.activeSession.zIndex == top }).count > 1 {
            for index in sessions.indices where sessions[index].paneID == s.paneID { sessions[index].zIndex = top + 1 }
            scheduleSave()
        }
    }

    func setCanvasPosition(for id: UUID, _ p: PanePoint?) {
        guard let s = session(id) else { return }
        let position = p.map { PanePoint(x: max(0, $0.x), y: max(0, $0.y)) }
        for index in sessions.indices where sessions[index].paneID == s.paneID {
            sessions[index].canvasPosition = position
        }
        scheduleSave()
    }

    /// Give every pane that has no canvas position one, flowing after the existing panes.
    func ensureCanvasPositions(viewportWidth: Double) {
        let missing = panes.map(\.activeSession).filter { $0.canvasPosition == nil }
        // A tiny width means the window has not been laid out yet; wait for the real size.
        guard !missing.isEmpty, viewportWidth > 500 else { return }
        let placed = panes.map(\.activeSession).filter { $0.canvasPosition != nil }
        var y =
            placed.map { ($0.canvasPosition?.y ?? 0) + paneSize(for: $0).height }.max().map { $0 + Self.canvasSpacing }
        guard let app = NSApp as NSApplication? else { return }
            ?? Self.canvasSpacing
        var x = Self.canvasSpacing
        var rowH = 0.0
        let width = viewportWidth
        for s in missing {
            let size = paneSize(for: s)
            if x > Self.canvasSpacing, x + size.width > width {
                x = Self.canvasSpacing
                y += rowH + Self.canvasSpacing
                rowH = 0
            }
            setCanvasPosition(for: s.id, PanePoint(x: x, y: y))
            x += size.width + Self.canvasSpacing
            rowH = max(rowH, size.height)
        }
    }

    /// Re-pack all panes left-to-right into the viewport width, keeping their sizes.
    func tidyCanvas(viewportWidth: Double) {
        var x = Self.canvasSpacing
        var y = Self.canvasSpacing
        var rowH = 0.0
        let width = max(viewportWidth, 600)
        for s in panes.map(\.activeSession) {
            let size = paneSize(for: s)
            if x > Self.canvasSpacing, x + size.width > width {
                x = Self.canvasSpacing
                y += rowH + Self.canvasSpacing
                rowH = 0
            }
            setCanvasPosition(for: s.id, PanePoint(x: x, y: y))
            x += size.width + Self.canvasSpacing
            rowH = max(rowH, size.height)
        }
    }

    /// Size and position all panes in the measured visible canvas, independent of focus/z-order.
    func fillCanvas() {
        let ordered = panes
        let frames = CanvasLayout.frames(count: ordered.count, viewport: canvasViewport)
        guard frames.count == ordered.count, !frames.isEmpty else { return }
        settings.layoutMode = .canvas
        maximizedSessionID = nil
        let framesByPane = Dictionary(uniqueKeysWithValues: zip(ordered.map(\.id), frames))
        sessions = sessions.map { session in
            guard let frame = framesByPane[session.paneID] else { return session }
            var session = session
            session.canvasPosition = PanePoint(x: frame.minX, y: frame.minY)
            session.paneSize = PaneSize(width: frame.width, height: frame.height)
            return session
        }
        scheduleSave()
    }

    // MARK: Injection

    /// Type `text` into a CLI session as if the user had typed it. Multi-line text is collapsed to one line.
    func inject(_ id: UUID, text: String, submit: Bool = true, source: String = "user", queueIfBusy: Bool = false)
        -> Bool
    {
        guard let s = session(id), s.kind == .cli else { return false }
        if source != "user" || queueIfBusy {
            guard profile(for: s)?.supportsMCP == true else { return false }
        }
        let line = text.singleLine
        guard !line.isEmpty else { return false }
        guard runtime[id]?.isRunning == true else { return false }
        if queueIfBusy, !(runtime[id]?.status.acceptsInjection ?? false) {
            pendingInjections[id, default: []].append(line)
            addLog(source: source, message: "queued message for \"\(s.name)\" (busy): \(line.prefix(80))")
            return true
        }
        let delay = Double(max(0, min(2000, profile(for: s)?.submitDelayMs ?? 150))) / 1000
        let generation = runtime[id]?.generation
        let terminal = terminals.view(for: id)
        terminals.send(id: id, text: line)
        if submit {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak terminal] in
                guard let self, let terminal, self.runtime[id]?.isRunning == true,
                    self.runtime[id]?.generation == generation, self.terminals.view(for: id) === terminal
                else { return }
                self.terminals.send(id: id, text: "\r")
            }
        }
        runtime[id]?.lastOutputAt = Date()
        runtime[id]?.injectionReadyAt = Date().addingTimeInterval(max(delay, settings.idleAfterSeconds))
        setStatus(id, .working)
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
            if let seen = outputTimes[s.id], seen > (rt.lastOutputAt ?? .distantPast) { rt.lastOutputAt = seen }
            if let ready = rt.injectionReadyAt, now < ready { continue }
            let lines = terminals.visibleLines(id: s.id)
            rt.lastLines = Array(lines.suffix(12))
            let ev = StatusHeuristics.evaluate(
                lines: lines, lastOutputAt: rt.lastOutputAt, startedAt: rt.startedAt,
                settings: settings, programState: rt.programState, now: now)
            var st = ev.status
            if rt.status == .starting, now.timeIntervalSince(rt.startedAt ?? now) < 2 { st = .starting }
            rt.pendingQuestion = ev.pendingQuestion
            let stats = StatusHeuristics.modelStats(lines: lines)
            if let m = stats.model { rt.modelName = m }
            if let c = stats.context { rt.contextInfo = c }
            if rt != runtime[s.id] { runtime[s.id] = rt }
            setStatus(s.id, st)
            if st == .idle {
                flushPending(s.id)
                deliverFirstMessageIfNeeded(s)
            }
        }
    }

    private func deliverFirstMessageIfNeeded(_ s: ManagedSession) {
        guard var rt = runtime[s.id], rt.status.acceptsInjection, !rt.initialPromptSent else { return }
        rt.initialPromptSent = true
        runtime[s.id] = rt
        guard !rt.resumed, let profile = profile(for: s) else { return }
        var parts: [String] = []
        let pointer = profile.supportsMCP && !profile.deliversBriefingInCommand
        if pointer { parts.append("[AgentDeck] Read your briefing at \(briefingPath(for: s.id)) before working.") }
        if let p = s.initialPrompt?.singleLine, !p.isEmpty { parts.append(pointer ? "Your first task: \(p)" : p) }
        guard !parts.isEmpty else { return }
        _ = inject(s.id, text: parts.joined(separator: " "), source: pointer ? "context" : "user")
    }

    // MARK: Context awareness

    func briefing(for s: ManagedSession) -> String {
        let role =
            s.isOrchestrator
            ? "You are the Orchestrator: you may also call recruit_session (user approves) and assign work." : ""
        return
            "[AgentDeck] You are managed session \"\(s.name)\" (\(profile(for: s)?.name ?? "CLI")) in \(s.effectiveDirectory.abbreviatingHome). Other agents run in sibling sessions. Coordinate only through the agentdeck MCP tools: list_sessions, read_board, create_task, update_task, handoff, send_message, log. Claim a task with update_task(owner=me, status=in-progress) before working on it and mark it done when finished. For anything on the web use your private AgentDeck browser (browser_navigate, browser_read, browser_click, browser_type, browser_screenshot, browser_eval) and never the user's own browser. \(role)"
            .singleLine
    }

    func contextSummary(for target: ManagedSession) -> String {
        let sess = sessions.filter { $0.agentOwnerID == nil }.map { s -> String in
            let st = status(of: s.id).label.lowercased()
            return s.id == target.id
                ? "\(s.name) (\(st), you)" : "\(s.name) (\(st)\(s.kind == .browser ? ", browser" : ""))"
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

    /// Status summaries are only ever sent on an explicit request (menu, inspector, pane menu); nothing broadcasts
    /// board or session changes to other sessions on its own.
    func injectContextNow(_ id: UUID) {
        guard let s = session(id) else { return }
        _ = inject(id, text: contextSummary(for: s), source: "context", queueIfBusy: true)
    }

    // MARK: Task board

    @discardableResult
    func createTask(
        title: String, description: String = "", owner: UUID? = nil, status: TaskStatus = .todo,
        notes: String = "", createdBy: String = "user"
    ) -> BoardTask {
        let t = BoardTask(
            id: nextTaskID, title: title, description: description, ownerSessionID: owner,
            status: status, notes: notes, createdBy: createdBy)
        nextTaskID += 1
        tasks.append(t)
        addLog(source: createdBy, message: "task #\(t.id) created: \(title)")
        scheduleSave()
        return t
    /// The briefing itself lives in a file (see `briefingText`). Providers whose command takes `{briefingPath}`
    /// get it as a system prompt and nothing is typed; others get one short pointer line. A resumed conversation
    /// already saw its briefing and first prompt, so nothing is typed at all.
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
    func handoff(
        from caller: UUID?, to target: ManagedSession, taskID: Int?, title: String?, description: String?,
        note: String?
    ) throws -> (task: BoardTask, delivered: Bool) {
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
            task = createTask(
                title: title, description: description ?? "", owner: target.id,
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
            let idle = runtime[target.id]?.status.acceptsInjection == true
            delivered = inject(target.id, text: msg, source: source, queueIfBusy: true) && idle
        }
        return (task, delivered)
    }

    // MARK: Recruits

    func requestRecruit(_ r: RecruitRequest) {
        recruits.append(r)
        addLog(
            source: r.requestedByName,
            message: "requests a new session \"\(r.name)\" (\(r.kind.label)) — approve in the sidebar", level: .warn)
        NSApp.requestUserAttention(.informationalRequest)
    }

    func approveRecruit(_ id: UUID) {
        Task { await approveRecruitAsync(id) }
    }

    func approveRecruitAsync(_ id: UUID) async {
        guard let i = recruits.firstIndex(where: { $0.id == id }), recruits[i].status == .pending,
            approvingRecruits.insert(id).inserted
        else { return }
        defer { approvingRecruits.remove(id) }
        var r = recruits[i]
        var s = ManagedSession(name: r.name, kind: r.kind)
        if r.kind == .cli {
            s.cliProfileID = r.cliProfileID
            s.workingDirectory = r.workingDirectory
            s.initialPrompt = r.initialPrompt
            if r.useWorktree {
                do {
                    let wt = try await Worktree.create(
                        repoDir: r.workingDirectory, slug: r.name.slug, root: settings.worktreeRoot)
                    s.worktreePath = wt.path
                    s.worktreeBranch = wt.branch
                    s.worktreeRepo = wt.repo
                } catch {
                    lastError = "Worktree creation failed: \(error.localizedDescription)"
                    return
                }
            }
        } else {
            s.url = r.url ?? BrowserPreset.chatgpt.url
        }
        let created = addSession(s)
        r.status = .approved
        r.createdSessionID = created.id
        recruits[i] = r
        if let by = r.requestedBy {
            _ = inject(
                by,
                text:
                    "[AgentDeck] Your recruit request was approved: session \"\(created.name)\" (id \(created.id.uuidString)) is starting. Use handoff to give it work.",
                source: "app", queueIfBusy: true)
        }
    }

    func denyRecruit(_ id: UUID) {
        guard let i = recruits.firstIndex(where: { $0.id == id }), recruits[i].status == .pending,
            !approvingRecruits.contains(id)
        else { return }
        recruits[i].status = .denied
        if let by = recruits[i].requestedBy {
            _ = inject(
                by, text: "[AgentDeck] Your recruit request \"\(recruits[i].name)\" was denied by the user.",
                source: "app", queueIfBusy: true)
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
        mcp = nil
        guard let port = UInt16(exactly: settings.mcpPort), port > 0 else {
            mcpStatus = "failed: port must be between 1 and 65535"
            return
        }
        let server = MCPServer(port: port) { [weak self] method, path, body in
            guard let self else { return (500, Data(), "text/plain") }
            return await self.handleHTTP(method: method, path: path, body: body)
        }
        server.onStateChange = { [weak self] status in self?.mcpStatus = status }
        do {
            try server.start()
            mcp = server
            mcpStatus = "starting on \(mcpBaseURL)"
        } catch {
            mcpStatus = "failed: \(error.localizedDescription)"
            addLog(source: "mcp", message: "server failed to start: \(error.localizedDescription)", level: .error)
        }
    }
}
