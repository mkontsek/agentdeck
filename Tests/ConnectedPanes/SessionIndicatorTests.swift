import AppKit
import SwiftUI
import XCTest

@MainActor
final class SessionIndicatorTests: XCTestCase {
    func testIdleRuntimeWithPendingApprovalMustDisplayAttentionInBothPlaces() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        let session = store.addSession(ManagedSession(name: "Status fixture", kind: .cli), start: false)
        store.runtime[session.id]?.status = .idle
        store.tasks = [
            BoardTask(id: 1, title: "Pending approval", ownerSessionID: session.id, status: .awaitingApproval)
        ]
        XCTAssertEqual(store.glassBallStatus(for: session), .attention)
        XCTAssertEqual(
            store.sessionDisplayStatus(for: session).color, Color.yellow,
            "The session dot must agree with the attention ball")
        var browser = ManagedSession(name: "Owned browser", kind: .browser)
        browser.agentOwnerID = session.id
        browser.paneID = session.paneID
        browser = store.addSession(browser, start: false, focus: false)
        store.runtime[browser.id]?.status = .working
        XCTAssertEqual(store.sessionDisplayStatus(for: browser), .attention)
        for state: TaskStatus in [.blocked, .review, .awaitingApproval] {
            store.tasks[0].status = state
            XCTAssertEqual(store.sessionDisplayStatus(for: session), .attention)
        }
        store.tasks[0].status = .done
        XCTAssertEqual(store.sessionDisplayStatus(for: session), .finished)
        store.runtime[session.id]?.status = .working
        XCTAssertEqual(store.sessionDisplayStatus(for: session), .working)
        XCTAssertEqual(store.sessionDisplayStatus(for: browser), .working)
        for state: SessionStatus in [.waitingForUser, .error, .stalled, .quotaWarning] {
            store.runtime[session.id]?.status = state
            XCTAssertEqual(store.sessionDisplayStatus(for: session), .attention)
        }
        store.tasks = []
        store.runtime[session.id]?.status = .idle
        XCTAssertEqual(store.sessionDisplayStatus(for: session), .idle)
        XCTAssertEqual(store.sessionDisplayStatus(for: browser), .idle)
        XCTAssertEqual(store.status(of: browser.id), .working, "Presentation does not rewrite runtime state")
    }

    func testNativeStatusRowsMatchBallsInBothThemes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        let states: [GlassBallStatus] = [.attention, .working, .finished, .idle]
        for (index, state) in states.enumerated() {
            let session = store.addSession(ManagedSession(name: state.label, kind: .cli), start: false)
            store.runtime[session.id]?.status = state == .working ? .working : .idle
            if state == .attention || state == .finished {
                store.tasks.append(
                    BoardTask(
                        id: index + 1, title: "Fixture", ownerSessionID: session.id,
                        status: state == .attention ? .awaitingApproval : .done))
            }
        }
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 440, height: 460),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(
            rootView: VStack(spacing: 8) {
                ForEach(store.sessions) { session in
                    HStack {
                        SessionRow(session: session).frame(width: 260)
                        GlassBallView(
                            name: session.name, status: store.glassBallStatus(for: session),
                            reduceMotion: true, onOpen: {})
                    }
                }
            }.padding().background(Color(nsColor: .windowBackgroundColor)).environmentObject(store))
        window.contentView = host
        window.orderFront(nil)
        defer {
            store.shutdown()
            window.close()
            try? FileManager.default.removeItem(at: directory)
        }
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            window.appearance = NSAppearance(named: appearance)
            try await Task.sleep(for: .milliseconds(100))
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
                to: URL(fileURLWithPath: "/tmp/agentdeck-status-\(name).png"))
        }
    }
}
