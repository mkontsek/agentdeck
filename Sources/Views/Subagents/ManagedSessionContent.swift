import SwiftUI

struct ManagedSessionContent: View {
    @EnvironmentObject var store: AppStore
    let session: ManagedSession
    /// Edges that meet the mini-window border and are kept clear of it by `PaneChrome.contentInset`.
    var borderEdges: Edge.Set = []
    /// Whether this view paints its own gutter. A lone session leaves that to the fill `PaneSessionContent` already
    /// has: one more fill behind every terminal measurably slowed canvas scrolling.
    var fillsGutter = false

    var body: some View {
        Group {
            switch session.kind {
            case .cli: TerminalPaneView(session: session)
            case .browser: BrowserPaneView(session: session)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(borderEdges, PaneChrome.contentInset)
        .background(fillsGutter ? gutter : .clear)
        .overlay {
            if store.focusedSessionID != session.id {
                PaneFocusOverlay {
                    store.focusSession(session.id)
                }.accessibilityLabel("Focus \(session.name)")
            }
        }
    }

    private var gutter: Color {
        store.terminalGutterColor(for: session).map { Color(nsColor: $0) } ?? .clear
    }
}
