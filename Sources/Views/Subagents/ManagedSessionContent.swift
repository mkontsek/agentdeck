import SwiftUI

struct ManagedSessionContent: View {
    @EnvironmentObject var store: AppStore
    let session: ManagedSession
    /// Edges that meet the mini-window border and are kept clear of it by `PaneChrome.contentInset`.
    var borderEdges: Edge.Set = []

    var body: some View {
        Group {
            switch session.kind {
            case .cli: TerminalPaneView(session: session)
            case .browser: BrowserPaneView(session: session)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(borderEdges, PaneChrome.contentInset)
        .background(gutter)
        .overlay {
            if store.focusedSessionID != session.id {
                PaneFocusOverlay {
                    store.focusSession(session.id)
                }.accessibilityLabel("Focus \(session.name)")
            }
        }
    }

    /// A terminal's gutter continues its background, so the inset reads as terminal padding.
    private var gutter: Color {
        guard session.kind == .cli, store.terminals.view(for: session.id) != nil else { return .clear }
        return Color(nsColor: TerminalHost.backgroundColor(dark: store.terminals.dark))
    }
}
