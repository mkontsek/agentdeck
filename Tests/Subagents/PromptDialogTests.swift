import AppKit
import XCTest

final class PromptDialogTests: XCTestCase {
    @MainActor
    func testWorkerEventsCannotAcceptApprovalOrPasswordPrompts() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        for (index, prompt) in ["Password: ", "Approve action? [y/N] "].enumerated() {
            let output = directory.appendingPathComponent("accepted-\(index)")
            let command =
                "printf '%s' " + CommandTemplate.expand("{prompt}", values: ["prompt": prompt])
                + "; read -r fixture; printf 'UNEXPECTED_SUBMIT' > "
                + CommandTemplate.expand("{file}", values: ["file": output.path])
            store.cliProfiles.append(CLIProfile(id: "dialog-\(index)", name: "Dialog", command: command))
            var session = ManagedSession(name: "Dialog fixture", kind: .cli)
            session.cliProfileID = "dialog-\(index)"
            session.workingDirectory = directory.path
            store.addSession(session)
            for _ in 0..<500
            where !store.terminals.visibleLines(id: session.id).contains(where: {
                $0.contains(prompt.trimmingCharacters(in: .whitespaces))
            }) {
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertTrue(
                store.terminals.visibleLines(id: session.id).contains(where: {
                    $0.contains(prompt.trimmingCharacters(in: .whitespaces))
                }))
            for status in [SessionStatus.idle, .waitingForUser, .working] {
                store.runtime[session.id]?.status = status
                XCTAssertTrue(store.inject(session.id, text: "Worker result", source: "worker", queueIfBusy: true))
                store.statusTick()
            }
            try await Task.sleep(for: .milliseconds(350))
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        }
    }
}
