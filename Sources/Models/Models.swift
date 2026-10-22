import Foundation

// MARK: - Sessions

enum SessionKind: String, Codable, CaseIterable, Identifiable {
    case cli, browser
    var id: String { rawValue }
    var label: String { self == .cli ? "CLI" : "Browser" }
    var systemImage: String { self == .cli ? "terminal" : "globe" }
}

enum SessionStatus: String, Codable, CaseIterable {
    case starting, working, idle, waitingForUser, stalled, error, quotaWarning, exited

    var label: String {
        switch self {
        case .starting: return "Starting"
        case .working: return "Working"
        case .idle: return "Idle"
        case .waitingForUser: return "Waiting for user"
        case .stalled: return "Stalled"
        case .error: return "Error"
        case .quotaWarning: return "Quota warning"
        case .exited: return "Exited"
        }
    }

    var systemImage: String {
        switch self {
        case .starting: return "hourglass"
        case .working: return "bolt.fill"
        case .idle: return "pause.circle"
        case .waitingForUser: return "questionmark.circle.fill"
        case .stalled: return "exclamationmark.triangle"
        case .error: return "xmark.octagon.fill"
        case .quotaWarning: return "gauge.with.dots.needle.100percent"
        case .exited: return "stop.circle"
        }
    }

    /// True when the agent is not in the middle of a turn and can safely receive injected text.
    var acceptsInjection: Bool { self == .idle }
}

struct PaneSize: Codable, Hashable {
    var width: Double
    var height: Double
}

enum PaneSizePreset: String, Codable, CaseIterable, Identifiable {
    case compact, normal, large
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var size: PaneSize {
        switch self {
        case .compact: return PaneSize(width: 440, height: 300)
        case .normal: return PaneSize(width: 640, height: 440)
        case .large: return PaneSize(width: 960, height: 640)
        }
    }
}

enum LayoutMode: String, Codable, CaseIterable, Identifiable {
    case grid, canvas
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum AppAppearance: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}

struct PanePoint: Codable, Hashable {
    var x: Double
    var y: Double
}

struct ManagedSession: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var kind: SessionKind
    var createdAt: Date = Date()

    // CLI
    var cliProfileID: String? = nil
    var workingDirectory: String = NSHomeDirectory()
    var worktreePath: String? = nil
    var worktreeBranch: String? = nil
    var worktreeRepo: String? = nil
    var initialPrompt: String? = nil

    // Browser
    var url: String? = nil
    var browserProfileID: UUID = UUID()

    // UI / behaviour
    var fontSizeOverride: Double? = nil
    var paneSize: PaneSize? = nil
    var canvasPosition: PanePoint? = nil
    var zIndex: Int = 0
    var isOrchestrator: Bool = false
    var autoInjectContext: Bool = true
    var autoStart: Bool = true

    var effectiveDirectory: String { worktreePath ?? workingDirectory }

    init(name: String, kind: SessionKind) {
        self.name = name
        self.kind = kind
    }

    enum CodingKeys: String, CodingKey {
        case id, name, kind, createdAt, cliProfileID, workingDirectory, worktreePath, worktreeBranch, worktreeRepo,
             initialPrompt, url, browserProfileID, fontSizeOverride, paneSize, canvasPosition, zIndex, isOrchestrator,
             autoInjectContext, autoStart
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        name = c.value(.name, default: "Session")
        kind = c.value(.kind, default: .cli)
        createdAt = c.value(.createdAt, default: Date())
        cliProfileID = c.value(.cliProfileID, default: nil)
        workingDirectory = c.value(.workingDirectory, default: NSHomeDirectory())
        worktreePath = c.value(.worktreePath, default: nil)
        worktreeBranch = c.value(.worktreeBranch, default: nil)
        worktreeRepo = c.value(.worktreeRepo, default: nil)
        initialPrompt = c.value(.initialPrompt, default: nil)
        url = c.value(.url, default: nil)
        browserProfileID = c.value(.browserProfileID, default: UUID())
        fontSizeOverride = c.value(.fontSizeOverride, default: nil)
        paneSize = c.value(.paneSize, default: nil)
        canvasPosition = c.value(.canvasPosition, default: nil)
        zIndex = c.value(.zIndex, default: 0)
        isOrchestrator = c.value(.isOrchestrator, default: false)
        autoInjectContext = c.value(.autoInjectContext, default: true)
        autoStart = c.value(.autoStart, default: true)
    }
}

/// Live, non-persisted state of a session.
struct SessionRuntime {
    var status: SessionStatus = .starting
    var statusSince: Date = Date()
    var lastOutputAt: Date? = nil
    var startedAt: Date? = nil
    var pendingQuestion: String? = nil
    var exitCode: Int32? = nil
    var title: String? = nil
    var lastLines: [String] = []
    var programState: String? = nil      // OSC 7501 state if the program reports one
    var programMessage: String? = nil
    var modelName: String? = nil         // parsed from the CLI's own status line, best effort
    var contextInfo: String? = nil       // e.g. "ctx 21%" or "63% context left"

