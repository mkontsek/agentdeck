import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gear") }
            OrchestrationSettings().tabItem { Label("Orchestration", systemImage: "point.3.connected.trianglepath.dotted") }
            ProfilesSettings().tabItem { Label("CLI Profiles", systemImage: "terminal") }
        }
        .frame(width: 640, height: 460)
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Form {
            Section("Text") {
                HStack {
                    Slider(value: $store.settings.globalFontSize, in: 8...32, step: 1) { Text("Global font size") }
                    Text("\(Int(store.settings.globalFontSize)) pt").monospacedDigit().frame(width: 44)
                }
                TextField("Font name", text: $store.settings.fontName)
                Text("Any installed monospaced font, e.g. Menlo, SF Mono, JetBrains Mono. ⌘+ / ⌘− / ⌘0 change the focused pane only.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Panes") {
                Picker("Layout", selection: $store.settings.layoutMode) { ForEach(LayoutMode.allCases) { Text($0.label).tag($0) } }
                Stepper("Grid columns: \(store.settings.gridColumns)", value: $store.settings.gridColumns, in: 1...4)
                Picker("Default pane size", selection: $store.settings.defaultPanePreset) {
                    ForEach(PaneSizePreset.allCases) { p in Text("\(p.label) (\(Int(p.size.width))×\(Int(p.size.height)))").tag(p) }
                }
                Text("Freeform layout uses per-pane sizes (drag the grip at a pane's corner; double-click it to reset).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
                    Button("Apply & restart server") { store.settings.mcpPort = port; store.startMCP() }
                }
                Text("Status: \(store.mcpStatus)").font(.caption).foregroundStyle(.secondary)
                Text("Sessions connect to \(store.mcpBaseURL)/mcp/<session-id>. Running CLI sessions need a restart after a port change.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Context injection") {
                Toggle("Inject status summaries into idle CLI sessions", isOn: $store.settings.contextInjectionEnabled)
                HStack {
                    Slider(value: $store.settings.contextInjectionIntervalSeconds, in: 60...1800, step: 60) { Text("Minimum interval") }
                    Text("\(Int(store.settings.contextInjectionIntervalSeconds / 60)) min").frame(width: 50)
                }
                Text("A summary is only sent when the board or session list changed since the last one, and only while the session is idle. Each one costs the agent a turn.")
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

private struct ProfilesSettings: View {
    @EnvironmentObject var store: AppStore
    @State private var selected: String?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(store.cliProfiles, selection: $selected) { p in Text(p.name).tag(p.id) }
                Divider()
                HStack {
                    Button { add() } label: { Image(systemName: "plus") }
                    Button { remove() } label: { Image(systemName: "minus") }.disabled(selected == nil)
                    Spacer()
                }.buttonStyle(.borderless).padding(6)
            }
            .frame(width: 180)
            if let i = store.cliProfiles.firstIndex(where: { $0.id == selected }) {
                Form {
                    TextField("Name", text: $store.cliProfiles[i].name)
                    TextField("Id", text: $store.cliProfiles[i].id)
                    LabeledContent("Command") {
                        TextEditor(text: $store.cliProfiles[i].command).font(.system(.body, design: .monospaced)).frame(height: 60)
                    }
                    Text("zsh snippet. Placeholders: {mcpUrl} {mcpConfigPath} {sessionId} {sessionName} {cwd}. Env: AGENTDECK_SESSION_ID, AGENTDECK_SESSION_NAME, AGENTDECK_MCP_URL, AGENTDECK_MCP_CONFIG.")
                        .font(.caption).foregroundStyle(.secondary)
                    Stepper("Submit delay: \(store.cliProfiles[i].submitDelayMs) ms", value: $store.cliProfiles[i].submitDelayMs, in: 0...2000, step: 50)
                    Toggle("Speaks MCP (receives briefings & summaries)", isOn: $store.cliProfiles[i].supportsMCP)
                    LabeledContent("Notes") { TextEditor(text: $store.cliProfiles[i].notes).frame(height: 50) }
                }
                .formStyle(.grouped)
            } else {
                ContentUnavailableView("Select a profile", systemImage: "terminal")
            }
        }
        .onAppear { selected = store.cliProfiles.first?.id }
    }

    private func add() {
        let p = CLIProfile(id: "custom-\(store.cliProfiles.count + 1)", name: "Custom CLI", command: "my-agent --mcp {mcpUrl}")
        store.cliProfiles.append(p)
        selected = p.id
    }

    private func remove() {
        store.cliProfiles.removeAll { $0.id == selected }
        selected = store.cliProfiles.first?.id
    }
}
