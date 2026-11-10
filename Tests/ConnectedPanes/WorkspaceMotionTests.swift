import AppKit
import SwiftUI
import XCTest

@MainActor
final class WorkspaceMotionTests: XCTestCase {
    func testRetainedTransitionHasIntermediateFramesAndSurvivesReversal() async throws {
        let fixture = MotionFixtureState()
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 700, height: 460), styleMask: [.titled], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: MotionFixtureView(fixture: fixture))
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(150))
        let view = try XCTUnwrap(fixture.nativeView)
        let originalSize = view.bounds.size
        let initial = try capture(host, name: "expanded")
        fixture.collapsed = true
        try await Task.sleep(for: .milliseconds(45))
        XCTAssertFalse(view.isHidden, "Closing content stays attached and visible while its layer animates")
        let intermediate = try capture(host, name: "closing")
        XCTAssertNotEqual(initial, intermediate, "Capture a real intermediate animation frame")
        XCTAssertEqual(view.bounds.size, originalSize, "No per-frame native terminal reflow")
        fixture.collapsed = false
        try await Task.sleep(for: .milliseconds(35))
        fixture.collapsed = true
        try await Task.sleep(for: .milliseconds(35))
        fixture.collapsed = false
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertFalse(view.isHidden, "A stale completion must not hide the last expanded state")
        XCTAssertTrue(fixture.nativeView === view)
        XCTAssertEqual(view.bounds.size, originalSize)
        fixture.collapsed = true
        for _ in 0..<200 where !view.isHidden { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(view.isHidden, "The completed collapse releases display work")
        let collapsed = try capture(host, name: "collapsed")
        XCTAssertNotEqual(intermediate, collapsed)
        fixture.reduceMotion = true
        fixture.collapsed = false
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertFalse(view.isHidden)
        fixture.collapsed = true
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertTrue(view.isHidden, "Reduce Motion settles without a spring or completion delay")
        window.contentView = nil
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(fixture.nativeView === view, "Detaching presentation does not replace the resource owner")
    }

    private func capture(_ view: NSView, name: String) throws -> Data {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: "/tmp/agentdeck-glass-motion-\(name).png"))
        return data
    }
}

@MainActor
private final class MotionFixtureState: ObservableObject {
    @Published var collapsed = false
    @Published var reduceMotion = false
    var nativeView: NSView?
}

private struct MotionFixtureView: View {
    @ObservedObject var fixture: MotionFixtureState
    var body: some View {
        GlassBallTransitionView(
            collapsed: fixture.collapsed, size: CGSize(width: 640, height: 400), reduceMotion: fixture.reduceMotion
        ) {
            MotionNativeFixture(fixture: fixture).frame(width: 640, height: 400).background(.blue)
        } ball: {
            GlassBallView(name: "Motion fixture", status: .attention, reduceMotion: fixture.reduceMotion, onOpen: {})
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20).background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct MotionNativeFixture: NSViewRepresentable {
    @Environment(\.isGlassBallCollapsed) private var hidden
    let fixture: MotionFixtureState
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.systemBlue.cgColor
        fixture.nativeView = view
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { view.isHidden = hidden }
}
