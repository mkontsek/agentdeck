import AppKit
import SwiftUI
import XCTest

@MainActor
final class GlassBallDockRenderingTests: XCTestCase {
    func testNativeRoutesRemainVisibleAndStationaryAcrossShapesInBothThemes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        store.settings.layoutMode = .canvas
        store.settings.glassBallSubagents = true
        var parent = ManagedSession(name: "Parent fixture", kind: .cli)
        parent.paneSize = PaneSize(width: 180, height: 160)
        parent = store.addSession(parent, start: false)
        var child = ManagedSession(name: "Worker fixture", kind: .cli)
        child.parentSessionID = parent.id
        child.canvasPosition = PanePoint(x: 360, y: 250)
        child.paneSize = PaneSize(width: 320, height: 240)
        child = store.addSession(child, start: false, focus: false)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1100, height: 800),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: PaneGridView().environmentObject(store).preferredColorScheme(.dark))
        window.contentView = host
        window.orderFrontRegardless()
        defer {
            store.shutdown()
            window.close()
            try? FileManager.default.removeItem(at: directory)
        }
        for (side, position) in [
            (GlassBallDock.left, PanePoint(x: 20, y: 270)),
            (.right, PanePoint(x: 820, y: 270)),
            (.top, PanePoint(x: 390, y: 10)),
            (.bottom, PanePoint(x: 390, y: 600)),
        ] {
            store.setCanvasPosition(for: parent.id, position)
            for dark in [false, true] {
                store.focusSession(parent.id)
                store.runtime[child.id]?.status = dark ? .waitingForUser : .working
                host.rootView = PaneGridView().environmentObject(store).preferredColorScheme(dark ? .dark : .light)
                try await Task.sleep(for: .milliseconds(600))
                let size = store.canvasViewport
                let frames = store.paneFrames(in: size)
                let docks = store.glassBallDocks(in: frames)
                XCTAssertEqual(docks[child.paneID], side)
                let route = try XCTUnwrap(
                    PaneRouteCache().paths(
                        connections: store.paneConnections,
                        frames: frames, docks: docks,
                        bounds: CGRect(x: 2, y: 2, width: size.width - 4, height: size.height - 4))[child.paneID])
                let endpoint = try XCTUnwrap(route.last)
                let sphere = side.sphereFrame(in: try XCTUnwrap(frames[child.paneID]))
                XCTAssertEqual(hypot(endpoint.x - sphere.midX, endpoint.y - sphere.midY), 32, accuracy: 0.001)
                let name = "\(side)-\(dark ? "dark" : "light")"
                try capture(host, route: route, name: "\(name)-collapsed")
                store.focusSession(child.id)
                let started = ProcessInfo.processInfo.systemUptime
                for (index, delay) in [10, 85, 120, 300].enumerated() {
                    try await Task.sleep(for: .milliseconds(delay))
                    print(
                        "SPHERE_FRAME \(name)-open-\(index) elapsed=\(ProcessInfo.processInfo.systemUptime - started)")
                    try capture(host, route: route, name: "\(name)-open-\(index)")
                }
                store.focusSession(parent.id)
                try await Task.sleep(for: .milliseconds(180))
                try capture(host, route: route, name: "\(name)-closing")
                store.focusSession(child.id)
                try await Task.sleep(for: .milliseconds(40))
                store.focusSession(parent.id)
                try await Task.sleep(for: .milliseconds(600))
                try capture(host, route: route, name: "\(name)-reversed")
            }
        }
        let observer = try XCTUnwrap(descendants(host).compactMap { $0 as? CanvasScrollObservationView }.first)
        let scroll = try XCTUnwrap(observer.enclosingScrollView)
        scroll.allowsMagnification = true
        for zoom: CGFloat in [0.75, 1.25, 1.75] {
            scroll.magnification = zoom
            scroll.contentView.scroll(to: CGPoint(x: 160, y: 100))
            scroll.reflectScrolledClipView(scroll.contentView)
            try await Task.sleep(for: .milliseconds(150))
            let frames = store.paneFrames(in: store.canvasViewport)
            let bounds = try XCTUnwrap(scroll.documentView?.bounds)
            let routes = PaneRouteCache().paths(
                connections: store.paneConnections, frames: frames,
                docks: store.glassBallDocks(in: frames), bounds: bounds.insetBy(dx: 2, dy: 2))
            try capture(host, route: XCTUnwrap(routes[child.paneID]), name: "zoom-\(zoom)")
        }
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    private func capture(_ host: NSView, route: [CGPoint], name: String) throws {
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
        // Every old route segment must still be drawn, including both bends and the arriving tip.
        var samples: [CGPoint] = []
        for (a, b) in zip(route, route.dropFirst()) where hypot(a.x - b.x, a.y - b.y) > 16 {
            for fraction: CGFloat in [0.2, 0.5, 0.8] {
                samples.append(CGPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction))
            }
        }
        if let end = route.last, route.count >= 2 {
            let previous = route[route.count - 2]
            let length = hypot(end.x - previous.x, end.y - previous.y)
            samples.append(
                CGPoint(
                    x: end.x + (previous.x - end.x) * 2 / length,
                    y: end.y + (previous.y - end.y) * 2 / length))
        }
        let document = descendants(host).compactMap { $0 as? CanvasScrollObservationView }.first?.enclosingScrollView?
            .documentView
        var visibleSamples = 0
        for canvasPoint in samples {
            let point = host.convert(canvasPoint, from: document)
            guard host.bounds.insetBy(dx: 2, dy: 2).contains(point) else { continue }
            visibleSamples += 1
            var orange = false
            for dx in -1...1 {
                for dy in -1...1 {
                    if let color = bitmap.colorAt(x: Int(point.x * scale) + dx, y: Int(point.y * scale) + dy)?
                        .usingColorSpace(.sRGB)
                    {
                        orange = orange || color.redComponent - color.blueComponent > 0.15
                    }
                }
            }
            XCTAssertTrue(orange, "\(name): route must remain at canvas coordinate \(point)")
        }
        XCTAssertGreaterThan(visibleSamples, 1)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let directory = URL(fileURLWithPath: "/tmp/agentdeck-sphere-anchors", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("\(name).png"))
    }
}
