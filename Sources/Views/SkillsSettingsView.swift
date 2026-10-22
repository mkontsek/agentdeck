import AppKit
import SwiftUI

struct SkillsSettingsView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        SkillsLibraryView(library: store.skillLibrary)
    }
}

private struct SkillsLibraryView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var library: SkillLibrary
    @State private var selected: LoadedSkill?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Skill directories").font(.headline)
                Spacer()
                Button("Add folder…", action: addDirectory)
                Button("Reload") { store.reloadSkills() }.disabled(library.isLoading)
            }
            ForEach(store.settings.skillDirectories, id: \.self) { directory in
                HStack {
                    Image(systemName: "folder")
                    Text(directory).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Spacer()
                    Button {
                        store.settings.skillDirectories.removeAll { $0 == directory }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless).help("Remove skill directory")
                }
            }
            Text(
                "Choose a skills folder or a repository containing .agents/skills. Enabled skills are shared with CLI agents; copy a skill to use it in a browser chat."
            )
            .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("\(library.enabledSkills.count) of \(library.skills.count) skills enabled").font(.headline)
                if library.isLoading { ProgressView().controlSize(.small) }
            }
            List(library.skills) { skill in
                HStack(alignment: .top) {
                    Toggle(
                        "Enable \(skill.name)",
                        isOn: Binding(
                            get: { !store.settings.disabledSkillIDs.contains(skill.id) },
                            set: { enabled in
                                var disabled = store.settings.disabledSkillIDs.filter { $0 != skill.id }
                                if !enabled { disabled.append(skill.id) }
                                store.settings.disabledSkillIDs = disabled
                            })
                    )
                    .labelsHidden()
                    VStack(alignment: .leading, spacing: 3) {
                        Text(skill.name).fontWeight(.medium)
                        Text(skill.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        Text(skill.path.abbreviatingHome).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                    }
                    Spacer()
                    Button("View") { selected = skill }
                }.padding(.vertical, 3)
            }
            if let warning = library.warnings.first {
                Text(warning).font(.caption).foregroundStyle(.orange).lineLimit(2).help(
                    library.warnings.joined(separator: "\n"))
            }
        }
        .padding(16)
        .onAppear { store.reloadSkills() }
        .sheet(item: $selected) { skill in
            VStack(alignment: .leading, spacing: 12) {
                Text(skill.name).font(.title2).bold()
                ScrollView {
                    Text(skill.markdown).font(.system(.body, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Button("Open file") { NSWorkspace.shared.open(URL(fileURLWithPath: skill.path)) }
                    Button("Copy for browser") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(skill.markdown, forType: .string)
                    }
                    Spacer()
                    Button("Use in focused CLI") {
                        if let id = store.focusedSessionID {
                            _ = store.inject(
                                id,
                                text:
                                    "Use the skill \(skill.name). Read its instructions at \(skill.path) before proceeding.",
                                queueIfBusy: true)
                        }
                        selected = nil
                    }
                    .disabled(
                        store.session(store.focusedSessionID)?.kind != .cli
                            || store.runtime[store.focusedSessionID ?? UUID()]?.isRunning != true
                            || store.settings.disabledSkillIDs.contains(skill.id))
                    Button("Done") { selected = nil }.keyboardShortcut(.defaultAction)
                }
            }.padding(20).frame(width: 720, height: 540)
        }
    }

    private func addDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Load skills"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            let path = url.standardizedFileURL.path
            if !store.settings.skillDirectories.contains(where: { $0.expandingTilde == path }) {
                store.settings.skillDirectories.append(path)
            }
        }
    }
}
