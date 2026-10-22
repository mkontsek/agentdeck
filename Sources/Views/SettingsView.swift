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
        .frame(width: 640, height: 460)
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
            Section("Browser sign-ins") {
                Text("Browser panes share AgentDeck’s saved sign-ins by default, including after restarting the app.")
                Text(
                    "Sign in once per service. Signing out affects other shared panes for that service. Choose Separate account in a pane’s inspector for an independent login."
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
                    "Canvas layout turns panes into movable mini-windows: drag the header to move, the corner grip to resize (double-click resets), ⌥⌘T tidies them."
                )
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
            Section("Context injection") {
                Text(
                    "Status summaries are never broadcast automatically. Send one to a session with Session › Inject Context Now, the pane menu, or the inspector."
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

private struct ProfilesSettings: View {
    @EnvironmentObject var store: AppStore
    @State private var selected: String?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(store.cliProfiles, selection: $selected) { p in Text(p.name).tag(p.id) }
                Divider()
                HStack {
                    Button {
                        add()
                    } label: {
                        Image(systemName: "plus")
                    }
                    Button {
                        remove()
                    } label: {
                        Image(systemName: "minus")
                    }.disabled(selected == nil)
                    Spacer()
                }.buttonStyle(.borderless).padding(6)
            }
            .frame(width: 180)
            if let i = store.cliProfiles.firstIndex(where: { $0.id == selected }) {
                Form {
                    TextField("Name", text: $store.cliProfiles[i].name)
                    TextField("Id", text: $store.cliProfiles[i].id)
                    LabeledContent("Command") {
                        TextEditor(text: $store.cliProfiles[i].command).font(.system(.body, design: .monospaced)).frame(
                            height: 60)
                    }
                    Text(
                        "zsh snippet. Placeholders: {mcpUrl} {mcpConfigPath} {sessionId} {sessionName} {cwd}. Env: AGENTDECK_SESSION_ID, AGENTDECK_SESSION_NAME, AGENTDECK_MCP_URL, AGENTDECK_MCP_CONFIG."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    Stepper(
                        "Submit delay: \(store.cliProfiles[i].submitDelayMs) ms",
                        value: $store.cliProfiles[i].submitDelayMs, in: 0...2000, step: 50)
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
        let p = CLIProfile(
            id: "custom-\(store.cliProfiles.count + 1)", name: "Custom CLI", command: "my-agent --mcp {mcpUrl}")
        store.cliProfiles.append(p)
        selected = p.id
    }

    private func remove() {
        store.cliProfiles.removeAll { $0.id == selected }
        selected = store.cliProfiles.first?.id
    }
}
