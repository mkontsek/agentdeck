import AppKit
import SwiftUI

struct InspectorView: View {
    @EnvironmentObject var store: AppStore
    @State private var confirmRemove = false

    var body: some View {
        if let s = store.session(store.focusedSessionID) {
            inspector(for: s)
        } else {
            ContentUnavailableView("No session focused", systemImage: "sidebar.trailing",
                                   description: Text("Click a pane or pick a session in the sidebar."))
        }
    }

    private func bind<T>(_ s: ManagedSession, _ kp: WritableKeyPath<ManagedSession, T>) -> Binding<T> {
        Binding(get: { store.session(s.id)?[keyPath: kp] ?? s[keyPath: kp] },
                set: { v in if var n = store.session(s.id) { n[keyPath: kp] = v; store.updateSession(n) } })
    }

    @ViewBuilder
    private func inspector(for s: ManagedSession) -> some View {
        let rt = store.runtime[s.id] ?? SessionRuntime()
        Form {
            Section {
                TextField("Name", text: bind(s, \.name))
                LabeledContent("Kind", value: s.kind == .cli ? (store.profile(for: s)?.name ?? "CLI") : "Browser")
                LabeledContent("Status") {
                    HStack(spacing: 5) {
                        Circle().fill(rt.status.color).frame(width: 8, height: 8)
                        Text(rt.status.label)
                        Text("· \(relative(rt.statusSince))").foregroundStyle(.secondary)
                    }
                }
                if let q = rt.pendingQuestion { LabeledContent("Pending", value: q).foregroundStyle(.orange) }
                if let m = rt.programMessage, !m.isEmpty { LabeledContent("Program", value: m) }
                if let code = rt.exitCode { LabeledContent("Exit code", value: "\(code)") }
            }
            if s.kind == .cli {
                Section("Environment") {
                    LabeledContent("Directory") {
                        HStack {
                            Text(s.effectiveDirectory.abbreviatingHome).lineLimit(2).truncationMode(.head).textSelection(.enabled)
                            Button { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: s.effectiveDirectory.expandingTilde) } label: {
                                Image(systemName: "folder")
                            }.buttonStyle(.borderless)
                        }
                    }
                    if let b = s.worktreeBranch { LabeledContent("Worktree", value: b) }
                    LabeledContent("MCP URL") {
                        HStack {
                            Text(store.mcpURL(for: s.id)).font(.caption).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(store.mcpURL(for: s.id), forType: .string) } label: {
                                Image(systemName: "doc.on.doc")
                            }.buttonStyle(.borderless)
                        }
                    }
                    LabeledContent("Launch", value: store.launchCommand(for: s)).font(.caption)
                    if let t = rt.title, !t.isEmpty { LabeledContent("Title", value: t) }
                }
                Section("Capabilities") {
                    Text((store.profile(for: s)?.supportsMCP ?? false)
                         ? "MCP tools: whoami, list_sessions, read_board, create_task, update_task, handoff, send_message, log" + (s.isOrchestrator ? ", recruit_session, recruit_status" : "")
                         : "No MCP tools (plain shell). $AGENTDECK_MCP_URL is exported.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Orchestrator (may recruit sessions)", isOn: bind(s, \.isOrchestrator))
                    Toggle("Auto-inject status summaries", isOn: bind(s, \.autoInjectContext))
                    Toggle("Start at launch", isOn: bind(s, \.autoStart))
                }
                Section("Screen (last lines)") {
                    Text(rt.lastLines.suffix(6).joined(separator: "\n"))
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Section("Browser") {
                    TextField("Start URL", text: bind(s, \.url).unwrap(""))
                    LabeledContent("Profile", value: s.browserProfileID.uuidString.prefix(8) + "…").font(.caption)
                    if let t = rt.title, !t.isEmpty { LabeledContent("Title", value: t) }
                    Toggle("Start at launch", isOn: bind(s, \.autoStart))
                }
            }
            Section("Appearance") {
                if s.kind == .cli {
                    HStack {
                        Text("Font size")
                        Spacer()
                        Button { store.adjustFont(for: s.id, by: -1) } label: { Image(systemName: "minus") }
                        Text("\(Int(s.fontSizeOverride ?? store.settings.globalFontSize))").monospacedDigit().frame(width: 24)
                        Button { store.adjustFont(for: s.id, by: 1) } label: { Image(systemName: "plus") }
                        Button("Global") { store.resetFont(for: s.id) }.disabled(s.fontSizeOverride == nil)
                    }.buttonStyle(.bordered).controlSize(.small)
                }
                HStack {
                    Text("Pane size")
                    Spacer()
                    ForEach(PaneSizePreset.allCases) { p in Button(p.label) { store.setPaneSize(for: s.id, p.size) } }
                    Button("Reset") { store.setPaneSize(for: s.id, nil) }.disabled(s.paneSize == nil)
                }.buttonStyle(.bordered).controlSize(.small)
                if let ps = s.paneSize { Text("Custom: \(Int(ps.width)) × \(Int(ps.height)) (used on the Canvas)").font(.caption).foregroundStyle(.secondary) }
                if let p = s.canvasPosition { Text("Canvas position: \(Int(p.x)), \(Int(p.y))").font(.caption).foregroundStyle(.secondary) }
                if let m = rt.modelName { LabeledContent("Model", value: m) }
                if let c = rt.contextInfo { LabeledContent("Context", value: c) }
            }
            let mine = store.tasks.filter { $0.ownerSessionID == s.id }
            if !mine.isEmpty {
                Section("Tasks (\(mine.count))") {
                    ForEach(mine) { t in
                        HStack { Image(systemName: t.status.systemImage); Text("#\(t.id) \(t.title)").lineLimit(1) }
                            .foregroundStyle(t.status == .done ? .secondary : .primary)
                    }
                }
            }
            Section("Actions") {
                HStack {
                    if s.kind == .cli {
                        Button("Inject note…") { store.showInjectSheet = true }
                        Button("Context now") { store.injectContextNow(s.id) }
                    }
                    Button("Restart") { store.restartSession(s.id) }
                    Button("Stop") { store.stopSession(s.id) }
                }.controlSize(.small)
                Button("Remove session…", role: .destructive) { confirmRemove = true }.controlSize(.small)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Remove “\(s.name)”?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { store.removeSession(s.id) }
            if s.worktreePath != nil { Button("Remove and delete worktree", role: .destructive) { store.removeSession(s.id, deleteWorktree: true) } }
            if s.kind == .browser { Button("Remove and delete browser profile", role: .destructive) { store.removeSession(s.id, deleteBrowserProfile: true) } }
        }
    }

    private func relative(_ d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h"
    }
}

extension Binding where Value == String? {
    func unwrap(_ fallback: String) -> Binding<String> {
        Binding<String>(get: { wrappedValue ?? fallback }, set: { wrappedValue = $0 })
    }
}
