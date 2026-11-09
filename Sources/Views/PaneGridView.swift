import SwiftUI

/// Stable pane identities across canvas, grid, and maximized layouts keep native PTYs attached during animation.
struct PaneGridView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var movingPanes: [UUID: CGSize] = [:]
    @State private var hoveredPanes: Set<UUID> = []

    var body: some View {
        GeometryReader { geometry in
            let frames = store.paneFrames(in: geometry.size)
            let maximizedPaneID = store.session(store.maximizedSessionID)?.paneID
            let extent =
                store.maximizedSessionID == nil
                ? CGSize(
                    width: max(geometry.size.width, (frames.values.map(\.maxX).max() ?? 0) + 8),
                    height: max(geometry.size.height, (frames.values.map(\.maxY).max() ?? 0) + 8)) : geometry.size
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        Color.clear.frame(width: 1, height: 1).id("pane-origin")
                        CanvasScrollObserver(
                            store: store,
                            frames: connectionFrames(frames).filter {
                                maximizedPaneID == nil || $0.key == maximizedPaneID
                            },
                            focusedPaneID: store.pane(containing: store.focusedSessionID)?.id
                        ).frame(width: 1, height: 1).accessibilityHidden(true)
                        CanvasBackground()
                            .frame(width: extent.width, height: extent.height)
                            .contentShape(Rectangle()).onTapGesture { store.focusedSessionID = nil }
                        CanvasNavigationView(
                            revision: store.paneRevealRevision,
                            target: store.maximizedSessionID == nil
                                ? store.pane(containing: store.focusedSessionID).flatMap { frames[$0.id] } : nil
                        )
                        .frame(width: extent.width, height: extent.height)
                        .accessibilityHidden(true)
                        if store.sessions.isEmpty {
                            EmptyCanvasView().frame(width: geometry.size.width, height: geometry.size.height)
                                .transition(.opacity)
                        }
                        if store.maximizedSessionID == nil {
                            PaneConnectionsView(
                                connections: store.paneConnections,
                                frames: connectionFrames(frames),
                                color: CanvasArrowColor.color(hex: store.settings.arrowColorHex)
                            )
                            .frame(width: extent.width, height: extent.height)
                            .zIndex(1_000_001)
                        }
                        ForEach(store.panes) { pane in
                            let frame = frames[pane.id] ?? CGRect(x: 8, y: 8, width: 440, height: 300)
                            let visible =
                                store.maximizedSessionID == nil
                                || pane.tabs.contains { $0.id == store.maximizedSessionID }
                            PaneView(
                                pane: pane, size: PaneSize(width: frame.width, height: frame.height),
                                mode: paneMode(frame: frame),
                                collapsed: store.collapsesToGlassBall(pane, hovered: hoveredPanes.contains(pane.id)),
                                onHover: { entered in
                                    if entered { hoveredPanes.insert(pane.id) } else { hoveredPanes.remove(pane.id) }
                                },
                                onResizeBegin: { store.detachGridForResize(frames: frames) },
                                onMove: { offset in movingPanes[pane.id] = offset }
                            )
                            .offset(
                                x: store.maximizedSessionID == nil ? 0 : frame.minX,
                                y: store.maximizedSessionID == nil ? 0 : frame.minY
                            )
                            .opacity(visible ? 1 : 0).allowsHitTesting(visible).accessibilityHidden(!visible)
                            .zIndex(
                                visible && store.maximizedSessionID != nil
                                    ? 1_000_000
                                    : (hoveredPanes.contains(pane.id) ? 999_999 : Double(pane.activeSession.zIndex))
                            )
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
                        }
                    }.frame(width: extent.width, height: extent.height, alignment: .topLeading)
                }
                .scrollDisabled(store.maximizedSessionID != nil)
                .onChange(of: store.maximizedSessionID) { _, id in
                    hoveredPanes.removeAll()
                    if id != nil { proxy.scrollTo("pane-origin", anchor: .topLeading) }
                }
                .onChange(of: store.settings.layoutMode) { _, mode in
                    // Resizing a scrolled grid must keep the grabbed border under the mouse.
                    if mode == .grid { proxy.scrollTo("pane-origin", anchor: .topLeading) }
                }
            }
            .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion), value: store.panes.map(\.id))
            .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion), value: store.settings.layoutMode)
            .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion), value: store.maximizedSessionID)
            .onAppear {
                updateViewport(geometry.size)
                store.paneRevealRevision += 1
            }
            .onChange(of: geometry.size) { _, size in updateViewport(size) }
            .onChange(of: store.panes.count) { _, _ in updateViewport(geometry.size) }
            .onChange(of: store.settings.glassBallSubagents) { _, _ in hoveredPanes.removeAll() }
            .onChange(of: store.settings.workspaceMode) { _, _ in hoveredPanes.removeAll() }
            .onChange(of: store.panes.map(\.id)) { _, ids in hoveredPanes.formIntersection(ids) }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func updateViewport(_ size: CGSize) {
        store.updateCanvasViewport(size)
    }

    private func connectionFrames(_ frames: [UUID: CGRect]) -> [UUID: CGRect] {
        var result = frames
        for (id, offset) in movingPanes {
            guard let frame = frames[id] else { continue }
            result[id] = CGRect(
                x: max(0, frame.minX + offset.width), y: max(0, frame.minY + offset.height),
                width: frame.width, height: frame.height)
        }
        for pane in store.panes where store.collapsesToGlassBall(pane, hovered: hoveredPanes.contains(pane.id)) {
            if let frame = result[pane.id] {
                result[pane.id] = CGRect(origin: frame.origin, size: GlassBallStatus.compactSize)
            }
        }
        return result
    }

    private func paneMode(frame: CGRect) -> PaneMode {
        guard store.maximizedSessionID == nil else { return .fixed }
        let position = PanePoint(x: frame.minX, y: frame.minY)
        return store.settings.layoutMode == .canvas ? .canvas(position) : .tiled(position)
    }

}

