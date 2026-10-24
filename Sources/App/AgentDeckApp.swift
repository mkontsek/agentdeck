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
        .defaultSize(width: 1400, height: 900)
        .commands { AppCommands(store: store) }

        Settings {
            SettingsView().environmentObject(store)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppStore.shared.bootstrap()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if let id = AppStore.shared.focusedSessionID {
            AppStore.shared.acknowledgeFinished(id)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppStore.shared.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let store = AppStore.shared
        let waiting = store.sessions.filter { $0.kind == .cli && store.status(of: $0.id) == .waitingForUser }
        let finished = store.sessions.filter { store.finishedSessionIDs.contains($0.id) }
        guard !waiting.isEmpty || !finished.isEmpty else { return nil }

        let menu = NSMenu()
        if !waiting.isEmpty {
            let item = NSMenuItem(title: "Waiting for Input:", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            for s in waiting {
                let sItem = NSMenuItem(
                    title: "  \(s.name)", action: #selector(focusSessionFromDock(_:)), keyEquivalent: "")
                sItem.target = self
                sItem.representedObject = s.id
                menu.addItem(sItem)
            }
        }
        if !finished.isEmpty {
            if !waiting.isEmpty { menu.addItem(.separator()) }
            let item = NSMenuItem(title: "Finished:", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            for s in finished {
                let sItem = NSMenuItem(
                    title: "  \(s.name)", action: #selector(focusSessionFromDock(_:)), keyEquivalent: "")
                sItem.target = self
                sItem.representedObject = s.id
                menu.addItem(sItem)
            }
        }
        return menu
    }

    @objc private func focusSessionFromDock(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        NSApp.activate(ignoringOtherApps: true)
        AppStore.shared.selectTab(id)
        AppStore.shared.acknowledgeFinished(id)
    }
}

struct AppCommands: Commands {
    @ObservedObject var store: AppStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Session…") { store.showNewSession = true }.keyboardShortcut("n", modifiers: .command)
            Button("New CLI Tab") { store.addCLITab(to: store.focusedSessionID) }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(store.cliTabSource(for: store.focusedSessionID).flatMap { store.profile(for: $0) } == nil)
        }
        CommandMenu("Session") {
            Button("Next Tab") { store.selectAdjacentTab(1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled((store.pane(containing: store.focusedSessionID)?.tabs.count ?? 0) < 2)
            Button("Previous Tab") { store.selectAdjacentTab(-1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled((store.pane(containing: store.focusedSessionID)?.tabs.count ?? 0) < 2)
            Divider()
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
            Toggle(
                "Orchestrator",
                isOn: Binding(
                    get: { store.session(store.focusedSessionID)?.isOrchestrator ?? false },
                    set: { v in
                        if var s = store.session(store.focusedSessionID) {
                            s.isOrchestrator = v
                            store.updateSession(s)
                        }
                    }))
        }
        CommandGroup(after: .toolbar) {
            Button("Bigger Text") { store.adjustFont(for: store.focusedSessionID, by: 1) }.keyboardShortcut(
                "+", modifiers: .command)
            Button("Bigger Text (⌘=)") { store.adjustFont(for: store.focusedSessionID, by: 1) }.keyboardShortcut(
                "=", modifiers: .command)
            Button("Smaller Text") { store.adjustFont(for: store.focusedSessionID, by: -1) }.keyboardShortcut(
                "-", modifiers: .command)
            Button("Reset Text Size") { store.resetFont(for: store.focusedSessionID) }.keyboardShortcut(
                "0", modifiers: .command)
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
                store.tidyCanvas(viewportWidth: store.canvasViewport.width)
            }.keyboardShortcut("t", modifiers: [.command, .option])
            Button("Fill Canvas") { store.fillCanvas() }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(store.sessions.isEmpty || store.canvasViewport.width <= 0 || store.canvasViewport.height <= 0)
            Button(store.maximizedSessionID == nil ? "Maximize Pane" : "Restore Panes") {
                store.maximizedSessionID = store.maximizedSessionID == nil ? store.focusedSessionID : nil
            }.keyboardShortcut("m", modifiers: [.command, .shift])
            Divider()
            Picker("Appearance", selection: $store.settings.appearance) {
                ForEach(AppAppearance.allCases) { Label($0.label, systemImage: $0.systemImage).tag($0) }
            }
            Button("Toggle Light/Dark") { store.toggleTheme() }.keyboardShortcut("d", modifiers: [.command, .option])
            Divider()
            Toggle("Show Sessions Sidebar", isOn: $store.settings.showSidebar).keyboardShortcut(
                "s", modifiers: [.command, .option])
            Toggle("Show Inspector", isOn: $store.settings.showInspector).keyboardShortcut(
                "i", modifiers: [.command, .option])
            Toggle("Show Task Board", isOn: $store.settings.showBottomPanel).keyboardShortcut(
                "b", modifiers: [.command, .option])
            Picker("Layout", selection: $store.settings.layoutMode) {
                ForEach(LayoutMode.allCases) { Text($0.label).tag($0) }
            }
        }
    }
}
