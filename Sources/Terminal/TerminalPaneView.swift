import AppKit
import SwiftUI

struct TerminalPaneView: View {
    @EnvironmentObject var store: AppStore
    let session: ManagedSession

    var body: some View {
        let rt = store.runtime[session.id]
        ZStack {
            TerminalRepresentable(
                terminal: store.terminals.view(for: session.id), font: store.font(for: session),
                focused: store.focusedSessionID == session.id, generation: rt?.generation ?? 0)
            if rt?.isRunning != true {
                VStack(spacing: 8) {
                    if rt?.exitCode == 127, let profile = store.profile(for: session), let url = profile.setupURL {
                        Text("Set up \(profile.name)").font(.headline)
                        Text("The command could not start. Install the CLI, then restart this pane.")
                            .font(.callout).multilineTextAlignment(.center)
                        Link("Installation instructions", destination: url)
                    } else {
                        Text(rt?.exitCode.map { "Process exited (code \($0))" } ?? "Not running").font(.headline)
                    }
                    Button("Restart") { store.restartSession(session.id) }.buttonStyle(.borderedProminent)
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

struct TerminalRepresentable: NSViewRepresentable {
    let terminal: DeckTerminalView?
    let font: NSFont
    let focused: Bool
    let generation: Int

    final class Coordinator {
        var wasFocused = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> TerminalContainerView {
        let c = TerminalContainerView()
        c.autoresizesSubviews = true
        attach(to: c, coordinator: context.coordinator)
        return c
    }

    func updateNSView(_ c: TerminalContainerView, context: Context) {
        attach(to: c, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ c: TerminalContainerView, coordinator: Coordinator) {
        // The host retains the PTY and screen while this tab is hidden.
        c.focusWhenAttached = false
        for view in c.subviews { view.removeFromSuperview() }
    }

    private func attach(to c: TerminalContainerView, coordinator: Coordinator) {
        let becameFocused = focused && !coordinator.wasFocused
        coordinator.wasFocused = focused
        guard let tv = terminal else {
            for view in c.subviews { view.removeFromSuperview() }
            c.focusWhenAttached = false
            return
        }
        var attached = false
        if tv.superview !== c {
            for view in c.subviews { view.removeFromSuperview() }
            tv.removeFromSuperview()
            tv.frame = c.bounds
            tv.autoresizingMask = [.width, .height]
            c.addSubview(tv)
            attached = true
        }
        c.focusWhenAttached = focused && (attached || becameFocused || c.focusWhenAttached)
        c.focusTerminalIfNeeded()
        if tv.font.pointSize != font.pointSize || tv.font.fontName != font.fontName { tv.font = font }
    }
}

/// Defers keyboard focus until SwiftUI has attached the selected tab to a window.
final class TerminalContainerView: NSView {
    var focusWhenAttached = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusTerminalIfNeeded()
    }

    func focusTerminalIfNeeded() {
        guard focusWhenAttached, let window, let terminal = subviews.first else { return }
        focusWhenAttached = false
        window.makeFirstResponder(terminal)
    }
}
