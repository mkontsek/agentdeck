import AppKit
import XCTest

final class AppStoreTests: XCTestCase {
    @MainActor
    private func withStore(_ operation: (AppStore, URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("state.json")
        let store = AppStore(stateURL: url)
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        try await operation(store, url)
    }

    @MainActor
    func testPersistenceRoundTripAndCorruptionPreservation() async throws {
        try await withStore { store, url in
            let session = store.addSession(ManagedSession(name: "Review", kind: .cli), start: false)
            store.createTask(title: "Test", owner: session.id)
            store.saveNow()
            let loaded = AppStore(stateURL: url)
            XCTAssertEqual(loaded.sessions.map(\.id), [session.id])
            XCTAssertEqual(loaded.tasks.first?.ownerSessionID, session.id)
            XCTAssertEqual(loaded.nextTaskID, 2)
            loaded.shutdown()
            let corrupt = Data("{broken".utf8)
            try corrupt.write(to: url)
            let damaged = AppStore(stateURL: url)
            XCTAssertNotNil(damaged.lastError)
            damaged.shutdown()
            XCTAssertEqual(try Data(contentsOf: url), corrupt)
        }
    }

    @MainActor
    func testInvalidPortAndStoppedInjection() async throws {
        try await withStore { store, _ in
            for port in [-1, 0, 65536, Int.max] {
                store.settings.mcpPort = port
                store.startMCP()
                XCTAssertTrue(store.mcpStatus.hasPrefix("failed"))
            }
            let session = store.addSession(ManagedSession(name: "Stopped", kind: .cli), start: false)
            XCTAssertFalse(store.inject(session.id, text: "hello", queueIfBusy: true))
            XCTAssertNil(store.resolveSession(""))
        }
    }

    @MainActor
    func testRecruitWorktreeFailureDoesNotLaunchFallback() async throws {
        try await withStore { store, url in
            let request = RecruitRequest(
                requestedBy: nil, requestedByName: "Test", kind: .cli, name: "Tests", cliProfileID: "shell",
                workingDirectory: url.deletingLastPathComponent().path, useWorktree: true, reason: "regression")
            store.recruits.append(request)
            await store.approveRecruitAsync(request.id)
            XCTAssertTrue(store.sessions.isEmpty)
            XCTAssertEqual(store.recruits.first?.status, .pending)
            XCTAssertNotNil(store.lastError)
        }
    }

    @MainActor
    func testMCPValidationAndBoardWorkflow() async throws {
        try await withStore { store, _ in
            let session = store.addSession(ManagedSession(name: "Agent", kind: .cli), start: false)
            let path = "/mcp/\(session.id.uuidString)"
            @MainActor func rpc(_ request: [String: Any]) async throws -> (status: Int, body: Data, contentType: String)
            {
                await store.handleHTTP(
                    method: "POST", path: path, body: try JSONSerialization.data(withJSONObject: request))
            }
            let missingVersion = try await rpc(["method": "ping", "id": 1]).status
            XCTAssertEqual(missingVersion, 400)
            let booleanID = try await rpc(["jsonrpc": "2.0", "method": "ping", "id": true]).status
            XCTAssertEqual(booleanID, 400)
            let notification = try await rpc(["jsonrpc": "2.0", "method": "notifications/initialized"]).status
            XCTAssertEqual(notification, 202)
            let nullID = try await rpc(["jsonrpc": "2.0", "method": "ping", "id": NSNull()]).status
            XCTAssertEqual(nullID, 200)
            let unknownSession = await store.handleHTTP(method: "POST", path: "/mcp/\(UUID())", body: Data()).status
            XCTAssertEqual(unknownSession, 404)
            XCTAssertTrue(store.callTool(name: "create_task", args: ["title": "unauthorized"], caller: nil).isError)
            XCTAssertTrue(
                store.callTool(name: "create_task", args: ["title": "bad", "status": "invalid"], caller: session.id)
                    .isError)
            XCTAssertFalse(
                store.callTool(name: "create_task", args: ["title": "Fix", "owner": "me"], caller: session.id).isError)
            XCTAssertEqual(store.tasks.first?.ownerSessionID, session.id)
            XCTAssertFalse(
                store.callTool(name: "update_task", args: ["task_id": 1, "status": "done"], caller: session.id).isError)
            XCTAssertEqual(store.tasks.first?.status, .done)
            XCTAssertTrue(store.callTool(name: "recruit_session", args: ["name": "Other"], caller: session.id).isError)
        }
    }
}