    var lastContextHash: Int? = nil
    var lastContextAt: Date? = nil
    var initialPromptSent: Bool = false
    var isRunning: Bool = false
    var generation: Int = 0
}

// MARK: - Task board

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case todo, inProgress = "in-progress", done, blocked
    var id: String { rawValue }
    var label: String {
        switch self {
        case .todo: return "To do"
        case .inProgress: return "In progress"
        case .done: return "Done"
        case .blocked: return "Blocked"
        }
    }
    var systemImage: String {
        switch self {
        case .todo: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .done: return "checkmark.circle.fill"
        case .blocked: return "hand.raised.fill"
        }
    }
}

struct BoardTask: Codable, Identifiable, Hashable {
    var id: Int
    var title: String
    var description: String = ""
    var ownerSessionID: UUID? = nil
    var status: TaskStatus = .todo
    var notes: String = ""
    var createdBy: String = "user"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: Int, title: String, description: String = "", ownerSessionID: UUID? = nil, status: TaskStatus = .todo,
         notes: String = "", createdBy: String = "user") {
        self.id = id; self.title = title; self.description = description; self.ownerSessionID = ownerSessionID
        self.status = status; self.notes = notes; self.createdBy = createdBy
    }

    enum CodingKeys: String, CodingKey { case id, title, description, ownerSessionID, status, notes, createdBy, createdAt, updatedAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = c.value(.title, default: "Untitled")
        description = c.value(.description, default: "")
        ownerSessionID = c.value(.ownerSessionID, default: nil)
        status = c.value(.status, default: .todo)
        notes = c.value(.notes, default: "")
        createdBy = c.value(.createdBy, default: "user")
        createdAt = c.value(.createdAt, default: Date())
        updatedAt = c.value(.updatedAt, default: Date())
    }
}

// MARK: - Orchestration log

enum LogLevel: String, Codable { case info, warn, error }

struct LogEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var at: Date = Date()
    var source: String
    var message: String
    var level: LogLevel = .info

    init(source: String, message: String, level: LogLevel = .info) {
        self.source = source; self.message = message; self.level = level
    }

    enum CodingKeys: String, CodingKey { case id, at, source, message, level }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        at = c.value(.at, default: Date())
        source = c.value(.source, default: "?")
        message = c.value(.message, default: "")
        level = c.value(.level, default: .info)
    }
}

// MARK: - CLI profiles

/// Describes how to launch a kind of CLI agent. The `command` is a zsh snippet with placeholders:
/// {mcpUrl} {mcpConfigPath} {sessionId} {sessionName} {cwd}
struct CLIProfile: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var command: String
    var submitDelayMs: Int = 150
    var supportsMCP: Bool = true
    var notes: String = ""

    static let builtins: [CLIProfile] = [
        CLIProfile(id: "claude", name: "Claude Code",
                   command: "claude --mcp-config \"{mcpConfigPath}\"",
                   notes: "AgentDeck writes a per-session MCP config file; Claude loads it with --mcp-config."),
        CLIProfile(id: "codex", name: "Codex",
                   command: "codex -c 'mcp_servers.agentdeck.url=\"{mcpUrl}\"'",
                   notes: "Streamable HTTP MCP server injected via -c config override."),
        CLIProfile(id: "gemini", name: "Gemini CLI",
                   command: "gemini",
                   notes: "Run once: gemini mcp add -t http -s user agentdeck {mcpUrl} (session identity is then weaker; use whoami/from_session)."),
        CLIProfile(id: "opencode", name: "OpenCode",
                   command: "opencode",
                   notes: "Add the MCP server in opencode.json: {\"mcp\":{\"agentdeck\":{\"type\":\"remote\",\"url\":\"{mcpUrl}\"}}}"),
        CLIProfile(id: "grok", name: "Grok CLI",
                   command: "grok",
                   notes: "Add the MCP server per the Grok CLI docs; URL is in $AGENTDECK_MCP_URL."),
        CLIProfile(id: "shell", name: "Plain shell",
                   command: "exec ${SHELL:-/bin/zsh} -l",
                   supportsMCP: false,
                   notes: "A login shell. $AGENTDECK_MCP_URL and $AGENTDECK_SESSION_ID are exported."),
    ]
}

// MARK: - Browser presets

enum BrowserPreset: String, CaseIterable, Identifiable {
    case chatgpt, claude, gemini, grok, perplexity, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .chatgpt: return "ChatGPT"
        case .claude: return "Claude.ai"
        case .gemini: return "Gemini"
        case .grok: return "Grok"
        case .perplexity: return "Perplexity"
        case .custom: return "Custom URL"
        }
    }
    var url: String {
        switch self {
        case .chatgpt: return "https://chatgpt.com"
        case .claude: return "https://claude.ai"
        case .gemini: return "https://gemini.google.com"
        case .grok: return "https://grok.com"
        case .perplexity: return "https://www.perplexity.ai"
        case .custom: return "https://"
        }
    }
}

