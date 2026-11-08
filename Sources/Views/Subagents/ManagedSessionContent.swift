import SwiftUI

struct ManagedSessionContent: View {
    @EnvironmentObject var store: AppStore
    let session: ManagedSession

    var body: some View {
        Group {
            switch session.kind {
            case .cli: TerminalPaneView(session: session)
            case .browser: BrowserPaneView(session: session)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if store.focusedSessionID != session.id {
                PaneFocusOverlay {
                    store.focusSession(session.id)
                }.accessibilityLabel("Focus \(session.name)")
            }
        }
    }
}
