import SwiftUI

struct CoordinationBoardView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var search = ""
    @State private var includeDone = false
    @State private var editing: BoardTask?

    private var visibleTasks: [BoardTask] {
        store.tasks.filter {
            (includeDone || $0.status != .done)
                && (search.isEmpty || "\($0.id) \($0.title) \($0.description)".localizedCaseInsensitiveContains(search))
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shared work").font(.largeTitle.bold())
                    Text(
                        "\(store.tasks.filter { $0.status != .done }.count) open · \(store.attentionCount) need attention"
                    )
                    .foregroundStyle(.secondary)
                }
                Spacer()
                TextField("Find a task", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                Toggle("Show completed", isOn: $includeDone).toggleStyle(.checkbox)
                Button {
                    editing = BoardTask(id: 0, title: "")
                } label: {
                    Label("New task", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }.padding(20)
            Divider()
            HSplitView {
                List(selection: $store.selectedTaskID) {
                    ForEach(TaskStatus.allCases) { status in
                        let tasks = visibleTasks.filter { $0.status == status }
                        if !tasks.isEmpty {
                            Section(status.label) {
                                ForEach(tasks) { task in
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(task.title).font(.headline).lineLimit(2)
                                        HStack {
                                            Text("#\(task.id)")
                                            Text(task.ownerSessionID.map(store.name(of:)) ?? "Unassigned")
                                            Spacer()
                                            if store.handoffs.contains(where: {
                                                $0.taskID == task.id && $0.status.isOpen
                                            }) {
                                                Image(systemName: "arrow.triangle.swap").help("Handoff in progress")
                                            }
                                        }.font(.caption).foregroundStyle(.secondary)
                                    }.padding(.vertical, 6).tag(task.id)
                                }
                            }
                        }
                    }
                }.frame(minWidth: 240, idealWidth: 300, maxWidth: 400)
                if let task = store.tasks.first(where: { $0.id == store.selectedTaskID }) {
                    TaskDetailView(task: task, edit: { editing = task })
                        .id(task.id).transition(.opacity)
                        .frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 40))
                            .foregroundStyle(.tint)
                        Text("One task. A clear next step.").font(.title2.bold())
                        Text("Select shared work to see context, handoffs, approvals, and evidence.")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                        if store.recruits.contains(where: { $0.status == .pending }) {
                            Button("Review session requests") { store.settings.showSidebar = true }
                        }
                    }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion), value: store.selectedTaskID)
        .sheet(item: $editing) { TaskEditorSheet(task: $0) }
    }
}
