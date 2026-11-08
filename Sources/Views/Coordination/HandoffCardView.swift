import SwiftUI

struct HandoffCardView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var historyExpanded = false
    let handoff: TaskHandoff

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("\(handoff.fromName) → \(handoff.targetName)", systemImage: "arrow.triangle.swap").font(
                        .headline)
                    Spacer()
                    Text(handoff.status.label).font(.caption.bold())
                }
                if !handoff.detail.isEmpty { Text(handoff.detail).font(.caption).foregroundStyle(.secondary) }
                context("Objective", handoff.context.objective)
                context("Published summary", handoff.context.summary)
                context("Constraints", handoff.context.constraints)
                context("Artifacts", handoff.context.artifacts.joined(separator: "\n"))
                context("Verification", handoff.context.verification)
                context("Next action", handoff.context.nextAction)
                DisclosureGroup("Shared notes and delivery history", isExpanded: $historyExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(handoff.context.sharedNotes).textSelection(.enabled)
                        ForEach(handoff.events) { event in
                            Text(
                                "\(event.at.formatted(date: .omitted, time: .shortened)) · \(event.actor) · \(event.message)"
                            )
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion), value: historyExpanded)
                HStack {
                    if handoff.status == .awaitingApproval {
                        Button("Approve handoff") { store.approveHandoff(handoff.id) }.buttonStyle(.borderedProminent)
                    }
                    if handoff.status == .failed || handoff.status == .delivered {
                        Button("Retry notification") { store.retryHandoff(handoff.id) }
                    }
                    if handoff.status.isOpen {
                        Button("Cancel handoff") {
                            store.transitionHandoff(handoff.id, to: .cancelled, detail: "User cancelled", actor: "user")
                        }
                    }
                    if store.session(handoff.targetSessionID) != nil {
                        Button("Open recipient") {
                            store.selectTab(handoff.targetSessionID)
                            store.settings.workspaceMode = .sessions
                        }
                    }
                }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func context(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.caption.bold()).foregroundStyle(.secondary)
                Text(value).textSelection(.enabled)
            }
        }
    }
}
