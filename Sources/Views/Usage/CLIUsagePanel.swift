import SwiftUI

struct CLIUsagePanel: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var monitor: CLIUsageMonitor
    @State private var dragOffset = CGSize.zero
    @State private var collapsed = false
    let viewport: CGSize

    private var profiles: [CLIProfile] {
        let ids = Set(store.sessions.filter { $0.kind == .cli }.compactMap(\.cliProfileID))
        return store.cliProfiles.filter { ids.contains($0.id) }.sorted { $0.name < $1.name }
    }

    var body: some View {
        let size = store.settings.usagePanelSize
        let position = store.settings.usagePanelPosition
        let width = min(max(320, size.width), max(320, viewport.width - 16))
        let height = min(max(220, size.height), max(220, viewport.height - 16))
        let visibleHeight = collapsed ? 44.0 : height
        let origin = CGPoint(
            x: min(max(8, position.x + dragOffset.width), max(8, viewport.width - width - 8)),
            y: min(max(8, position.y + dragOffset.height), max(8, viewport.height - visibleHeight - 8)))
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.xaxis").foregroundStyle(.tint)
                Text("CLI usage").font(.headline)
                Spacer()
                Button {
                    collapsed.toggle()
                } label: {
                    Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                }.help(collapsed ? "Expand CLI usage" : "Collapse CLI usage")
                if monitor.refreshing { ProgressView().controlSize(.small) }
                Button {
                    Task { await monitor.refresh(profiles.map(\.id)) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }.disabled(monitor.refreshing).help("Refresh account usage")
                Button {
                    store.settings.showUsagePanel = false
                } label: {
                    Image(systemName: "xmark")
                }.help("Close CLI usage")
            }
            .buttonStyle(.borderless).padding(12).background(.bar)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { dragOffset = $0.translation }
                    .onEnded { value in
                        store.settings.usagePanelPosition = PanePoint(
                            x: min(max(8, position.x + value.translation.width), max(8, viewport.width - width - 8)),
                            y: min(
                                max(8, position.y + value.translation.height),
                                max(8, viewport.height - visibleHeight - 8)))
                        dragOffset = .zero
                    })
            Divider()
            if !collapsed {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        let sessions = store.sessions.filter { $0.kind == .cli }
                        Text(
                            "\(sessions.count) sessions · \(sessions.filter { store.status(of: $0.id) == .working }.count) working · \(sessions.filter { store.status(of: $0.id) == .quotaWarning }.count) quota warnings"
                        )
                        .font(.caption).foregroundStyle(.secondary)
                        Text(
                            "Uses each CLI’s default local sign-in. Custom account profiles may differ. Context usage is separate."
                        )
                        .font(.caption).foregroundStyle(.secondary)
                        ForEach(profiles) { profile in
                            CLIUsageProviderView(profile: profile, snapshot: monitor.snapshots[profile.id])
                        }
                        if profiles.isEmpty {
                            Text("Open a CLI session to see its usage here.").foregroundStyle(.secondary)
                        }
                    }.padding(14)
                }
                .transition(.opacity)
            }
        }
        .frame(width: width, height: visibleHeight)
        .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion), value: collapsed)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.35)))
        .overlay {
            if !collapsed {
                MiniWindowResizeOverlay(
                    frame: CGRect(origin: origin, size: CGSize(width: width, height: height)),
                    minimum: CGSize(width: 320, height: 220),
                    bounds: CGRect(
                        x: 8, y: 8, width: max(320, viewport.width - 16), height: max(220, viewport.height - 16)),
                    onResize: { frame in
                        store.settings.usagePanelPosition = PanePoint(x: frame.minX, y: frame.minY)
                        store.settings.usagePanelSize = PaneSize(width: frame.width, height: frame.height)
                    },
                    onReset: { store.settings.usagePanelSize = AppSettings().usagePanelSize })
            }
        }
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .offset(x: origin.x, y: origin.y)
        .task(id: profiles.map(\.id)) { await monitor.poll(profiles.map(\.id)) }
        .accessibilityIdentifier("cli-usage-panel")
    }
}