// MARK: - Recruit requests (orchestrator → user approval)

enum RecruitStatus: String, Codable { case pending, approved, denied }

struct RecruitRequest: Identifiable, Hashable {
    var id: UUID = UUID()
    var requestedBy: UUID?
    var requestedByName: String
    var kind: SessionKind
    var name: String
    var cliProfileID: String
    var workingDirectory: String
    var useWorktree: Bool
    var url: String?
    var initialPrompt: String?
    var reason: String
    var status: RecruitStatus = .pending
    var createdSessionID: UUID? = nil
    var createdAt: Date = Date()
}

// MARK: - Settings

struct AppSettings: Codable {
    var globalFontSize: Double = 13
    var fontName: String = "Menlo"
    var defaultPanePreset: PaneSizePreset = .normal
    var gridColumns: Int = 2
    var layoutMode: LayoutMode = .canvas
    var mcpPort: Int = 4820
    var contextInjectionEnabled: Bool = true
    var contextInjectionIntervalSeconds: Double = 300
    var idleAfterSeconds: Double = 4
    var stallAfterSeconds: Double = 90
    var worktreeRoot: String = "~/.agentdeck/worktrees"
    var appearance: AppAppearance = .system
    var showSidebar: Bool = false
    var showInspector: Bool = false
    var showBottomPanel: Bool = false
    var bottomPanelHeight: Double = 240

    init() {}

    enum CodingKeys: String, CodingKey {
        case globalFontSize, fontName, defaultPanePreset, gridColumns, layoutMode, mcpPort, contextInjectionEnabled,
             contextInjectionIntervalSeconds, idleAfterSeconds, stallAfterSeconds, worktreeRoot, appearance, showSidebar, showInspector,
             showBottomPanel, bottomPanelHeight
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        globalFontSize = c.value(.globalFontSize, default: d.globalFontSize)
        fontName = c.value(.fontName, default: d.fontName)
        defaultPanePreset = c.value(.defaultPanePreset, default: d.defaultPanePreset)
        gridColumns = c.value(.gridColumns, default: d.gridColumns)
        layoutMode = c.value(.layoutMode, default: d.layoutMode)
        mcpPort = c.value(.mcpPort, default: d.mcpPort)
        contextInjectionEnabled = c.value(.contextInjectionEnabled, default: d.contextInjectionEnabled)
        contextInjectionIntervalSeconds = c.value(.contextInjectionIntervalSeconds, default: d.contextInjectionIntervalSeconds)
        idleAfterSeconds = c.value(.idleAfterSeconds, default: d.idleAfterSeconds)
        stallAfterSeconds = c.value(.stallAfterSeconds, default: d.stallAfterSeconds)
        worktreeRoot = c.value(.worktreeRoot, default: d.worktreeRoot)
        appearance = c.value(.appearance, default: d.appearance)
        showSidebar = c.value(.showSidebar, default: d.showSidebar)
        showInspector = c.value(.showInspector, default: d.showInspector)
        showBottomPanel = c.value(.showBottomPanel, default: d.showBottomPanel)
        bottomPanelHeight = c.value(.bottomPanelHeight, default: d.bottomPanelHeight)
    }
}

struct PersistedState: Codable {
    var sessions: [ManagedSession] = []
    var tasks: [BoardTask] = []
    var nextTaskID: Int = 1
    var log: [LogEntry] = []
    var settings: AppSettings = AppSettings()
    var cliProfiles: [CLIProfile] = CLIProfile.builtins
    var focusedSessionID: UUID? = nil

    init() {}

    enum CodingKeys: String, CodingKey { case sessions, tasks, nextTaskID, log, settings, cliProfiles, focusedSessionID }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessions = c.lenientArray(.sessions)
        tasks = c.lenientArray(.tasks)
        nextTaskID = c.value(.nextTaskID, default: 1)
        log = c.lenientArray(.log)
        settings = c.value(.settings, default: AppSettings())
        cliProfiles = c.value(.cliProfiles, default: CLIProfile.builtins)
        focusedSessionID = c.value(.focusedSessionID, default: nil)
    }
}

// MARK: - Helpers

private struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

extension KeyedDecodingContainer {
    /// Decodes an array, skipping elements that fail instead of failing the whole array.
    func lenientArray<T: Decodable>(_ key: Key) -> [T] {
        ((try? decodeIfPresent([Lenient<T>].self, forKey: key)) ?? []).compactMap(\.value)
    }

    func value<T: Decodable>(_ key: Key, default defaultValue: T) -> T {
        if let v = try? decodeIfPresent(T.self, forKey: key) { return v }
        return defaultValue
    }
}

extension String {
    var expandingTilde: String { (self as NSString).expandingTildeInPath }
    var abbreviatingHome: String { (self as NSString).abbreviatingWithTildeInPath }
    var slug: String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        let s = lowercased().map { allowed.contains($0) ? $0 : "-" }
        return String(s).replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
    /// Collapse the text to a single line suitable for typing into a CLI input box.
    var singleLine: String {
        components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
}
