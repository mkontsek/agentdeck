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
    case grid, freeform
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
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
             initialPrompt, url, browserProfileID, fontSizeOverride, paneSize, isOrchestrator, autoInjectContext, autoStart
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
}

// MARK: - Orchestration log

enum LogLevel: String, Codable { case info, warn, error }

struct LogEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var at: Date = Date()
    var source: String
    var message: String
    var level: LogLevel = .info
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
    var layoutMode: LayoutMode = .grid
    var mcpPort: Int = 4820
    var contextInjectionEnabled: Bool = true
    var contextInjectionIntervalSeconds: Double = 300
    var idleAfterSeconds: Double = 4
    var stallAfterSeconds: Double = 90
    var worktreeRoot: String = "~/.agentdeck/worktrees"
    var showInspector: Bool = true
    var showBottomPanel: Bool = true
    var bottomPanelHeight: Double = 240

    init() {}

    enum CodingKeys: String, CodingKey {
        case globalFontSize, fontName, defaultPanePreset, gridColumns, layoutMode, mcpPort, contextInjectionEnabled,
             contextInjectionIntervalSeconds, idleAfterSeconds, stallAfterSeconds, worktreeRoot, showInspector,
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
        sessions = c.value(.sessions, default: [])
        tasks = c.value(.tasks, default: [])
        nextTaskID = c.value(.nextTaskID, default: 1)
        log = c.value(.log, default: [])
        settings = c.value(.settings, default: AppSettings())
        cliProfiles = c.value(.cliProfiles, default: CLIProfile.builtins)
        focusedSessionID = c.value(.focusedSessionID, default: nil)
    }
}

// MARK: - Helpers

extension KeyedDecodingContainer {
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
