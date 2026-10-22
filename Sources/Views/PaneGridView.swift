import SwiftUI

struct PaneGridView: View {
    @EnvironmentObject var store: AppStore
    private let spacing: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            if let mid = store.maximizedSessionID, let s = store.session(mid) {
                PaneView(session: s, size: PaneSize(width: geo.size.width - 16, height: geo.size.height - 16), resizable: false)
                    .padding(8)
            } else if store.sessions.isEmpty {
                ContentUnavailableView("No sessions yet", systemImage: "rectangle.3.group",
                                       description: Text("Add a CLI agent or an isolated browser session with ⌘N."))
            } else {
                ScrollView(.vertical) {
                    FlowLayout(spacing: spacing) {
                        ForEach(store.sessions) { s in
                            PaneView(session: s, size: size(for: s, in: geo.size), resizable: store.settings.layoutMode == .freeform)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(8)
                }
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func size(for s: ManagedSession, in area: CGSize) -> PaneSize {
        switch store.settings.layoutMode {
        case .freeform:
            return store.paneSize(for: s)
        case .grid:
            let count = max(1, store.sessions.count)
            let fit = max(1, Int((area.width - 16 + spacing) / (320 + spacing)))
            let cols = max(1, min(store.settings.gridColumns, count, fit))
            let rows = Int(ceil(Double(count) / Double(cols)))
            let w = floor((area.width - 16 - spacing * CGFloat(cols - 1)) / CGFloat(cols))
            let h = max(220, floor((area.height - 16 - spacing * CGFloat(rows - 1)) / CGFloat(rows)))
            return PaneSize(width: max(300, w), height: h)
        }
    }
}

/// Left-to-right wrapping layout; every child reports a fixed size.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = frames(maxWidth: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: frames.map(\.maxX).max() ?? 0, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = frames(maxWidth: bounds.width, subviews: subviews)
        for (i, f) in frames.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: ProposedViewSize(f.size))
        }
    }

    private func frames(maxWidth: CGFloat, subviews: Subviews) -> [CGRect] {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        var out: [CGRect] = []
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > maxWidth { x = 0; y += rowH + spacing; rowH = 0 }
            out.append(CGRect(x: x, y: y, width: sz.width, height: sz.height))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return out
    }
}

struct PaneView: View {
    @EnvironmentObject var store: AppStore
    let session: ManagedSession
    let size: PaneSize
    let resizable: Bool
    @State private var dragStart: PaneSize?

    private var focused: Bool { store.focusedSessionID == session.id }

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(session: session)
            Divider()
            content
        }
        .frame(width: size.width, height: size.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(focused ? Color.accentColor : Color.gray.opacity(0.35), lineWidth: focused ? 2 : 1))
        .overlay(alignment: .bottomTrailing) { if resizable { grip } }
    }

    @ViewBuilder private var content: some View {
        switch session.kind {
        case .cli: TerminalPaneView(session: session)
        case .browser: BrowserPaneView(session: session)
        }
    }

    private var grip: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.caption2).padding(5)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 5))
            .padding(6)
            .help("Drag to resize · double-click to reset")
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { v in
                        if dragStart == nil { dragStart = size }
                        let b = dragStart ?? size
                        store.setPaneSize(for: session.id, PaneSize(width: max(320, b.width + v.translation.width),
                                                                    height: max(200, b.height + v.translation.height)))
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .onTapGesture(count: 2) { store.setPaneSize(for: session.id, nil) }
    }
}

struct PaneHeader: View {
    @EnvironmentObject var store: AppStore
    let session: ManagedSession

    private var focused: Bool { store.focusedSessionID == session.id }

    var body: some View {
        let st = store.status(of: session.id)
        HStack(spacing: 6) {
            Circle().fill(st.color).frame(width: 8, height: 8)
            Image(systemName: session.kind.systemImage).foregroundStyle(.secondary).font(.caption)
            Text(session.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            if session.isOrchestrator { Image(systemName: "crown.fill").font(.caption2).foregroundStyle(.yellow) }
            Text(st.label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 4)
            Text(session.kind == .cli ? session.effectiveDirectory.abbreviatingHome : (store.runtime[session.id]?.title ?? ""))
                .font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
            if session.kind == .cli { fontControls }
            Menu { menuItems } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(focused ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
        .contentShape(Rectangle())
        .onTapGesture { store.focusedSessionID = session.id }
    }

    private var fontControls: some View {
        HStack(spacing: 2) {
            Button { store.adjustFont(for: session.id, by: -1) } label: { Image(systemName: "minus") }
            Text("\(Int(session.fontSizeOverride ?? store.settings.globalFontSize))")
                .font(.caption).monospacedDigit().frame(width: 18)
                .foregroundStyle(session.fontSizeOverride == nil ? .secondary : .primary)
            Button { store.adjustFont(for: session.id, by: 1) } label: { Image(systemName: "plus") }
            if session.fontSizeOverride != nil {
                Button { store.resetFont(for: session.id) } label: { Image(systemName: "arrow.counterclockwise") }
                    .help("Use global font size")
            }
        }
        .buttonStyle(.borderless).font(.caption)
        .help("Per-pane font size (⌘+ / ⌘− / ⌘0 on the focused pane)")
    }

    @ViewBuilder private var menuItems: some View {
        Section("Pane size") {
            ForEach(PaneSizePreset.allCases) { p in Button(p.label) { store.setPaneSize(for: session.id, p.size) } }
            Button("Reset to default") { store.setPaneSize(for: session.id, nil) }
        }
        Button(store.maximizedSessionID == session.id ? "Restore panes" : "Maximize") {
            store.maximizedSessionID = store.maximizedSessionID == session.id ? nil : session.id
        }
        Divider()
        if session.kind == .cli {
            Button("Inject note…") { store.focusedSessionID = session.id; store.showInjectSheet = true }
            Button("Inject context now") { store.injectContextNow(session.id) }
        }
        Button("Restart") { store.restartSession(session.id) }
        Button("Stop") { store.stopSession(session.id) }
        Divider()
        Button("Remove session", role: .destructive) { store.removeSession(session.id) }
    }
}
