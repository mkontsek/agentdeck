import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            List(
                selection: Binding(
                    get: { store.focusedSessionID },
                    set: { id in
                        if let id { store.selectSidebarSession(id) } else { store.focusedSessionID = nil }
                    })
            ) {
                Section("Sessions") {
                    ForEach(store.sessions) { s in
                        SessionRow(session: s)
                            .tag(s.id)
                            .contextMenu { sessionMenu(s) }
                    }
                }
                let pending = store.recruits.filter { $0.status == .pending }
                if !pending.isEmpty {
                    Section("Approval needed") {
                        ForEach(pending) { r in RecruitRow(request: r) }
                    }
                }
            }
            .listStyle(.sidebar)
            .onKeyPress(.return) {
                guard let id = store.focusedSessionID else { return .ignored }
                store.focusSession(id)
                return .handled
            }
            .accessibilityHint("Use Up and Down to select a session; Return focuses its terminal or browser.")
            .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion), value: store.sessions.map(\.id))
            .animation(
                WorkspaceMotion.animation(reduceMotion: reduceMotion),
                value: store.recruits.filter { $0.status == .pending }.map(\.id))
            Divider()
            CanvasMiniMapView(overview: store.canvasOverview)
            Divider()
            HStack(spacing: 6) {
                Circle().fill(store.mcpStatus.hasPrefix("listening") ? Color.green : Color.red).frame(
                    width: 7, height: 7)
                Text("MCP " + (store.mcpStatus.hasPrefix("listening") ? ":\(store.settings.mcpPort)" : store.mcpStatus))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button {
                    store.showNewSession = true
                } label: {
                    Image(systemName: "plus")
                }.buttonStyle(.borderless)
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private func sessionMenu(_ s: ManagedSession) -> some View {
        Button("Restart") { store.restartSession(s.id) }
        Button("Stop") { store.stopSession(s.id) }
        if s.kind == .cli {
            if s.delegatedTaskID != nil {
                Button("Promote to Main Conversation") { store.promoteToMainConversation(s.id) }
                    .help("Preserves tasks and history. Restart the session afterward to reload its role and tools.")
            }
            Button("New CLI Tab") { store.addCLITab(to: s.id) }
                .disabled(store.cliTabSource(for: s.id) == nil)
            Button("Inject Note…") {
                store.selectTab(s.id)
                store.showInjectSheet = true
            }
            Button("Inject Context Now") { store.injectContextNow(s.id) }
        }
        Button(store.maximizedSessionID == s.id ? "Restore Panes" : "Maximize") {
            store.maximizedSessionID = store.maximizedSessionID == s.id ? nil : s.id
        }
        Toggle(
            "Orchestrator",
            isOn: Binding(
                get: { s.isOrchestrator },
                set: { v in
                    var n = s
                    n.isOrchestrator = v
                    store.updateSession(n)
                }))
        Divider()
        Button("Remove", role: .destructive) { store.removeSession(s.id) }
        if s.worktreePath != nil {
            Button("Remove + Delete Worktree", role: .destructive) { store.removeSession(s.id, deleteWorktree: true) }
        }
        if s.kind == .browser, s.browserProfileMode == .isolated {
            Button("Remove + Delete Browser Profile", role: .destructive) {
                store.removeSession(s.id, deleteBrowserProfile: true)
            }
        }
    }
}

struct SessionRow: View {
    @EnvironmentObject var store: AppStore
    let session: ManagedSession

    var body: some View {
        let st = store.status(of: session.id)
        let display = store.sessionDisplayStatus(for: session)
        HStack(spacing: 8) {
            SessionStatusIndicator(status: display, diameter: 9)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(session.name).fontWeight(.medium).lineLimit(1)
                    if session.isOrchestrator {
                        Image(systemName: "crown.fill").font(.caption2).foregroundStyle(.yellow)
                    }
                }
                HStack(spacing: 4) {
                    Image(systemName: session.kind.systemImage).font(.caption2)
                    Text(display.label).font(.caption)
                    if let q = store.runtime[session.id]?.pendingQuestion, st == .waitingForUser {
                        Text("· \(q)").font(.caption).lineLimit(1)
                    }
                }.foregroundStyle(.secondary)
            }
            Spacer()
            let open = store.tasks.filter { $0.ownerSessionID == session.id && $0.status != .done }.count
            if open > 0 {
                Text("\(open)").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor.opacity(0.2)))
            }
        }
        .padding(.vertical, 2)
    }
}

struct RecruitRow: View {
    @EnvironmentObject var store: AppStore
    let request: RecruitRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(request.requestedByName) wants “\(request.name)”").fontWeight(.medium)
            Text(
                "\(request.kind.label)\(request.kind == .cli ? " · \(request.cliProfileID) · \(request.workingDirectory.abbreviatingHome)" : "")\(request.useWorktree ? " · worktree" : "")"
            )
            .font(.caption).foregroundStyle(.secondary)
            if !request.reason.isEmpty { Text(request.reason).font(.caption).lineLimit(3) }
            HStack {
                Button("Approve") { store.approveRecruit(request.id) }.buttonStyle(.borderedProminent).controlSize(
                    .small)
                Button("Deny") { store.denyRecruit(request.id) }.controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
