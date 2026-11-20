import SwiftUI

struct RenameSessionSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool
    let session: ManagedSession
    @State private var name: String

    init(session: ManagedSession) {
        self.session = session
        _name = State(initialValue: session.name)
    }

    private var sessionExists: Bool { store.session(session.id) != nil }
    private var canRename: Bool {
        sessionExists && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename mini-window").font(.title2.bold())
            Text("Change the selected tab’s name in the window header and sidebar.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .accessibilityIdentifier("rename-session-name")
                .onSubmit(rename)
            if !sessionExists {
                Text("This session has been removed.").foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename", action: rename)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canRename)
                    .accessibilityIdentifier("rename-session-save")
            }
        }
        .padding(24)
        .frame(width: 380)
        .onAppear { nameFocused = true }
    }

    private func rename() {
        guard canRename, store.renameSession(session.id, to: name) else { return }
        dismiss()
    }
}
