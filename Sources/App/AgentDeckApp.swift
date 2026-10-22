import AppKit
import SwiftUI

@main
struct AgentDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = AppStore.shared

    var body: some Scene {
        WindowGroup("AgentDeck") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .defaultSize(width: 1800, height: 1100)
        .commands { AppCommands(store: store) }

        Settings {
            SettingsView().environmentObject(store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppStore.shared.bootstrap()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppStore.shared.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct AppCommands: Commands {
    @ObservedObject var store: AppStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Session…") { store.showNewSession = true }.keyboardShortcut("n", modifiers: .command)
        }
        CommandMenu("Session") {
            Button("Inject Note…") { store.showInjectSheet = true }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(store.session(store.focusedSessionID)?.kind != .cli)
            Button("Inject Context Now") { if let id = store.focusedSessionID { store.injectContextNow(id) } }
                .disabled(store.session(store.focusedSessionID)?.kind != .cli)
            Divider()
            Button("Restart Session") { if let id = store.focusedSessionID { store.restartSession(id) } }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Stop Session") { if let id = store.focusedSessionID { store.stopSession(id) } }
            Button("Remove Session") { if let id = store.focusedSessionID { store.removeSession(id) } }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
            Divider()
            Toggle("Orchestrator", isOn: Binding(
                get: { store.session(store.focusedSessionID)?.isOrchestrator ?? false },
                set: { v in if var s = store.session(store.focusedSessionID) { s.isOrchestrator = v; store.updateSession(s) } }))
        }
        CommandGroup(after: .toolbar) {
            Button("Bigger Text") { store.adjustFont(for: store.focusedSessionID, by: 1) }.keyboardShortcut("+", modifiers: .command)
            Button("Bigger Text (⌘=)") { store.adjustFont(for: store.focusedSessionID, by: 1) }.keyboardShortcut("=", modifiers: .command)
            Button("Smaller Text") { store.adjustFont(for: store.focusedSessionID, by: -1) }.keyboardShortcut("-", modifiers: .command)
            Button("Reset Text Size") { store.resetFont(for: store.focusedSessionID) }.keyboardShortcut("0", modifiers: .command)
            Divider()
            Menu("Pane Size") {
                ForEach(PaneSizePreset.allCases) { p in
                    Button(p.label) { if let id = store.focusedSessionID { store.setPaneSize(for: id, p.size) } }
                }
                Button("Reset to Default") { if let id = store.focusedSessionID { store.setPaneSize(for: id, nil) } }
                    .keyboardShortcut("0", modifiers: [.command, .option])
            }
            Button("Tidy Canvas") {
                store.settings.layoutMode = .canvas
                let w = NSApp.keyWindow?.frame.width ?? 1600
                store.tidyCanvas(viewportWidth: w - (store.settings.showSidebar ? 240 : 0) - (store.settings.showInspector ? 300 : 0) - 16)
            }.keyboardShortcut("t", modifiers: [.command, .option])
            Button(store.maximizedSessionID == nil ? "Maximize Pane" : "Restore Panes") {
                store.maximizedSessionID = store.maximizedSessionID == nil ? store.focusedSessionID : nil
            }.keyboardShortcut("m", modifiers: [.command, .shift])
            Divider()
            Picker("Appearance", selection: $store.settings.appearance) {
                ForEach(AppAppearance.allCases) { Label($0.label, systemImage: $0.systemImage).tag($0) }
            }
            Button("Toggle Light/Dark") { store.toggleTheme() }.keyboardShortcut("d", modifiers: [.command, .option])
            Divider()
            Toggle("Show Sessions Sidebar", isOn: $store.settings.showSidebar).keyboardShortcut("s", modifiers: [.command, .option])
            Toggle("Show Inspector", isOn: $store.settings.showInspector).keyboardShortcut("i", modifiers: [.command, .option])
            Toggle("Show Task Board", isOn: $store.settings.showBottomPanel).keyboardShortcut("b", modifiers: [.command, .option])
            Picker("Layout", selection: $store.settings.layoutMode) {
                ForEach(LayoutMode.allCases) { Text($0.label).tag($0) }
            }
        }
    }
}
