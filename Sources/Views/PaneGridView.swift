import SwiftUI

struct PaneGridView: View {
    @EnvironmentObject var store: AppStore
    private let spacing: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            if let mid = store.maximizedSessionID, let s = store.session(mid) {
                PaneView(session: s, size: PaneSize(width: geo.size.width - 16, height: geo.size.height - 16), mode: .fixed)
                    .padding(8)
            } else if store.sessions.isEmpty {
                ContentUnavailableView("No sessions yet", systemImage: "rectangle.3.group",
                                       description: Text("Add a CLI agent or an isolated browser session with ⌘N."))
            } else if store.settings.layoutMode == .canvas {
                CanvasView(viewport: geo.size)
            } else {
                ScrollView(.vertical) {
                    FlowLayout(spacing: spacing) {
                        ForEach(store.sessions) { s in
                            PaneView(session: s, size: gridSize(in: geo.size), mode: .fixed)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(8)
                }
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func gridSize(in area: CGSize) -> PaneSize {
        let count = max(1, store.sessions.count)
        let fit = max(1, Int((area.width - 16 + spacing) / (320 + spacing)))
        let cols = max(1, min(store.settings.gridColumns, count, fit))
        let rows = Int(ceil(Double(count) / Double(cols)))
        let w = floor((area.width - 16 - spacing * CGFloat(cols - 1)) / CGFloat(cols))
        let h = max(220, floor((area.height - 16 - spacing * CGFloat(rows - 1)) / CGFloat(rows)))
        return PaneSize(width: max(300, w), height: h)
    }
}

/// Free canvas: every pane is a mini-window with its own position, size and z-order.
struct CanvasView: View {
    @EnvironmentObject var store: AppStore
    let viewport: CGSize

    var body: some View {
        let margin = AppStore.canvasSpacing
        let extentW = store.sessions.map { ($0.canvasPosition?.x ?? 0) + store.paneSize(for: $0).width }.max() ?? 0
        let extentH = store.sessions.map { ($0.canvasPosition?.y ?? 0) + store.paneSize(for: $0).height }.max() ?? 0
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                DotGrid().frame(width: max(viewport.width, extentW + margin), height: max(viewport.height, extentH + margin))
                    .contentShape(Rectangle())
                    .onTapGesture { store.focusedSessionID = nil }
                ForEach(store.sessions) { s in
                    PaneView(session: s, size: store.paneSize(for: s), mode: .canvas(s.canvasPosition ?? PanePoint(x: margin, y: margin)))
                        .zIndex(Double(s.zIndex))
                }
            }
        }
        .onAppear { store.ensureCanvasPositions(viewportWidth: viewport.width) }
        .onChange(of: viewport.width) { _, w in store.ensureCanvasPositions(viewportWidth: w) }
        .onChange(of: store.sessions.count) { _, _ in store.ensureCanvasPositions(viewportWidth: viewport.width) }
    }
}

private struct DotGrid: View {
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 24
            var x: CGFloat = step
            while x < size.width {
                var y: CGFloat = step
                while y < size.height {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(.secondary.opacity(0.18)))
                    y += step
                }
                x += step
            }
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

enum PaneMode: Equatable {
    case fixed                 // grid / maximized: not movable, not resizable
    case canvas(PanePoint)     // mini-window at a position: movable and resizable
}

struct PaneView: View {
    @EnvironmentObject var store: AppStore
    let session: ManagedSession
    let size: PaneSize
    let mode: PaneMode
    @State private var dragStartSize: PaneSize?
    @State private var moveOffset: CGSize = .zero

    private var focused: Bool { store.focusedSessionID == session.id }
    private var isCanvas: Bool { if case .canvas = mode { return true } else { return false } }

    var body: some View {
        let pane = VStack(spacing: 0) {
            PaneHeader(session: session, movable: isCanvas,
                       onMove: { t in moveOffset = t },
                       onMoveEnd: { t in commitMove(t) })
            Divider()
            if focused { PaneStatsBar(session: session); Divider() }
            content
        }
        .frame(width: size.width, height: size.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(focused ? Color.accentColor : Color.gray.opacity(0.35), lineWidth: focused ? 2 : 1))
        .overlay(alignment: .bottomTrailing) { if isCanvas { grip } }
        .shadow(color: .black.opacity(isCanvas ? (focused ? 0.35 : 0.2) : 0), radius: isCanvas ? 10 : 0, y: isCanvas ? 4 : 0)

        if case .canvas(let p) = mode {
            pane.offset(x: p.x + moveOffset.width, y: p.y + moveOffset.height)
        } else {
            pane
        }
    }

