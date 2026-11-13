import SwiftUI

struct WorkerResumeSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let workerID: UUID
    @State private var instructions = ""
    @State private var requestID = UUID()
    @State private var error: String?

    private var request: WorkerResumeRequest? {
        let _ = store.workerResumeRevision
        return store.workerResumes.requests.last { $0.workerID == workerID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Resume Worker").font(.title2)
            Text(
                "Starts an explicit native Codex turn when its exact thread is idle in the shared server. The terminal draft stays untouched. Other transports fail safely."
            ).font(.callout)
            if let request {
                LabeledContent("Receipt", value: request.phase.rawValue)
                Text(request.detail).font(.caption).lineLimit(5).textSelection(.enabled)
                Text("Request: \(request.id.uuidString)").font(.caption).textSelection(.enabled)
                if request.phase.reservesWorker {
                    Button(request.phase == .uncertain ? "Cancel / reconcile" : "Cancel continuation") {
                        store.cancelWorkerResume(workerID)
                    }
                }
            }
            if store.session(workerID)?.resumeStopped == true {
                Text("This worker was explicitly stopped. Enable Resume does not start work.")
                Button("Enable Resume") { store.enableWorkerResume(workerID) }
            }
            Text("Next step")
            TextEditor(text: $instructions).frame(minHeight: 120).border(.secondary)
                .accessibilityLabel("Continuation instructions")
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            HStack {
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Resume") {
                    do {
                        guard let parentID = store.session(workerID)?.parentSessionID else { return }
                        _ = try store.resumeWorker(
                            from: parentID, workerID: workerID, requestID: requestID, instructions: instructions)
                        requestID = UUID()
                        error = nil
                    } catch { self.error = error.localizedDescription }
                }
                .disabled(
                    instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || request?.phase.reservesWorker == true)
            }
        }.padding(20).frame(width: 520)
    }
}
