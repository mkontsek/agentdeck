import AppKit
import SwiftUI

/// Keep native terminal layers while panning; parsing and input continue in their existing owners.
struct CanvasScrollObserver: NSViewRepresentable {
    let store: AppStore

    func makeNSView(context: Context) -> CanvasScrollObservationView {
        let view = CanvasScrollObservationView()
        view.store = store
        return view
    }

    func updateNSView(_ view: CanvasScrollObservationView, context: Context) {
        view.scheduleVisibilityRefresh()
    }

    static func dismantleNSView(_ view: CanvasScrollObservationView, coordinator: ()) { view.disconnect() }
}

final class CanvasScrollObservationView: NSView {
    weak var store: AppStore?
    private weak var scrollView: NSScrollView?
    private var observer: NSObjectProtocol?
    private var inputObserver: NSObjectProtocol?
    private var resumeWork: DispatchWorkItem?
    private var refreshScheduled = false
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

    func disconnect() {
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
