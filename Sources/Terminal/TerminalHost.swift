import AppKit
import SwiftTerm

/// A terminal view that reports focus clicks back to the host.
final class DeckTerminalView: LocalProcessTerminalView {
    var onFocus: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onFocus?()
        if window?.firstResponder !== self { window?.makeFirstResponder(self) }
        super.mouseDown(with: event)
    }
}

/// Owns every PTY-backed terminal view. Views outlive SwiftUI re-renders so the child process is never restarted
/// by a layout change.
@MainActor
final class TerminalHost: LocalProcessTerminalViewDelegate {
    private(set) var views: [UUID: DeckTerminalView] = [:]
    private var ids: [ObjectIdentifier: UUID] = [:]

    var onOutput: ((UUID) -> Void)?
    var onExit: ((UUID, Int32?) -> Void)?
    var onTitle: ((UUID, String) -> Void)?
    var onFocus: ((UUID) -> Void)?
    var onProgramStatus: ((UUID, String?, String?) -> Void)?

    func view(for id: UUID) -> DeckTerminalView? { views[id] }
    func isRunning(_ id: UUID) -> Bool { views[id] != nil }

    private(set) var dark = true

    func makeView(for id: UUID, font: NSFont) -> DeckTerminalView {
        if let v = views[id] { return v }
        let v = DeckTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        v.font = font
        theme(v, dark: dark)
        v.processDelegate = self
        v.onFocus = { [weak self] in self?.onFocus?(id) }
        v.setProcessOutputHandler { [weak self] in
            DispatchQueue.main.async { self?.onOutput?(id) }
        }
        views[id] = v
        ids[ObjectIdentifier(v)] = id
        return v
    }

    func start(id: UUID, command: String, cwd: String, environment: [String: String], font: NSFont) {
        let v = makeView(for: id, font: font)
        let env = environment.map { "\($0.key)=\($0.value)" }
        v.startProcess(executable: "/bin/zsh", args: ["-l", "-i", "-c", command], environment: env,
                       execName: "-zsh", currentDirectory: cwd)
    }

    func terminate(id: UUID) {
        guard let v = views[id] else { return }
        v.terminate()
    }

    /// Drop the view entirely (session removed or about to be restarted).
    func dispose(id: UUID) {
        guard let v = views[id] else { return }
        v.terminate()
        v.removeFromSuperview()
        ids[ObjectIdentifier(v)] = nil
        views[id] = nil
    }

    func send(id: UUID, text: String) {
        views[id]?.send(txt: text)
    }

    func applyTheme(dark: Bool) {
        self.dark = dark
        for v in views.values { theme(v, dark: dark) }
    }

    private func theme(_ v: DeckTerminalView, dark: Bool) {
        if dark {
            v.nativeBackgroundColor = NSColor(calibratedRed: 0.09, green: 0.09, blue: 0.11, alpha: 1)
            v.nativeForegroundColor = NSColor(calibratedWhite: 0.92, alpha: 1)
            v.caretColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        } else {
            v.nativeBackgroundColor = NSColor(calibratedWhite: 0.99, alpha: 1)
            v.nativeForegroundColor = NSColor(calibratedWhite: 0.12, alpha: 1)
            v.caretColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        }
    }

    func setFont(id: UUID, _ font: NSFont) {
        guard let v = views[id] else { return }
        if v.font.pointSize != font.pointSize || v.font.fontName != font.fontName { v.font = font }
    }

    func visibleLines(id: UUID) -> [String] {
        guard let v = views[id] else { return [] }
        let rows = v.terminalDimensions.rows
        guard rows > 0 else { return [] }
        return v.visibleRowsText(0..<rows).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    // MARK: LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        if let id = ids[ObjectIdentifier(source)] { onTitle?(id, title) }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        if let id = ids[ObjectIdentifier(source)] { onExit?(id, exitCode) }
    }

    func processFailedToStart(source: TerminalView, error: LocalProcessError) {
        if let id = ids[ObjectIdentifier(source)] { onExit?(id, 127) }
    }

    func programStatusChanged(source: TerminalView, records: [TerminalProgramStatus]) {
        guard let id = ids[ObjectIdentifier(source)] else { return }
        let root = records.first(where: { $0.id.isEmpty }) ?? records.first
        onProgramStatus?(id, root?.state.rawValue, root?.message ?? root?.title)
    }

}
