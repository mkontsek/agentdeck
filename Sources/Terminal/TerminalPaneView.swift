import AppKit
import SwiftUI

struct TerminalPaneView: View {
    @EnvironmentObject var store: AppStore
    let session: ManagedSession

    var body: some View {
        let rt = store.runtime[session.id]
        ZStack {
            TerminalRepresentable(session: session, generation: rt?.generation ?? 0, fontSize: session.fontSizeOverride ?? store.settings.globalFontSize)
            if rt?.isRunning != true {
                VStack(spacing: 8) {
                    Text(rt?.exitCode.map { "Process exited (code \($0))" } ?? "Not running").font(.headline)
                    Button("Restart") { store.restartSession(session.id) }.buttonStyle(.borderedProminent)
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

struct TerminalRepresentable: NSViewRepresentable {
    let session: ManagedSession
    let generation: Int
    let fontSize: Double

    func makeNSView(context: Context) -> NSView {
        let c = NSView()
        c.autoresizesSubviews = true
        attach(to: c)
        return c
    }

    func updateNSView(_ c: NSView, context: Context) { attach(to: c) }

    private func attach(to c: NSView) {
        let store = AppStore.shared
        let tv = store.terminals.makeView(for: session.id, font: store.font(for: session))
        if tv.superview !== c {
            tv.removeFromSuperview()
            tv.frame = c.bounds
            tv.autoresizingMask = [.width, .height]
            c.addSubview(tv)
        }
        store.terminals.setFont(id: session.id, store.font(for: session))
    }
}
