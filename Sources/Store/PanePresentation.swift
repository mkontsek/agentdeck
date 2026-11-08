import AppKit

extension AppStore {
    /// Called once by bootstrap. Wait for both the restored/default sessions and a measured viewport.
    func prepareStartupLayout() {
        settings.workspaceMode = .sessions
        startupPaneFitPending = true
        fitStartupCanvasIfNeeded()
    }

    func fitStartupCanvasIfNeeded() {
        guard startupPaneFitPending, !panes.isEmpty,
            canvasViewport.width.isFinite, canvasViewport.height.isFinite,
            canvasViewport.width > 100, canvasViewport.height > 100
        else { return }
        startupPaneFitPending = false
        fillCanvas()
    }

    func updateCanvasViewport(_ size: CGSize) {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
        if canvasViewport != size { canvasViewport = size }
        fitStartupCanvasIfNeeded()
        ensureCanvasPositions(viewportWidth: size.width)
        applyFonts()
    }

    func displayedPaneSize(for session: ManagedSession) -> PaneSize {
        if canvasViewport.width > 0, canvasViewport.height > 0 {
            if self.session(maximizedSessionID)?.paneID == session.paneID {
                return PaneSize(
                    width: canvasViewport.width, height: canvasViewport.height)
            }
            if settings.layoutMode == .grid { return gridPaneSize(in: canvasViewport) }
        }
        return paneSize(for: session)
    }

    func textSize(for session: ManagedSession) -> Double {
        if session.kind == .browser {
            if let override = session.fontSizeOverride {
                return PaneTextScale.points(
                    base: PaneTextScale.browserReference, size: PaneSizePreset.normal.size, override: override)
            }
            return (browsers.controllers[session.id]?.webView.pageZoom ?? 1) * PaneTextScale.browserReference
        }
        return PaneTextScale.points(
            base: settings.globalFontSize, size: displayedPaneSize(for: session), override: session.fontSizeOverride)
    }

    func textSizeLabel(for session: ManagedSession) -> String {
        if session.kind == .browser && session.fontSizeOverride == nil { return "Fit" }
        let size = textSize(for: session)
        if session.kind == .browser { return "\(Int((size / PaneTextScale.browserReference * 100).rounded()))%" }
        return size.formatted(.number.precision(.fractionLength(0...1)))
    }

    func font(for session: ManagedSession) -> NSFont {
        let size = textSize(for: session)
        return NSFont(name: settings.fontName, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    func applyTextSize(to session: ManagedSession) {
        if session.kind == .cli {
            terminals.setFont(id: session.id, font(for: session))
        } else if let webView = browsers.controllers[session.id]?.webView {
            webView.pageFit.setZoom(manual: browserZoomOverride(for: session))
        }
    }

    func browserZoomOverride(for session: ManagedSession) -> Double? {
        session.fontSizeOverride.map { _ in textSize(for: session) / PaneTextScale.browserReference }
    }

    func applyFonts() {
        for session in sessions { applyTextSize(to: session) }
    }

    func adjustFont(for id: UUID?, by delta: Double) {
        guard let id, var session = session(id), delta.isFinite else { return }
        session.fontSizeOverride = min(
            PaneTextScale.maximum, max(PaneTextScale.minimum, textSize(for: session) + delta))
        updateSession(session)
    }

    func setAutomaticTextSize(for id: UUID, enabled: Bool) {
        guard var session = session(id) else { return }
        session.fontSizeOverride = enabled ? nil : textSize(for: session)
        updateSession(session)
    }

    func resetFont(for id: UUID?) {
        guard let id else { return }
        setAutomaticTextSize(for: id, enabled: true)
    }

    func setPaneSize(for id: UUID, _ size: PaneSize?) {
        guard let session = session(id) else { return }
        if let size { guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return } }
        for index in sessions.indices where sessions[index].paneID == session.paneID { sessions[index].paneSize = size }
        for tab in sessions where tab.paneID == session.paneID { applyTextSize(to: tab) }
        scheduleSave()
    }

    func paneSize(for session: ManagedSession) -> PaneSize { session.paneSize ?? settings.defaultPanePreset.size }

    func gridPaneSize(in area: CGSize) -> PaneSize {
        let count = max(1, panes.count)
        let fit = max(1, Int((area.width - 8) / 328))
        let columns = max(1, min(settings.gridColumns, count, fit))
        let rows = Int(ceil(Double(count) / Double(columns)))
        return PaneSize(
            width: max(300, floor((area.width - 16 - 8 * Double(columns - 1)) / Double(columns))),
            height: max(220, floor((area.height - 16 - 8 * Double(rows - 1)) / Double(rows))))
    }

    func paneFrames(in area: CGSize) -> [UUID: CGRect] {
        let panes = panes
        let spacing = 8.0
        let count = max(1, panes.count)
        let fit = max(1, Int((area.width - 8) / 328))
        let columns = max(1, min(settings.gridColumns, count, fit))
        let size = gridPaneSize(in: area)
        return Dictionary(
            uniqueKeysWithValues: panes.enumerated().map { index, pane in
                if let maximized = maximizedSessionID, pane.tabs.contains(where: { $0.id == maximized }) {
                    return (
                        pane.id,
                        CGRect(origin: .zero, size: area)
                    )
                }
                if settings.layoutMode == .canvas {
                    let position = pane.activeSession.canvasPosition ?? PanePoint(x: 8, y: 8)
                    let size = paneSize(for: pane.activeSession)
                    return (pane.id, CGRect(x: position.x, y: position.y, width: size.width, height: size.height))
                }
                return (
                    pane.id,
                    CGRect(
                        x: 8 + Double(index % columns) * (size.width + spacing),
                        y: 8 + Double(index / columns) * (size.height + spacing), width: size.width, height: size.height
                    )
                )
            })
    }
}
