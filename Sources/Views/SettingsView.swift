import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gear") }
            OrchestrationSettings().tabItem {
                Label("Orchestration", systemImage: "point.3.connected.trianglepath.dotted")
            }
            ProfilesSettings().tabItem { Label("CLI Profiles", systemImage: "terminal") }
            SkillsSettingsView().tabItem { Label("Skills", systemImage: "books.vertical") }
        }
        .frame(width: 780, height: 620)
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Open default sessions when the canvas is empty", isOn: $store.settings.openDefaultsWhenEmpty)
                TextField("Default CLI directory", text: $store.settings.defaultWorkingDirectory)
            }
            Section("Downloads") {
                HStack {
                    TextField(
                        "Download directory", text: $store.settings.downloadDirectory,
                        prompt: Text(DownloadLocation.defaultSetting))
                    Button("Choose…", action: chooseDownloadDirectory)
                }
                Text("Browser panes save files in this folder. It starts as the Mac Downloads directory.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Browser sign-ins") {
                Toggle("New agent browsers share AgentDeck sign-ins", isOn: $store.settings.shareAgentBrowserSignIns)
                Text("Browser panes share AgentDeck’s saved sign-ins by default, including after restarting the app.")
                Text(
                    "Sign in once per service. Signing out affects other shared panes for that service. Choose Separate account in a pane’s inspector for an independent login."
                )
                .font(.caption).foregroundStyle(.secondary)
                Text(
                    "Login cookies and website storage stay in a persistent local WebKit profile under your macOS account. AgentDeck does not save your account password. Websites can still expire or revoke a session."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Section("Text") {
                HStack {
                    Slider(value: $store.settings.globalFontSize, in: 8...32, step: 1) { Text("Global font size") }
                    Text("\(Int(store.settings.globalFontSize)) pt").monospacedDigit().frame(width: 44)
                }
                TextField("Font name", text: $store.settings.fontName)
                Text(
                    "Any installed monospaced font, e.g. Menlo, SF Mono, JetBrains Mono. ⌘+ / ⌘− / ⌘0 change the focused pane only."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Section("Appearance") {
                Picker("Theme", selection: $store.settings.appearance) {
                    ForEach(AppAppearance.allCases) { Label($0.label, systemImage: $0.systemImage).tag($0) }
                }.pickerStyle(.segmented)
                Text("Terminal panes and embedded web pages follow the theme. ⌥⌘D flips between light and dark.")
                    .font(.caption).foregroundStyle(.secondary)
                ColorPicker(
                    "Canvas arrows",
                    selection: Binding(
                        get: { CanvasArrowColor.color(hex: store.settings.arrowColorHex) },
                        set: { store.settings.arrowColorHex = CanvasArrowColor.hex(color: $0) }),
                    supportsOpacity: false)
                Text("Arrow color is independent of the focused window border. Dashed arrows identify browsers.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Panes") {
                Picker("Layout", selection: $store.settings.layoutMode) {
                    ForEach(LayoutMode.allCases) { Text($0.label).tag($0) }
                }
                Stepper("Grid columns: \(store.settings.gridColumns)", value: $store.settings.gridColumns, in: 1...4)
                Picker("Default pane size", selection: $store.settings.defaultPanePreset) {
                    ForEach(PaneSizePreset.allCases) { p in
                        Text("\(p.label) (\(Int(p.size.width))×\(Int(p.size.height)))").tag(p)
                    }
                }
                Text(
                    "Drag the bottom-right grip to resize (double-click it to reset). Resizing a grid pane switches to Canvas. In Canvas, drag the header to move; ⌥⌘T tidies panes."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func chooseDownloadDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = DownloadLocation.directory(from: store.settings.downloadDirectory)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.settings.downloadDirectory = url.standardizedFileURL.path.abbreviatingHome
    }
}

private struct OrchestrationSettings: View {
    @EnvironmentObject var store: AppStore
    @State private var port: Int = 4820

    var body: some View {
        Form {
            Section("MCP server") {
                HStack {
                    TextField("Port", value: $port, format: .number)
                    Button("Apply & restart server") {
                        store.settings.mcpPort = port
                        store.startMCP()
                    }
                    .disabled(!(1...65535).contains(port))
                }
                Text("Status: \(store.mcpStatus)").font(.caption).foregroundStyle(.secondary)
                Text(
                    "Sessions connect to \(store.mcpBaseURL)/mcp/<session-id>. Running CLI sessions need a restart after a port change."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Section("Briefing and context") {
                Toggle(
                    "Automatically delegate substantial tasks to subagents", isOn: $store.settings.automaticSubagents)
                Stepper(
                    "Concurrent workers per conversation: \(store.settings.maximumConcurrentSubagents)",
                    value: $store.settings.maximumConcurrentSubagents, in: SubagentLimits.concurrentWorkers)
                Text(
                    "Workers open in their own movable mini-windows, connected to the main conversation. Each worker's browser tabs have a separate connected window. Workers cannot spawn more workers; completion approval stays unchanged."
                )
                .font(.caption).foregroundStyle(.secondary)
                Toggle("Approve agent handoffs before delivery", isOn: $store.settings.approveAgentHandoffs)
                Text("Review the exact shared package in the Work board. Completion approval is controlled per task.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(
                    "Built-in agents retain AgentDeck instructions across conversation resets. Claude, Codex and Grok receive launch instructions; Gemini and Antigravity load a persistent rule that reads their session briefing. Restart existing CLI processes after upgrading. Custom profiles can use briefing placeholders; otherwise they receive a one-time pointer. Send updated board context with Session › Inject Context Now."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Section("Status detection") {
                HStack {
                    Slider(value: $store.settings.idleAfterSeconds, in: 1...30, step: 1) { Text("Idle after quiet") }
                    Text("\(Int(store.settings.idleAfterSeconds)) s").frame(width: 40)
                }
                HStack {
                    Slider(value: $store.settings.stallAfterSeconds, in: 30...600, step: 15) { Text("Stalled after") }
                    Text("\(Int(store.settings.stallAfterSeconds)) s").frame(width: 40)
                }
            }
            Section("Git worktrees") {
                TextField("Worktree root", text: $store.settings.worktreeRoot)
                Text("New worktrees are created at <root>/<repo>/<session-slug> on branch agentdeck/<session-slug>.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { port = store.settings.mcpPort }
    }
}