enum PaneMode: Equatable {
    case fixed  // maximized: not movable, not resizable
    case tiled(PanePoint)  // resizing detaches the grid at its current positions
    case canvas(PanePoint)  // mini-window at a position: movable and resizable

    var position: PanePoint {
        switch self {
        case .fixed: return PanePoint(x: 0, y: 0)
        case .tiled(let point), .canvas(let point): return point
        }
    }
}

struct PaneView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let pane: SessionPane
    let size: PaneSize
    let mode: PaneMode
    var collapsed = false
    var onHover: (Bool) -> Void = { _ in }
    var onResizeBegin: () -> Void = {}
    var onMove: (CGSize?) -> Void = { _ in }
    @State private var moveOffset: CGSize = .zero

    private var session: ManagedSession { pane.activeSession }
    private var focused: Bool { pane.tabs.contains { $0.id == store.focusedSessionID } }
    private var compact: Bool { size.width < 400 || size.height < 260 }
    private var isCanvas: Bool { if case .canvas = mode { return true } else { return false } }

    var body: some View {
        let pane = VStack(spacing: 0) {
            PaneHeader(
                session: session, movable: isCanvas, compact: compact,
                onMove: { t in
                    moveOffset = t
                    onMove(t)
                },
                onMoveEnd: { t in commitMove(t) })
            Divider()
            if self.pane.showsTabBar && (!compact || self.pane.tabs.count > 1) {
                PaneTabBar(pane: self.pane, maximumVisibleRows: compact ? 1 : (size.height < 400 ? 2 : 3))
                    .transition(WorkspaceMotion.panel(edge: .top, reduceMotion: reduceMotion))
                Divider()
            }
            // Always laid out: showing it only when focused changed the terminal's row count on every focus change,
            // which made the CLI repaint its whole screen (visible as a flicker).
            if !compact {
                PaneStatsBar(session: session).opacity(focused ? 1 : 0.55)
                Divider()
            }
            PaneRelationshipBar(session: session)
            PaneSessionContent(pane: self.pane)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: size.width, height: size.height)
        .environment(\.isGlassBallCollapsed, collapsed)
        .opacity(store.isDemoMode || collapsed ? 0 : 1)
        .allowsHitTesting(!store.isDemoMode && !collapsed)
        .accessibilityHidden(store.isDemoMode || collapsed)
        .overlay {
            if store.isDemoMode {
                DemoPaneView(
                    number: (store.panes.firstIndex { $0.id == self.pane.id } ?? 0) + 1,
                    split: store.visibleSessions(in: self.pane).count > 1,
                    movable: isCanvas,
                    onMove: { offset in
                        moveOffset = offset
                        onMove(offset)
                    },
                    onMoveEnd: commitMove, onMaximize: { store.toggleMaximize(session.id) })
            }
        }
        .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion), value: self.pane.showsTabBar)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.blue, lineWidth: focused ? 2.5 : 1.5)
                .shadow(color: Color.blue.opacity(focused ? 0.22 : 0), radius: 4)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        )
        .overlay {
            if mode != .fixed {
                MiniWindowResizeOverlay(
                    frame: CGRect(x: mode.position.x, y: mode.position.y, width: size.width, height: size.height),
                    minimum: CGSize(width: min(200, size.width), height: min(120, size.height)),
                    onBegin: {
                        onResizeBegin()
                        store.focusSession(session.id)
                    },
                    onResize: { frame in
                        store.setCanvasPosition(for: session.id, PanePoint(x: frame.minX, y: frame.minY))
                        store.setPaneSize(for: session.id, PaneSize(width: frame.width, height: frame.height))
                    },
                    onReset: {
                        onResizeBegin()
                        store.setPaneSize(for: session.id, nil)
                    })
            }
        }
        .shadow(
            color: .black.opacity(isCanvas ? (focused ? 0.35 : 0.2) : 0), radius: isCanvas ? 10 : 0, y: isCanvas ? 4 : 0
        )

        let origin: CGPoint = {
            CGPoint(x: max(0, mode.position.x + moveOffset.width), y: max(0, mode.position.y + moveOffset.height))
        }()
        ZStack(alignment: .topLeading) {
            pane.opacity(collapsed ? 0 : 1).allowsHitTesting(!collapsed).accessibilityHidden(collapsed)
            if collapsed, let owner = store.glassBallOwner(in: self.pane) {
                GlassBallView(name: owner.name, status: store.glassBallStatus(for: owner), reduceMotion: reduceMotion) {
                    store.focusSession(owner.id)
                }
            }
        }
        .frame(
            width: collapsed ? GlassBallStatus.compactSize.width : size.width,
            height: collapsed ? GlassBallStatus.compactSize.height : size.height, alignment: .topLeading
        )
        .overlay {
            if store.settings.glassBallSubagents && store.glassBallOwner(in: self.pane) != nil && !store.isDemoMode
                && store.maximizedSessionID == nil && store.settings.workspaceMode == .sessions
            {
                GlassBallHoverRegion(paneID: self.pane.id, onHover: onHover).accessibilityHidden(true)
            }
        }
        .offset(x: origin.x, y: origin.y)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(store.isDemoMode ? "Demo mini window" : "\(session.name) mini window")
        .accessibilityIdentifier("pane-\(self.pane.id)")
    }

    private func commitMove(_ t: CGSize) {
        guard case .canvas(let p) = mode else { return }
        moveOffset = .zero
        onMove(nil)
        store.setCanvasPosition(for: session.id, PanePoint(x: p.x + t.width, y: p.y + t.height))
    }

}

