import AppKit
import SwiftUI

struct AgentDeckIcon: View {
    @EnvironmentObject private var store: AppStore

    private static let image = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
        .flatMap { NSImage(contentsOf: $0) }

    var body: some View {
        let icon = Group {
            if let image = Self.image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "rectangle.3.group").resizable().scaledToFit()
            }
        }

        icon
            .overlay(alignment: .topTrailing) {
                badgeOverlay
            }
            .help(tooltipText)
    }

    @ViewBuilder
    private var badgeOverlay: some View {
        switch store.desktopNotificationState {
        case .waitingForInput(let count):
            NotificationBadgeView(
                text: count > 1 ? "\(count)" : "?",
                color: .orange
            )
        case .finished(let count):
            NotificationBadgeView(
                text: count > 1 ? "\(count)" : "✓",
                color: .green
            )
        case .none:
            EmptyView()
        }
    }

    private var tooltipText: String {
        switch store.desktopNotificationState {
        case .waitingForInput(let count):
            let names = store.sessions.filter { $0.kind == .cli && store.status(of: $0.id) == .waitingForUser }.map(
                \.name
            )
            .joined(separator: ", ")
            return count > 1 ? "\(count) agents waiting for input (\(names))" : "Agent waiting for input: \(names)"
        case .finished(let count):
            let names = store.sessions.filter { store.finishedSessionIDs.contains($0.id) }.map(\.name)
                .joined(separator: ", ")
            return count > 1 ? "\(count) agents finished (\(names))" : "Agent finished: \(names)"
        case .none:
            return "AgentDeck"
        }
    }
}

private struct NotificationBadgeView: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 2)
            .frame(minWidth: 10, minHeight: 10)
            .background(color, in: Capsule())
            .overlay(Capsule().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1))
            .offset(x: 3, y: -3)
    }
}
