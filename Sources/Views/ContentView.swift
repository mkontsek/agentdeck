import AppKit
import SwiftUI

extension SessionStatus {
    var color: Color {
        switch self {
        case .starting: return .gray
        case .working: return .blue
        case .idle: return .green
        case .waitingForUser: return .orange
        case .stalled: return .yellow
        case .error: return .red
        case .quotaWarning: return .purple
        case .exited: return .secondary
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HSplitView {
            if !store.isDemoMode && store.settings.showSidebar {
                SidebarView()
                    .frame(minWidth: 200, idealWidth: 240, maxWidth: 360)
                    .transition(WorkspaceMotion.panel(edge: .leading, reduceMotion: reduceMotion))
            }
            VSplitView {
                ZStack {
                    PaneGridView()
                        .opacity(store.isDemoMode || store.settings.workspaceMode == .sessions ? 1 : 0)
                        .allowsHitTesting(store.isDemoMode || store.settings.workspaceMode == .sessions)
                        .accessibilityHidden(!store.isDemoMode && store.settings.workspaceMode != .sessions)
                    if !store.isDemoMode && store.settings.workspaceMode == .board {
                        CoordinationBoardView().transition(.opacity)
                    }
                }
                .frame(minHeight: 220)
                if !store.isDemoMode && store.settings.showBottomPanel && store.settings.workspaceMode == .sessions {
                    BottomPanelView()
                        .frame(minHeight: 120, idealHeight: store.settings.bottomPanelHeight)
                        .transition(WorkspaceMotion.panel(edge: .bottom, reduceMotion: reduceMotion))
                }
            }
            .frame(minWidth: 520)
            if !store.isDemoMode && store.settings.showInspector {
                InspectorView()
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 440)
                    .transition(WorkspaceMotion.panel(edge: .trailing, reduceMotion: reduceMotion))
            }
        }
        .toolbar { toolbarItems }
        .overlay(alignment: .topLeading) {
            if !store.isDemoMode && store.settings.showUsagePanel {
                GeometryReader { geometry in
                    CLIUsagePanel(monitor: store.usageMonitor, viewport: geometry.size)
                }
                .transition(WorkspaceMotion.panel(edge: .trailing, reduceMotion: reduceMotion))
            }
        }
        .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion), value: store.settings.workspaceMode)
        .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion), value: store.settings.showSidebar)
        .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion), value: store.settings.showInspector)
        .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion), value: store.settings.showBottomPanel)
        .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion), value: store.settings.showUsagePanel)
        .onChange(of: store.settings.workspaceMode) { _, mode in
            if mode == .board { NSApp.keyWindow?.makeFirstResponder(nil) }
        }
        .sheet(
            isPresented: Binding(get: { !store.isDemoMode && store.showNewSession }, set: { store.showNewSession = $0 })
        ) { NewSessionSheet() }
        .sheet(
            isPresented: Binding(
                get: { !store.isDemoMode && store.showInjectSheet }, set: { store.showInjectSheet = $0 })
        ) { InjectSheet() }
        .alert(
            "AgentDeck",
            isPresented: Binding(
                get: { !store.isDemoMode && store.lastError != nil }, set: { if !$0 { store.lastError = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(store.lastError ?? "")
        }
    }

    private func tidy() {
        store.tidyCanvas(viewportWidth: store.canvasViewport.width)
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 7) {
                AgentDeckIcon()
                    .frame(width: 26, height: 26)
                    .accessibilityHidden(true)
                Text("AgentDeck")
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("agentdeck-brand")
        }
        ToolbarItemGroup(placement: .navigation) {
            if !store.isDemoMode {
                Picker("Workspace", selection: $store.settings.workspaceMode) {
                    Label("Work", systemImage: "checklist").tag(WorkspaceMode.board)
                    Label("Sessions", systemImage: "macwindow.on.rectangle").tag(WorkspaceMode.sessions)
                }.pickerStyle(.segmented).frame(width: 180)
                Toggle(isOn: $store.settings.showSidebar) { Image(systemName: "sidebar.leading") }
                    .help("Sessions sidebar (⌥⌘S)")
                Button {
                    store.showNewSession = true
                } label: {
                    Label("New Session", systemImage: "plus")
                }
                .help("New session (⌘N)")
                let pending = store.recruits.filter { $0.status == .pending }.count
                if pending > 0 {
                    Button {
                        store.settings.showSidebar = true
                    } label: {
                        Label("\(pending) approval\(pending == 1 ? "" : "s")", systemImage: "person.badge.clock")
                    }
                    .tint(.orange).help(
                        "An orchestrator wants to recruit a session; open the sidebar to approve or deny")
                }
            }
        }
        ToolbarItemGroup(placement: .principal) {
            if store.isDemoMode {
                Text("Demo workspace · Synthetic content").foregroundStyle(.secondary)
            } else if store.settings.workspaceMode == .sessions {
                Picker("Layout", selection: $store.settings.layoutMode) {
                    Image(systemName: "square.grid.2x2").tag(LayoutMode.grid)
                    Image(systemName: "macwindow.on.rectangle").tag(LayoutMode.canvas)
                }
                .pickerStyle(.segmented).help(
                    "Grid tiles panes evenly; Canvas gives every pane its own movable mini-window")
                if store.settings.layoutMode == .grid {
                    Stepper("\(store.settings.gridColumns) col", value: $store.settings.gridColumns, in: 1...4)
                        .help("Grid columns")
                } else {
                    Button {
                        tidy()
                    } label: {
                        Label("Tidy", systemImage: "rectangle.grid.2x2")
                    }
                    .help("Re-pack the mini-windows left to right (⌥⌘T)")
                }
                Picker("Pane size", selection: $store.settings.defaultPanePreset) {
                    ForEach(PaneSizePreset.allCases) { Text($0.label).tag($0) }
                }.help("Default pane size preset")
                Button {
                    store.fillCanvas()
                } label: {
                    Label("Fill Canvas", systemImage: "rectangle.split.2x2")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(store.sessions.isEmpty || store.canvasViewport.width <= 0 || store.canvasViewport.height <= 0)
                .help("Resize and arrange panes to fill the visible canvas (⌥⌘F)")
                .accessibilityIdentifier("fill-canvas")
                HStack(spacing: 8) {
                    Image(systemName: "textformat.size.smaller")
                    Slider(value: $store.settings.globalFontSize, in: 9...24, step: 1)
                        .frame(width: 172)
                        .controlSize(.small)
                        .accessibilityLabel("Base text size")
                    Image(systemName: "textformat.size.larger")
                    Text("\(Int(store.settings.globalFontSize))").monospacedDigit().frame(width: 20)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
                .frame(width: 270, height: 28)
                .help("Base text size (per-pane overrides in the pane header)")
            } else {
                Button {
                    store.showAttention()
                } label: {
                    Label("\(store.attentionCount) need attention", systemImage: "person.badge.clock")
                }
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Toggle("Demo mode", isOn: Binding(get: { store.isDemoMode }, set: { store.setDemoMode($0) }))
                .help("Replace live content and identifiers with synthetic content for screenshots")
                .accessibilityIdentifier("demo-mode")
            if !store.isDemoMode {
                Button {
                    store.settings.showUsagePanel.toggle()
                } label: {
                    Label("CLI usage", systemImage: "chart.bar.xaxis")
                }.help("Show CLI usage, limits and resets (⌥⌘U)")
                Button {
                    store.toggleTheme()
                } label: {
                    Image(systemName: store.isDarkTheme ? "sun.max" : "moon")
                }
                .help("Toggle light/dark theme (⌥⌘D) · System/Light/Dark in Settings")
                let up = store.mcpStatus.hasPrefix("listening")
                Image(systemName: up ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .foregroundStyle(up ? Color.green : Color.red)
                    .help("MCP server " + store.mcpStatus)
                Toggle(isOn: $store.settings.showBottomPanel) {
                    Image(systemName: "rectangle.bottomthird.inset.filled")
                }
                .help("Task board & log (⌥⌘B)")
                Toggle(isOn: $store.settings.showInspector) { Image(systemName: "sidebar.trailing") }
                    .help("Inspector (⌥⌘I)")
            }
        }
    }
}
