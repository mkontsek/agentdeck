import SwiftUI

/// Stable session keys keep the terminal attached while focus moves to its owned browser.
struct PaneSessionContent: View {
    @EnvironmentObject var store: AppStore
    let pane: SessionPane

    var body: some View {
        GeometryReader { geometry in
            let sessions = store.visibleSessions(in: pane)
            let horizontal = SubagentSplitLayout.automatic.isHorizontal(in: geometry.size)
            let layout = horizontal ? AnyLayout(HStackLayout(spacing: 1)) : AnyLayout(VStackLayout(spacing: 1))
            layout {
                ForEach(sessions) { session in
                    ManagedSessionContent(session: session)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
            }
            .background(Color(nsColor: .separatorColor))
        }
    }
}
