import SwiftUI

struct BottomPanelView: View {
    @EnvironmentObject var store: AppStore
    @State private var tab = 0
    @State private var editing: BoardTask?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $tab) {
                    Text("Task Board (\(store.tasks.filter { $0.status != .done }.count))").tag(0)
                    Text("Log").tag(1)
                }
                .pickerStyle(.segmented).frame(width: 240)
                Spacer()
                if tab == 0 {
                    Button { editing = BoardTask(id: 0, title: "") } label: { Label("Add Task", systemImage: "plus") }
                } else {
                    Button("Clear log") { store.log.removeAll(); store.scheduleSave() }
                }
            }
            .padding(6)
            Divider()
            if tab == 0 { TaskBoardView(editing: $editing) } else { LogView() }
        }
        .sheet(item: $editing) { TaskEditorSheet(task: $0) }
    }
}

struct TaskBoardView: View {
    @EnvironmentObject var store: AppStore
    @Binding var editing: BoardTask?
    @State private var selection = Set<Int>()

    var body: some View {
        Table(store.tasks, selection: $selection) {
            TableColumn("#") { t in Text("\(t.id)").foregroundStyle(.secondary) }.width(32)
            TableColumn("Status") { t in
                Picker("", selection: Binding(get: { t.status }, set: { v in var n = t; n.status = v; store.updateTask(n) })) {
                    ForEach(TaskStatus.allCases) { Label($0.label, systemImage: $0.systemImage).tag($0) }
                }.labelsHidden()
            }.width(120)
            TableColumn("Title") { t in
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.title).strikethrough(t.status == .done)
                    if !t.description.isEmpty { Text(t.description).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
            }
            TableColumn("Owner") { t in
                Picker("", selection: Binding(get: { t.ownerSessionID }, set: { v in var n = t; n.ownerSessionID = v; store.updateTask(n) })) {
                    Text("Unassigned").tag(UUID?.none)
                    ForEach(store.sessions) { s in Text(s.name).tag(UUID?.some(s.id)) }
                }.labelsHidden()
            }.width(140)
            TableColumn("Notes") { t in Text(t.notes.components(separatedBy: "\n").last ?? "").font(.caption).lineLimit(1) }
            TableColumn("By") { t in Text(t.createdBy).font(.caption).foregroundStyle(.secondary) }.width(80)
        }
        .contextMenu(forSelectionType: Int.self) { ids in
            Button("Edit") { if let id = ids.first { editing = store.tasks.first { $0.id == id } } }
            Menu("Hand off to") {
                ForEach(store.sessions.filter { $0.kind == .cli }) { s in
                    Button(s.name) {
                        for id in ids { _ = try? store.handoff(from: nil, to: s, taskID: id, title: nil, description: nil, note: nil) }
                    }
                }
            }
            Divider()
            Button("Delete", role: .destructive) { for id in ids { store.deleteTask(id) } }
        } primaryAction: { ids in
            if let id = ids.first { editing = store.tasks.first { $0.id == id } }
        }
    }
}

struct TaskEditorSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var task: BoardTask

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(task.id == 0 ? "New Task" : "Task #\(task.id)").font(.title3).bold()
            Form {
                TextField("Title", text: $task.title)
                Picker("Status", selection: $task.status) { ForEach(TaskStatus.allCases) { Text($0.label).tag($0) } }
                Picker("Owner", selection: $task.ownerSessionID) {
                    Text("Unassigned").tag(UUID?.none)
                    ForEach(store.sessions) { s in Text(s.name).tag(UUID?.some(s.id)) }
                }
                LabeledContent("Description") {
                    TextEditor(text: $task.description).font(.body).frame(height: 70)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3)))
                }
                LabeledContent("Notes") {
                    TextEditor(text: $task.notes).font(.body).frame(height: 90)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3)))
                }
            }
            HStack {
                if task.id != 0 { Button("Delete", role: .destructive) { store.deleteTask(task.id); dismiss() } }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(task.id == 0 ? "Create" : "Save") {
                    if task.id == 0 {
                        store.createTask(title: task.title, description: task.description, owner: task.ownerSessionID,
                                         status: task.status, notes: task.notes)
                    } else { store.updateTask(task) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction).disabled(task.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20).frame(width: 520)
    }
}

struct LogView: View {
    @EnvironmentObject var store: AppStore
    private static let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f }()

    var body: some View {
        List(Array(store.log.reversed())) { e in
            HStack(alignment: .top, spacing: 8) {
                Text(Self.fmt.string(from: e.at)).foregroundStyle(.tertiary)
                Text(e.source).bold().frame(minWidth: 70, alignment: .leading)
                    .foregroundStyle(e.level == .error ? .red : e.level == .warn ? .orange : .primary)
                Text(e.message).textSelection(.enabled)
            }
            .font(.system(size: 11, design: .monospaced))
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
    }
}
