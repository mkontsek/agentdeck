import SwiftUI

struct PaneTabBar: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let pane: SessionPane
    var maximumVisibleRows = 3

    /// New tabs clone the pane's CLI session even while its private browser tab is in front.
    private var cliAnchor: ManagedSession { store.cliTabSource(for: pane.activeSession.id) ?? pane.activeSession }
    private var mainTabs: [ManagedSession] { pane.tabs }
    private var isBrowser: Bool { pane.activeSession.kind == .browser }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(spacing: 3) {
                        ForEach(mainTabs) { tab in
                            tabButton(tab).id(tab.id).transition(.opacity)
                        }
                    }
                    .padding(4)
                }
                .frame(height: CGFloat(min(mainTabs.count, maximumVisibleRows)) * 29 + 5)
                .onAppear { proxy.scrollTo(pane.activeSession.id, anchor: .center) }
                .onChange(of: pane.activeSession.id) { _, id in
                    withAnimation(WorkspaceMotion.animation(reduceMotion: reduceMotion)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
            Button {
                if isBrowser {
                    store.addBrowserTab(to: pane.activeSession.id)
                } else {
                    store.addCLITab(to: cliAnchor.id)
                }
            } label: {
                Image(systemName: "plus")
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!isBrowser && store.cliTabSource(for: cliAnchor.id).flatMap({ store.profile(for: $0) }) == nil)
            .help(isBrowser ? "New browser tab" : "New \(store.profile(for: cliAnchor)?.name ?? "CLI") tab (⌘T)")
            .accessibilityLabel(isBrowser ? "New browser tab" : "New CLI tab")
            .accessibilityIdentifier("new-\(isBrowser ? "browser" : "cli")-tab-\(pane.id)")
            .padding(.trailing, 4)
            .padding(.top, 4)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion), value: pane.tabs.map(\.id))
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
                .frame(minWidth: 70, maxWidth: .infinity, minHeight: 26, alignment: .leading)
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
