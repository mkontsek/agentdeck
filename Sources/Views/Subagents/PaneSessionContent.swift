import SwiftUI

/// Stable session keys keep the terminal attached while focus moves to its owned browser.
struct PaneSessionContent: View {
    @EnvironmentObject var store: AppStore
    let pane: SessionPane
    @State private var previewFraction: Double?

    var body: some View {
        GeometryReader { geometry in
            let sessions = store.visibleSessions(in: pane)
            let horizontal = SubagentSplitLayout.automatic.isHorizontal(in: geometry.size)
            let split = sessions.count == 2
            let sizing = BrowserSplitGeometry(
                size: geometry.size, isHorizontal: horizontal,
                fraction: previewFraction ?? sessions.first?.browserSplitFraction
                    ?? BrowserSplitGeometry.defaultFraction)
            let spacing = split ? sizing.dividerExtent : 0
            let layout =
                horizontal ? AnyLayout(HStackLayout(spacing: spacing)) : AnyLayout(VStackLayout(spacing: spacing))
            layout {
                ForEach(sessions) { session in
                    let size =
                        split
                        ? (session.id == sessions.first?.id ? sizing.firstSize : sizing.secondSize) : geometry.size
                    ManagedSessionContent(session: session)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                }
            }
            .background(Color(nsColor: .separatorColor))
            .overlay(alignment: .topLeading) {
                if split, let owner = sessions.first {
                    BrowserSplitDivider(
                        ownerID: owner.id, geometry: sizing,
                        onPreview: { previewFraction = $0 },
                        onFinish: { fraction in
                            if let fraction { store.setBrowserSplitFraction(for: owner.id, fraction) }
                            previewFraction = nil
                        }
                    )
                    .id(sessions.map(\.id))
                    .frame(width: sizing.dividerFrame.width, height: sizing.dividerFrame.height)
                    .offset(x: sizing.dividerFrame.minX, y: sizing.dividerFrame.minY)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Terminal and browser divider")
                    .accessibilityValue("Terminal \(Int((sizing.displayedFraction * 100).rounded())) percent")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: store.setBrowserSplitFraction(for: owner.id, sizing.displayedFraction + 0.05)
                        case .decrement: store.setBrowserSplitFraction(for: owner.id, sizing.displayedFraction - 0.05)
                        @unknown default: break
                        }
                        previewFraction = nil
                    }
                }
            }
            .onChange(of: geometry.size) { _, _ in previewFraction = nil }
            .onChange(of: sessions.map(\.id)) { _, _ in previewFraction = nil }
        }
    }
}
