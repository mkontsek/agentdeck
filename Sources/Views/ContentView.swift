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

    var body: some View {
        HSplitView {
            if store.settings.showSidebar {
                SidebarView()
                    .frame(minWidth: 200, idealWidth: 240, maxWidth: 360)
            }
            VSplitView {
                PaneGridView()
                    .frame(minHeight: 220)
                if store.settings.showBottomPanel {
                    BottomPanelView()
                        .frame(minHeight: 120, idealHeight: store.settings.bottomPanelHeight)
                }
            }
            .frame(minWidth: 520)
            if store.settings.showInspector {
                InspectorView()
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 440)
            }
        }
        .toolbar { toolbarItems }
        .sheet(isPresented: $store.showNewSession) { NewSessionSheet() }
        .sheet(isPresented: $store.showInjectSheet) { InjectSheet() }
        .alert(
            "AgentDeck",
            isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })
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
                .tint(.orange).help("An orchestrator wants to recruit a session; open the sidebar to approve or deny")
            }
        }
        ToolbarItemGroup(placement: .principal) {
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
                    .accessibilityLabel("Global terminal font size")
                Image(systemName: "textformat.size.larger")
                Text("\(Int(store.settings.globalFontSize))").monospacedDigit().frame(width: 20)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .frame(width: 270, height: 28)
            .help("Global terminal font size (per-pane overrides in the pane header)")
        }
        ToolbarItemGroup(placement: .primaryAction) {
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
            Toggle(isOn: $store.settings.showBottomPanel) { Image(systemName: "rectangle.bottomthird.inset.filled") }
                .help("Task board & log (⌥⌘B)")
            Toggle(isOn: $store.settings.showInspector) { Image(systemName: "sidebar.trailing") }
                .help("Inspector (⌥⌘I)")
        }
    }
}