struct PaneHeader: View {
    @EnvironmentObject var store: AppStore
    let session: ManagedSession
    var movable: Bool = false
    var compact: Bool = false
    var onMove: (CGSize) -> Void = { _ in }
    var onMoveEnd: (CGSize) -> Void = { _ in }

    private var focused: Bool { store.focusedSessionID == session.id }

    var body: some View {
        let st = store.status(of: session.id)
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                if movable { Image(systemName: "line.3.horizontal").font(.caption) }
                Circle().fill(st.color).frame(width: 8, height: 8)
                Image(systemName: session.kind.systemImage).foregroundStyle(.secondary).font(.caption)
                Text(session.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                if session.isOrchestrator { Image(systemName: "crown.fill").font(.caption2).foregroundStyle(.yellow) }
                if !compact { Text(st.label).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                Spacer(minLength: 4)
                if !compact {
                    Text(
                        session.kind == .cli
                            ? session.effectiveDirectory.abbreviatingHome : (store.runtime[session.id]?.title ?? "")
                    )
                    .font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 18)
            .overlay {
                MiniWindowMoveHandle(
                    name: session.name, onBegin: { store.focusSession(session.id) },
                    onMove: onMove, onEnd: onMoveEnd, movable: movable, drawsGrip: false,
                    onDoubleClick: { store.toggleMaximize(session.id) })
            }
            .help("Drag to move · Double-click to expand or restore")
            if !compact { fontControls }
            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22)
            .accessibilityLabel("Window actions for \(session.name)")
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(focused ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
        .contentShape(Rectangle())
    }

    private var fontControls: some View {
        HStack(spacing: 2) {
            Button {
                store.adjustFont(for: session.id, by: -1)
            } label: {
                Image(systemName: "minus")
            }
            .accessibilityLabel("Decrease font size for \(session.name)")
            Text(store.textSizeLabel(for: session))
                .font(.caption).monospacedDigit().frame(minWidth: 18)
                .foregroundStyle(session.fontSizeOverride == nil ? .secondary : .primary)
            Button {
                store.adjustFont(for: session.id, by: 1)
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Increase font size for \(session.name)")
            if session.fontSizeOverride != nil {
                Button {
                    store.resetFont(for: session.id)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .help("Scale text automatically with window size")
                .accessibilityLabel("Automatic text size for \(session.name)")
            }
        }
        .buttonStyle(.borderless).font(.caption)
        .help("Per-pane font size (⌘+ / ⌘− / ⌘0 on the focused pane)")
    }

    @ViewBuilder private var menuItems: some View {
        if let owner = store.browserOwner(for: session) {
            Toggle(
                "Split terminal and browser",
                isOn: Binding(
                    get: { owner.browserSplitEnabled },
                    set: { store.setBrowserSplit(for: session, enabled: $0) }))
        }
        Section("Text size") {
            Toggle(
                session.kind == .browser ? "Fit page width" : "Scale text with window",
                isOn: Binding(
                    get: { session.fontSizeOverride == nil },
                    set: { store.setAutomaticTextSize(for: session.id, enabled: $0) }))
            Button("Smaller text") { store.adjustFont(for: session.id, by: -1) }
            Button("Larger text") { store.adjustFont(for: session.id, by: 1) }
        }
        Section("Pane size") {
            ForEach(PaneSizePreset.allCases) { p in Button(p.label) { store.setPaneSize(for: session.id, p.size) } }
            Button("Reset to default") { store.setPaneSize(for: session.id, nil) }
        }
        Button(store.maximizedSessionID == nil ? "Maximize" : "Restore panes") {
            store.toggleMaximize(session.id)
        }
        if movable {
            Button("Bring to front") { store.raisePane(session.id) }
            Menu("Move window") {
                Button("Left") { moveBy(x: -40, y: 0) }
                Button("Right") { moveBy(x: 40, y: 0) }
                Button("Up") { moveBy(x: 0, y: -40) }
                Button("Down") { moveBy(x: 0, y: 40) }
            }
        }
        Divider()
        if store.cliTabSource(for: session.id).flatMap({ store.profile(for: $0) }) != nil {
            Button("New CLI Tab") { store.addCLITab(to: session.id) }
        }
        if session.kind == .browser {
            Button("New Browser Tab") { store.addBrowserTab(to: session.id) }
        }
        if session.kind == .cli {
            Button("Inject note…") {
                store.focusedSessionID = session.id
                store.showInjectSheet = true
            }
            Button("Inject context now") { store.injectContextNow(session.id) }
        }
        Button("Restart") { store.restartSession(session.id) }
        Button("Stop") { store.stopSession(session.id) }
        Divider()
        Button("Remove session", role: .destructive) { store.removeSession(session.id) }
    }

    private func moveBy(x: Double, y: Double) {
        let position = session.canvasPosition ?? PanePoint(x: 0, y: 0)
        store.setCanvasPosition(for: session.id, PanePoint(x: position.x + x, y: position.y + y))
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
                    chip(
                        "checklist",
                        open.isEmpty
                            ? "no tasks"
                            : "\(open.count) open: " + open.prefix(3).map { "#\($0.id)" }.joined(separator: " "))
                    if let q = rt.pendingQuestion { chip("questionmark.circle", q, color: .orange) }
                    if let m = rt.programMessage, !m.isEmpty { chip("info.circle", m) }
                    if let code = rt.exitCode { chip("xmark.circle", "exit \(code)", color: .red) }
                } else {
                    if let t = rt.title, !t.isEmpty { chip("doc.text", t) }
                    if let host = URL(string: store.browsers.controllers[session.id]?.urlText ?? "")?.host {
                        chip("globe", host)
                    }
                    chip("checklist", open.isEmpty ? "no tasks" : "\(open.count) open")
                }
                chip(
                    "textformat.size",
                    "\(store.textSizeLabel(for: session))\(session.kind == .cli ? " pt" : "")\(session.fontSizeOverride == nil ? " (auto)" : " (fixed)")"
                )
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
