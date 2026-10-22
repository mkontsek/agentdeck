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
            SidebarView()
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 360)
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
        .alert("AgentDeck", isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
            Button("OK") {}
        } message: { Text(store.lastError ?? "") }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { store.showNewSession = true } label: { Label("New Session", systemImage: "plus") }
                .help("New session (⌘N)")
        }
        ToolbarItemGroup(placement: .principal) {
            Picker("Layout", selection: $store.settings.layoutMode) {
                Image(systemName: "square.grid.2x2").tag(LayoutMode.grid)
                Image(systemName: "rectangle.3.group").tag(LayoutMode.freeform)
            }
            .pickerStyle(.segmented).help("Grid tiles panes evenly; Freeform uses per-pane sizes")
            if store.settings.layoutMode == .grid {
                Stepper("\(store.settings.gridColumns) col", value: $store.settings.gridColumns, in: 1...4)
                    .help("Grid columns")
            }
            Picker("Pane size", selection: $store.settings.defaultPanePreset) {
                ForEach(PaneSizePreset.allCases) { Text($0.label).tag($0) }
            }.help("Default pane size preset")
            HStack(spacing: 4) {
                Image(systemName: "textformat.size.smaller")
                Slider(value: $store.settings.globalFontSize, in: 9...24, step: 1).frame(width: 110)
                Image(systemName: "textformat.size.larger")
                Text("\(Int(store.settings.globalFontSize))").monospacedDigit().frame(width: 20)
            }.help("Global terminal font size (per-pane overrides in the pane header)")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Toggle(isOn: $store.settings.showBottomPanel) { Image(systemName: "rectangle.bottomthird.inset.filled") }
                .help("Task board & log (⌥⌘B)")
            Toggle(isOn: $store.settings.showInspector) { Image(systemName: "sidebar.trailing") }
                .help("Inspector (⌥⌘I)")
        }
    }
}
