import SwiftUI

struct TaskDetailView: View {
    @EnvironmentObject var store: AppStore
    let task: BoardTask
    var edit: () -> Void
    @State private var showHandoff = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(task.status.label, systemImage: task.status.systemImage).foregroundStyle(.secondary)
                        Text(task.title).font(.title.bold()).textSelection(.enabled)
                        Text("#\(task.id) · \(task.ownerSessionID.map(store.name(of:)) ?? "Unassigned")")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Edit", action: edit)
                }
                HStack {
                    if let id = task.ownerSessionID, store.session(id) != nil {
                        Button("Open session") {
                            store.selectTab(id)
                            store.settings.workspaceMode = .sessions
                        }
                    }
                    Button("Hand off…") { showHandoff = true }
                        .disabled(store.handoffs.contains { $0.taskID == task.id && $0.status.isOpen })
                    if task.status == .awaitingApproval {
                        Button("Approve completion") { setStatus(.done) }.buttonStyle(.borderedProminent)
                            .disabled(!store.unfinishedDependencies(of: task).isEmpty)
                        Button("Request changes") { setStatus(.inProgress) }
                    } else if task.status == .review {
                        Button("Request completion approval") { setStatus(.awaitingApproval) }
                    }
                }
                if !task.description.isEmpty { section("Objective", task.description) }
                if !task.dependencies.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Dependencies").font(.headline)
                        ForEach(task.dependencies, id: \.self) { id in
                            Button {
                                store.openTask(id)
                            } label: {
                                Label(
                                    "#\(id) \(store.tasks.first { $0.id == id }?.title ?? "Missing task")",
                                    systemImage: store.tasks.first { $0.id == id }?.status == .done
                                        ? "checkmark.circle.fill" : "clock")
                            }.buttonStyle(.link)
                        }
                    }
                }
                if !task.notes.isEmpty { section("Shared findings and evidence", task.notes) }
                let transfers = store.handoffs.filter { $0.taskID == task.id }.reversed()
                ForEach(Array(transfers)) { transfer in HandoffCardView(handoff: transfer) }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Work history").font(.headline)
                    ForEach(task.events.reversed()) { event in
                        HStack(alignment: .top) {
                            Image(systemName: "circle.fill").font(.system(size: 6)).padding(.top, 5).foregroundStyle(
                                .tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.message)
                                Text("\(event.actor) · \(event.at.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showHandoff) { HandoffComposerView(task: task) }
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func setStatus(_ status: TaskStatus) {
        var updated = task
        updated.status = status
        store.updateTask(updated)
    }
}