    private func commitMove(_ t: CGSize) {
        guard case .canvas(let p) = mode else { return }
        let snap = 8.0
        let x = (max(0, p.x + t.width) / snap).rounded() * snap
        let y = (max(0, p.y + t.height) / snap).rounded() * snap
        moveOffset = .zero
        store.setCanvasPosition(for: session.id, PanePoint(x: x, y: y))
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
                        if dragStartSize == nil { dragStartSize = size; store.focusedSessionID = session.id }
                        let b = dragStartSize ?? size
                        store.setPaneSize(for: session.id, PaneSize(width: max(320, b.width + v.translation.width),
                                                                    height: max(200, b.height + v.translation.height)))
                    }
                    .onEnded { _ in dragStartSize = nil }
            )
            .onTapGesture(count: 2) { store.setPaneSize(for: session.id, nil) }
    }
}

struct PaneHeader: View {
    @EnvironmentObject var store: AppStore
    let session: ManagedSession
    var movable: Bool = false
    var onMove: (CGSize) -> Void = { _ in }
    var onMoveEnd: (CGSize) -> Void = { _ in }

    private var focused: Bool { store.focusedSessionID == session.id }

    var body: some View {
        let st = store.status(of: session.id)
        HStack(spacing: 6) {
            if movable { Image(systemName: "line.3.horizontal").font(.caption2).foregroundStyle(.tertiary) }
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
        .gesture(movable ? moveGesture : nil)
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { v in
                if store.focusedSessionID != session.id { store.focusedSessionID = session.id }
                onMove(v.translation)
            }
            .onEnded { v in onMoveEnd(v.translation) }
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
        if movable { Button("Bring to front") { store.raisePane(session.id) } }
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

/// Live stats for the focused pane: status age, uptime, model/context (scraped from the CLI status line), tasks, branch.
struct PaneStatsBar: View {
    @EnvironmentObject var store: AppStore
    let session: ManagedSession
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in bar(now: ctx.date) }
    }

    private func bar(now: Date) -> some View {
        let rt = store.runtime[session.id] ?? SessionRuntime()
        let open = store.tasks.filter { $0.ownerSessionID == session.id && $0.status != .done }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                chip(rt.status.systemImage, "\(rt.status.label) \(age(rt.statusSince, now))", color: rt.status.color)
                if let s = rt.startedAt, rt.isRunning { chip("clock", "up \(age(s, now))") }
                if session.kind == .cli {
                    if let m = rt.modelName { chip("cpu", m) }
                    if let c = rt.contextInfo { chip("gauge.with.dots.needle.33percent", c) }
                    if let p = store.profile(for: session) { chip("terminal", p.name) }
                    if let b = session.worktreeBranch { chip("arrow.triangle.branch", b) }
                    chip("checklist", open.isEmpty ? "no tasks" : "\(open.count) open: " + open.prefix(3).map { "#\($0.id)" }.joined(separator: " "))
                    if let q = rt.pendingQuestion { chip("questionmark.circle", q, color: .orange) }
                    if let m = rt.programMessage, !m.isEmpty { chip("info.circle", m) }
                    if let code = rt.exitCode { chip("xmark.circle", "exit \(code)", color: .red) }
                } else {
                    if let t = rt.title, !t.isEmpty { chip("doc.text", t) }
                    if let host = URL(string: store.browsers.controllers[session.id]?.urlText ?? "")?.host { chip("globe", host) }
                    chip("checklist", open.isEmpty ? "no tasks" : "\(open.count) open")
                }
                chip("textformat.size", "\(Int(session.fontSizeOverride ?? store.settings.globalFontSize)) pt\(session.fontSizeOverride == nil ? "" : " (override)")")
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
        }
        .background(Color.accentColor.opacity(0.06))
    }

    private func chip(_ icon: String, _ text: String, color: Color = .secondary) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).lineLimit(1)
        }
        .font(.caption2).foregroundStyle(.secondary)
    }

    private func age(_ d: Date, _ now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(d)))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \((s % 3600) / 60)m"
    }
}
