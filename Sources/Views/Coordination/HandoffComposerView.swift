import SwiftUI

struct HandoffComposerView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let task: BoardTask
    @State private var targetID: UUID?
    @State private var summary = ""
    @State private var constraints = ""
    @State private var artifacts = ""
    @State private var verification = ""
    @State private var nextAction = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hand off #\(task.id)").font(.title2.bold())
            Text(task.title).font(.headline)
            Text(
                "The recipient receives this package and the task’s shared objective and notes. Ownership changes when they accept."
            )
            .foregroundStyle(.secondary)
            Form {
                Picker("Recipient", selection: $targetID) {
                    Text("Choose a session").tag(UUID?.none)
                    ForEach(
                        store.sessions.filter {
                            $0.kind == .cli && store.profile(for: $0)?.supportsMCP == true
                                && $0.id != task.ownerSessionID
                        }
                    ) { session in
                        Text(session.name).tag(UUID?.some(session.id))
                    }
                }
                TextField("Published summary", text: $summary, axis: .vertical).lineLimit(2...4)
                TextField("Constraints", text: $constraints, axis: .vertical).lineLimit(2...3)
                TextField("Artifact paths or URLs (one per line)", text: $artifacts, axis: .vertical).lineLimit(2...4)
                TextField("Verification and results", text: $verification, axis: .vertical).lineLimit(2...4)
                TextField("Next action", text: $nextAction, axis: .vertical).lineLimit(2...3)
            }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Approve and send") { send() }.keyboardShortcut(.defaultAction)
                    .disabled(targetID == nil || nextAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 580)
    }

    private func send() {
        guard let target = store.session(targetID) else { return }
        do {
            _ = try store.handoff(
                from: nil, to: target, taskID: task.id, title: nil, description: nil, note: summary,
                constraints: constraints,
                artifacts: artifacts.components(separatedBy: .newlines).filter { !$0.isEmpty },
                verification: verification, nextAction: nextAction)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
