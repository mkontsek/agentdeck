import SwiftUI

struct TaskEditorSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var task: BoardTask
    @State private var dependencyText = ""
    @State private var validationError: String?
    @State private var runInSubagent = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(task.id == 0 ? "New Task" : "Task #\(task.id)").font(.title3).bold()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Title").font(.headline)
                    TextField("What needs to be done?", text: $task.title).textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Task title")
                    HStack {
                        Picker("Status", selection: $task.status) {
                            ForEach(TaskStatus.allCases) { Text($0.label).tag($0) }
                        }
                        Picker("Owner", selection: $task.ownerSessionID) {
                            Text("Unassigned").tag(UUID?.none)
                            ForEach(store.sessions) { s in Text(s.name).tag(UUID?.some(s.id)) }
                        }
                    }.frame(maxWidth: .infinity)
                    Toggle("Require user approval before completion", isOn: $task.requiresApproval)
                    if task.id == 0, store.canDelegate(from: task.ownerSessionID) {
                        Toggle("Run in a subagent and keep the main conversation available", isOn: $runInSubagent)
                            .accessibilityIdentifier("task-run-subagent")
                        Text("Starts newly created To do or In progress tasks whose dependencies are complete.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Dependencies").font(.headline)
                        TextField("Task numbers, separated by commas", text: $dependencyText).textFieldStyle(
                            .roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Description").font(.headline)
                        TextEditor(text: $task.description).font(.body).frame(height: 100)
                            .accessibilityLabel("Task description")
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3)))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes").font(.headline)
                        TextEditor(text: $task.notes).font(.body).frame(height: 90)
                            .accessibilityLabel("Task notes")
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3)))
                    }
                }.padding(2).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let validationError { Text(validationError).foregroundStyle(.red) }
            HStack {
                if task.id != 0 {
                    Button("Delete", role: .destructive) {
                        store.deleteTask(task.id)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(task.id == 0 ? "Create" : "Save") {
                    let parts = dependencyText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    let ids = parts.compactMap(Int.init)
                    guard ids.count == parts.count else {
                        validationError = "Use comma-separated task numbers."
                        return
                    }
                    do { try store.validateDependencies(ids, for: task.id == 0 ? store.nextTaskID : task.id) } catch {
                        validationError = error.localizedDescription
                        return
                    }
                    task.dependencies = Array(Set(ids)).sorted()
                    if task.status != .todo && task.status != .blocked
                        && !store.unfinishedDependencies(of: task).isEmpty
                    {
                        validationError = "Complete dependencies before starting or completing this task."
                        return
                    }
                    if task.id == 0 {
                        var created = store.createTask(
                            title: task.title, description: task.description, owner: task.ownerSessionID,
                            status: task.status, notes: task.notes)
                        created.dependencies = task.dependencies
                        created.requiresApproval = task.requiresApproval
                        store.updateTask(created)
                        if runInSubagent, created.status == .todo || created.status == .inProgress,
                            store.unfinishedDependencies(of: created).isEmpty,
                            let parent = created.ownerSessionID, store.canDelegate(from: parent)
                        {
                            do { try store.delegateTask(from: parent, taskID: created.id) } catch {
                                task = created
                                validationError = "Task created. Worker could not start: \(error.localizedDescription)"
                                return
                            }
                        }
                        store.openTask(created.id)
                    } else {
                        store.updateTask(task)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction).disabled(task.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24).frame(width: 600, height: 620)
        .onAppear {
            dependencyText = task.dependencies.map(String.init).joined(separator: ", ")
            if task.id == 0, task.ownerSessionID == nil, let focused = store.session(store.focusedSessionID) {
                let parent = store.parentConversationID(for: focused) ?? focused.id
                if store.canDelegate(from: parent) { task.ownerSessionID = parent }
            }
        }
    }
}
