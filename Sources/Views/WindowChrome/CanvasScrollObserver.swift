import AppKit
import SwiftUI

/// Keep native terminal layers while panning; parsing and input continue in their existing owners.
struct CanvasScrollObserver: NSViewRepresentable {
    let store: AppStore
    let frames: [UUID: CGRect]
    let focusedPaneID: UUID?

    func makeNSView(context: Context) -> CanvasScrollObservationView {
        let view = CanvasScrollObservationView()
        view.store = store
        view.frames = frames
        view.focusedPaneID = focusedPaneID
        return view
    }

    func updateNSView(_ view: CanvasScrollObservationView, context: Context) {
        view.frames = frames
        view.focusedPaneID = focusedPaneID
        view.scheduleVisibilityRefresh()
    }

    static func dismantleNSView(_ view: CanvasScrollObservationView, coordinator: ()) { view.disconnect() }
}

final class CanvasScrollObservationView: NSView {
    weak var store: AppStore?
    var frames: [UUID: CGRect] = [:]
    var focusedPaneID: UUID?
    private weak var scrollView: NSScrollView?
    private var observer: NSObjectProtocol?
    private var inputObserver: NSObjectProtocol?
    private var resumeWork: DispatchWorkItem?
    private var refreshScheduled = false
    private var overviewRefreshScheduled = false
    private var overviewSourceID: UUID?
    private(set) var isInteracting = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        disconnect()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in self?.connect() }
    }

    private func connect() {
        guard observer == nil, window != nil, let scroll = enclosingScrollView else { return }
        scrollView = scroll
        overviewSourceID = store?.canvasOverview.attach { [weak self] origin in self?.moveViewport(to: origin) }
        scroll.contentView.postsBoundsChangedNotifications = true
        observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.deferBackgroundDrawing() }
        }
        inputObserver = NotificationCenter.default.addObserver(
            forName: DeckTerminalView.textInputNotification, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let terminal = notification.object as? DeckTerminalView,
                    terminal.enclosingScrollView === self.scrollView,
                    terminal.window?.firstResponder === terminal
                else { return }
                self.deferBackgroundDrawing()
            }
        }
        refreshVisibility()
    }

    private func deferBackgroundDrawing() {
        isInteracting = true
        refreshVisibility()
        resumeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isInteracting = false
            self.refreshVisibility()
        }
        resumeWork = work
        // A short quiet tail includes wheel momentum and typing bursts; the keyboard responder stays live.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120), execute: work)
    }

    func scheduleVisibilityRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            self.refreshVisibility()
        }
    }

    func refreshVisibility() {
        guard let store, let scroll = scrollView, let document = scroll.documentView else { return }
        scheduleOverviewRefresh()
        let visible = scroll.contentView.bounds
        for (id, terminal) in store.terminals.views {
            let attached = terminal.window === window && terminal.enclosingScrollView === scroll
            let frame = terminal.convert(terminal.bounds, to: document)
            let maximizedPane = store.session(store.maximizedSessionID)?.paneID
            let inMaximizedPane = maximizedPane == nil || store.session(id)?.paneID == maximizedPane
            let hasKeyboardFocus = terminal.window?.firstResponder === terminal
            terminal.defersCanvasDisplay =
                !hasKeyboardFocus
                && (!attached || !inMaximizedPane || !visible.intersects(frame) || isInteracting)
        }
    }

    private func moveViewport(to origin: CGPoint) {
        guard let store, store.settings.workspaceMode == .sessions, store.maximizedSessionID == nil,
            let scroll = scrollView, window != nil, enclosingScrollView === scroll
        else { return }
        let clip = scroll.contentView
        let proposed = CGRect(origin: origin, size: clip.bounds.size)
        clip.scroll(to: clip.constrainBoundsRect(proposed).origin)
        scroll.reflectScrolledClipView(clip)
        refreshVisibility()
    }

    private func scheduleOverviewRefresh() {
        guard let sourceID = overviewSourceID, !overviewRefreshScheduled else { return }
        overviewRefreshScheduled = true
        // Publish outside native/SwiftUI layout and coalesce within one main-queue turn.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.overviewSourceID == sourceID else { return }
            self.overviewRefreshScheduled = false
            guard let store = self.store, let scroll = self.scrollView, let document = scroll.documentView,
                self.window != nil, self.enclosingScrollView === scroll
            else { return }
            store.canvasOverview.update(
                CanvasOverviewSnapshot(
                    bounds: document.bounds, viewport: scroll.documentVisibleRect,
                    panes: self.frames, focusedPaneID: self.focusedPaneID),
                from: sourceID)
        }
    }

    func disconnect() {
        if let sourceID = overviewSourceID, let overview = store?.canvasOverview {
            DispatchQueue.main.async { overview.detach(sourceID) }
        }
        overviewSourceID = nil
        overviewRefreshScheduled = false
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if let inputObserver { NotificationCenter.default.removeObserver(inputObserver) }
        observer = nil
        inputObserver = nil
        resumeWork?.cancel()
        resumeWork = nil
        isInteracting = false
        scrollView = nil
        for terminal in store?.terminals.views.values ?? [:].values { terminal.defersCanvasDisplay = false }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if let inputObserver { NotificationCenter.default.removeObserver(inputObserver) }
        resumeWork?.cancel()
    }
}
