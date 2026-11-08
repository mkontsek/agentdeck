import XCTest

final class InitialPromptTests: XCTestCase {
    @MainActor
    func testFreshPromptUsesLiteralArgumentsAndNeverReplaysOnResumeOrRestoration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        let prompt = "-draft ' \" $(printf WRONG) `printf WRONG` ž 🧑🏽‍💻"
        for profile in CLIProfile.builtins where profile.supportsMCP {
            var session = ManagedSession(name: "Initial fixture", kind: .cli)
            session.cliProfileID = profile.id
            session.initialPrompt = prompt
            session.resumeLastConversation = false
            store.addSession(session, start: false)
            let executable = profile.command.split(separator: " ").first!
            let stub = "\(executable)() { printf '%s\\0' \"$@\"; }; "
            let args = try Shell.run(["/bin/zsh", "-f", "-c", stub + store.launchCommand(for: session, resume: false)])
                .split(separator: "\0").map(String.init)
            XCTAssertEqual(args.last, prompt, profile.id)
            XCTAssertFalse(store.launchCommand(for: session, resume: true).contains("WRONG"))
            store.runtime[session.id]?.restoredLaunch = true
            XCTAssertFalse(store.launchCommand(for: session, resume: false).contains("WRONG"))
        }
        let custom = CLIProfile(id: "custom", name: "Custom", command: "custom --something")
        XCTAssertNil(custom.initialPromptTemplate)
        let optedIn = CLIProfile(id: "custom", name: "Custom", command: "custom --prompt {initialPrompt}")
        XCTAssertEqual(optedIn.initialPromptTemplate, optedIn.command)
    }
}
