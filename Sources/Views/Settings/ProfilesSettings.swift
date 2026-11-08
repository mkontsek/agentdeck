import SwiftUI

struct ProfilesSettings: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedID: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(store.cliProfiles) { profile in
                            Button {
                                selectedID = profile.id
                            } label: {
                                Text(profile.name)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(
                                        selectedID == profile.id ? Color.accentColor.opacity(0.2) : .clear,
                                        in: RoundedRectangle(cornerRadius: 6)
                                    )
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("profile-select-\(profile.id)")
                        }
                    }.padding(8)
                }
                Divider()
                HStack {
                    Button(action: add) { Image(systemName: "plus") }.help("Add CLI profile")
                    Button(action: remove) { Image(systemName: "minus") }
                        .disabled(selectedID == nil).help("Remove selected profile")
                    Spacer()
                }.buttonStyle(.borderless).padding(10)
            }
            .frame(width: 180)
            Divider()
            Group {
                if let index = store.cliProfiles.firstIndex(where: { $0.id == selectedID }) {
                    CLIProfileEditor(profile: $store.cliProfiles[index]).id(store.cliProfiles[index].id)
                } else {
                    ContentUnavailableView("Select a profile", systemImage: "terminal")
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { selectExistingProfile() }
        .onChange(of: store.cliProfiles.map(\.id)) { _, _ in selectExistingProfile() }
    }

    private func selectExistingProfile() {
        if !store.cliProfiles.contains(where: { $0.id == selectedID }) {
            selectedID = store.cliProfiles.first?.id
        }
    }

    private func add() {
        var number = 1
        while store.cliProfiles.contains(where: { $0.id == "custom-\(number)" }) { number += 1 }
        let profile = CLIProfile(id: "custom-\(number)", name: "Custom CLI", command: "my-agent --mcp {mcpUrl}")
        store.cliProfiles.append(profile)
        selectedID = profile.id
    }

    private func remove() {
        store.cliProfiles.removeAll { $0.id == selectedID }
        selectedID = store.cliProfiles.first?.id
    }
}

private struct CLIProfileEditor: View {
    @Binding var profile: CLIProfile

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name").font(.headline)
                    TextField("Profile name", text: $profile.name).textFieldStyle(.roundedBorder)
                    Text("Identifier: \(profile.id)").font(.caption).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                editor("Command", text: $profile.command, height: 88)
                editor("Resume command", text: $profile.resumeCommand.unwrap(""), height: 88)
                Text("Leave Resume command empty to always start fresh. Commands run as zsh snippets.")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Command placeholders") {
                    Text(
                        "{mcpUrl}  {mcpConfigPath}  {briefingPath}  {sessionId}  {sessionName}  {cwd}\nResume also supports {conversationId}. Environment variables use the AGENTDECK_ prefix."
                    )
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                }
                Stepper(
                    "Submit delay: \(profile.submitDelayMs) ms", value: $profile.submitDelayMs, in: 0...2000, step: 50)
                Toggle("Speaks MCP (receives briefings and messages)", isOn: $profile.supportsMCP)
                editor("Notes", text: $profile.notes, height: 70)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityIdentifier("cli-profile-editor")
    }

    private func editor(_ title: String, text: Binding<String>, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            TextEditor(text: text).font(.system(.body, design: .monospaced))
                .multilineTextAlignment(.leading).frame(height: height)
                .padding(6).background(Color(nsColor: .textBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                .accessibilityLabel(title)
        }
    }
}
