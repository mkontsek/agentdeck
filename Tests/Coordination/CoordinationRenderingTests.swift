import AppKit
import SwiftUI
import XCTest

final class CoordinationRenderingTests: XCTestCase {
    @MainActor
    func testAnimatedLayoutsKeepNativeTerminalAttachedAndHiddenWorkspaceUnfocused() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        let profile = CLIProfile(id: "motion-test", name: "Local test", command: "exec /bin/cat", supportsMCP: false)
        store.cliProfiles.append(profile)
        var session = ManagedSession(name: "Local PTY", kind: .cli)
        session.cliProfileID = profile.id
        session.workingDirectory = directory.path
        session.resumeLastConversation = false
        session = store.addSession(session)
        store.settings.workspaceMode = .sessions
        store.settings.showUsagePanel = false
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700), styleMask: [.titled, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ContentView().environmentObject(store))
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.close()
        }
        try await Task.sleep(for: .milliseconds(350))
        let terminal = try XCTUnwrap(store.terminals.view(for: session.id))
        let container = try XCTUnwrap(terminal.superview)
        store.settings.layoutMode = .grid
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(terminal.superview === container)
        store.maximizedSessionID = session.id
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(terminal.superview === container)
        store.settings.workspaceMode = .board
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(terminal.superview === container)
        XCTAssertFalse(window.firstResponder === terminal)
        store.settings.workspaceMode = .sessions
        store.maximizedSessionID = nil
        store.settings.layoutMode = .canvas
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(terminal.superview === container)
        XCTAssertTrue(store.terminals.view(for: session.id) === terminal)
    }

    @MainActor
    func testBoardAndUsagePanelRenderWithIsolatedFixtures() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let monitor = CLIUsageMonitor { id in
            CLIUsageSnapshot(
                providerID: id,
                windows: [
                    UsageWindow(
                        id: "weekly", label: "7 days", usedPercent: 38,
                        resetsAt: Date().addingTimeInterval(86_400))
                ],
                observedAt: Date(), source: "Test fixture")
        }
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"), usageMonitor: monitor)
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        var implementer = ManagedSession(name: "Codex · implementation", kind: .cli)
        implementer.cliProfileID = "codex"
        implementer = store.addSession(implementer, start: false)
        var reviewer = ManagedSession(name: "Claude · review", kind: .cli)
        reviewer.cliProfileID = "claude"
        reviewer = store.addSession(reviewer, start: false)
        let task = store.createTask(
            title: "Review the sign-in fix",
            description: "Keep existing sessions intact while validating the updated callback.",
            owner: implementer.id,
            notes: "Focused authentication checks pass. The review should cover cancellation and expired credentials.")
        _ = try store.handoff(
            from: implementer.id, to: reviewer, taskID: task.id, title: nil, description: nil,
            note: "The fix is ready for review.", artifacts: ["Sources/Auth/Callback.swift"],
            verification: "12 authentication checks passed.",
            nextAction: "Review the diff and request completion approval.")
        store.openTask(task.id)
        store.settings.usagePanelPosition = PanePoint(x: 930, y: 60)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900), styleMask: [.titled, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: ContentView().environmentObject(store))
        window.contentView = hosting
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.close()
        }
        try await Task.sleep(for: .milliseconds(400))
        hosting.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(hosting.bounds.width, 0)
        let output = URL(fileURLWithPath: "/tmp/agentdeck-coordination-preview.png")
        if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            if let png = bitmap.representation(using: .png, properties: [:]) { try png.write(to: output) }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertEqual(store.handoffs.first?.status, .awaitingApproval)
    }
}
