import SwiftUI

struct PaneRelationshipBar: View {
    @EnvironmentObject var store: AppStore
    let session: ManagedSession

    var body: some View {
        let parent = store.session(session.parentSessionID)
        let owner = store.session(session.agentOwnerID)
        let workers = store.sessions.filter { $0.parentSessionID == session.id }
        let browser = store.agentBrowser(for: session.id)
        if parent != nil || owner != nil || !workers.isEmpty || browser != nil {
            HStack(spacing: 8) {
                if let parent {
                    relation("Subagent of \(parent.name)", symbol: "arrow.turn.up.left", target: parent.id)
                } else if let owner {
                    relation("Browser for \(owner.name)", symbol: "link", target: owner.id)
                }
                if !workers.isEmpty {
                    Menu(
                        "\(workers.count) \(workers.count == 1 ? "worker" : "workers")",
                        systemImage: "arrow.triangle.branch"
                    ) {
                        ForEach(workers) { worker in
                            Button(worker.name) { store.selectTab(worker.id) }
                        }
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    .accessibilityLabel("Show workers of \(session.name)")
                }
                if let browser { relation("Browser", symbol: "globe", target: browser.id) }
                Spacer(minLength: 0)
            }
            .font(.caption2).buttonStyle(.plain)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.06))
        }
    }

    private func relation(_ label: String, symbol: String, target: UUID) -> some View {
        Button {
            store.selectTab(target)
        } label: {
            Label(label, systemImage: symbol).lineLimit(1).truncationMode(.middle)
        }
        .help("Focus \(store.name(of: target))")
        .accessibilityLabel(label)
        .accessibilityIdentifier("pane-relationship-\(session.id)-\(target)")
    }
}
