import SwiftUI

struct AgentStatusMenu: View {
    @ObservedObject var store: AppStore

    var body: some View {
        Button("Shared work · \(store.attentionCount) need attention") { store.showAttention() }
        Button("CLI usage, limits and resets") {
            store.settings.showUsagePanel = true
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        ForEach(store.sessions.filter { $0.kind == .cli }) { session in
            Button {
                store.selectTab(session.id)
                store.settings.workspaceMode = .sessions
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label(
                    "\(session.name) · \(store.status(of: session.id).label)",
                    systemImage: store.status(of: session.id).systemImage)
            }
        }
        Divider()
        Text("Show attention: ⌃⌥⌘Space")
    }
}
