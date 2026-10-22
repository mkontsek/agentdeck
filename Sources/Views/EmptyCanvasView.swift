import SwiftUI

struct EmptyCanvasView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(spacing: 20) {
            AgentDeckIcon()
                .frame(width: 80, height: 80)
                .accessibilityLabel("AgentDeck")
            Text("No sessions yet")
                .font(.system(size: 30, weight: .semibold))
            Text(
                "Your agents share this canvas. Open the default collection,\nor add a CLI agent or browser of your own."
            )
            .font(.title3)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Open default sessions") { store.openDefaultSessions() }
                    .buttonStyle(.borderedProminent)
                Button("New session…") { store.showNewSession = true }
                    .buttonStyle(.bordered)
            }
            .controlSize(.large)
            Text("⌘N to add a session").font(.callout).foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .accessibilityIdentifier("empty-canvas")
    }
}
