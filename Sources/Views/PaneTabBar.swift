import SwiftUI

struct PaneTabBar: View {
    @EnvironmentObject var store: AppStore
    let pane: SessionPane

    /// New tabs clone the pane's CLI session even while its private browser tab is in front.
    private var cliAnchor: ManagedSession { pane.tabs.first { $0.kind == .cli } ?? pane.activeSession }

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 3) {
                        ForEach(pane.tabs) { tab in
                            tabButton(tab).id(tab.id)
                        }
                    }
                    .padding(4)
                }
                .onAppear { proxy.scrollTo(pane.activeSession.id, anchor: .center) }
                .onChange(of: pane.activeSession.id) { _, id in proxy.scrollTo(id, anchor: .center) }
            }
            Button {
                store.addCLITab(to: cliAnchor.id)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(store.profile(for: cliAnchor) == nil)
            .help("New \(store.profile(for: cliAnchor)?.name ?? "CLI") tab (⌘T)")
            .accessibilityLabel("New CLI tab")
            .accessibilityIdentifier("new-cli-tab-\(pane.id)")
            .padding(.trailing, 4)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func tabButton(_ tab: ManagedSession) -> some View {
        let selected = tab.id == pane.activeSession.id
        let status = store.status(of: tab.id)
        return HStack(spacing: 0) {
            Button {
                store.selectTab(tab.id)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: tab.agentOwnerID != nil ? "globe" : status.systemImage)
                        .foregroundStyle(status.color)
                        .accessibilityLabel(status.label)
                    Text(tab.name)
                        .fontWeight(selected ? .semibold : .regular)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if tab.isOrchestrator {
                        Image(systemName: "crown.fill").foregroundStyle(.yellow)
                    }
                }
                .padding(.leading, 8)
                .padding(.trailing, 6)
                .frame(minWidth: 70, maxWidth: 160, minHeight: 26)
                .contentShape(Rectangle())
            }
            .help("\(tab.name) · \(status.label) · \(tab.effectiveDirectory.abbreviatingHome)")
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            .accessibilityIdentifier("cli-tab-\(tab.id)")
            Button {
                store.removeSession(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 22, height: 26)
                    .contentShape(Rectangle())
            }
            .help("Close \(tab.name)")
            .accessibilityLabel("Close \(tab.name)")
        }
        .font(.caption)
        .buttonStyle(.plain)
        .background(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
