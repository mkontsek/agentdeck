import AppKit
import SwiftUI

struct NewSessionSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var kind: SessionKind = .cli
    @State private var name = ""
    @State private var profileID = "claude"
    @State private var directory = NSHomeDirectory()
    @State private var useWorktree = false
    @State private var initialPrompt = ""
    @State private var orchestrator = false
    @State private var autoInject = true
    @State private var preset: BrowserPreset = .chatgpt
    @State private var url = BrowserPreset.chatgpt.url
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Session").font(.title3).bold()
            Picker("", selection: $kind) {
                ForEach(SessionKind.allCases) { Label($0.label, systemImage: $0.systemImage).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            Form {
                TextField("Name", text: $name, prompt: Text(defaultName))
                if kind == .cli {
                    Picker("CLI", selection: $profileID) {
                        ForEach(store.cliProfiles) { Text($0.name).tag($0.id) }
                    }
                    if let p = store.cliProfiles.first(where: { $0.id == profileID }), !p.notes.isEmpty {
                        Text(p.notes).font(.caption).foregroundStyle(.secondary)
                    }
                    LabeledContent("Directory") {
                        HStack {
                            TextField("", text: $directory).labelsHidden()
                            Button("Choose…") { chooseDirectory() }
                        }
                    }
                    Toggle("Isolated git worktree (branch agentdeck/<name>)", isOn: $useWorktree)
                        .disabled(Worktree.repoRoot(of: directory) == nil)
                    LabeledContent("First prompt") {
                        TextEditor(text: $initialPrompt).font(.body).frame(height: 60)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3)))
                    }
                    Toggle("Orchestrator (can recruit sessions with your approval)", isOn: $orchestrator)
                    Toggle("Auto-inject status summaries", isOn: $autoInject)
                } else {
                    Picker("Site", selection: $preset) { ForEach(BrowserPreset.allCases) { Text($0.label).tag($0) } }
                        .onChange(of: preset) { _, p in if p != .custom { url = p.url } }
                    TextField("URL", text: $url)
                    Text("Each browser session gets its own cookie/storage profile, so logins never collide.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create") { create() }.keyboardShortcut(.defaultAction).disabled(working)
            }
        }
        .padding(20).frame(width: 540)
    }

    private var defaultName: String {
        kind == .cli ? "\(store.cliProfiles.first { $0.id == profileID }?.name ?? "CLI") \(store.sessions.count + 1)" : preset.label
    }

    private func chooseDirectory() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.directoryURL = URL(fileURLWithPath: directory.expandingTilde)
        if p.runModal() == .OK, let u = p.url { directory = u.path }
    }

    private func create() {
        working = true
        var s = ManagedSession(name: name.trimmingCharacters(in: .whitespaces).isEmpty ? defaultName : name, kind: kind)
        if kind == .cli {
            s.cliProfileID = profileID
            s.workingDirectory = directory.expandingTilde
            s.initialPrompt = initialPrompt.isEmpty ? nil : initialPrompt
            s.isOrchestrator = orchestrator
            s.autoInjectContext = autoInject
            if useWorktree {
                do {
                    let wt = try Worktree.create(repoDir: s.workingDirectory, slug: s.name.slug, root: store.settings.worktreeRoot)
                    s.worktreePath = wt.path; s.worktreeBranch = wt.branch; s.worktreeRepo = wt.repo
                    store.addLog(source: "app", message: "worktree \(wt.branch) at \(wt.path.abbreviatingHome)")
                } catch {
                    store.lastError = "Worktree creation failed: \(error.localizedDescription)"
                    working = false
                    return
                }
            }
        } else {
            s.url = url
        }
        store.addSession(s)
        dismiss()
    }
}

struct InjectSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var submit = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Inject note into “\(store.session(store.focusedSessionID)?.name ?? "")”").font(.title3).bold()
            Text("Typed into the session exactly as if you wrote it. Newlines are collapsed to one line.")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $text).font(.body).frame(height: 110)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3)))
            Toggle("Press Enter after typing", isOn: $submit)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Inject") {
                    if let id = store.focusedSessionID { _ = store.inject(id, text: text, submit: submit) }
                    dismiss()
                }.keyboardShortcut(.defaultAction).disabled(text.singleLine.isEmpty)
            }
        }
        .padding(20).frame(width: 520)
    }
}
