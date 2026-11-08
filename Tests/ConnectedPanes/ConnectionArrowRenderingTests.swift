import AppKit
import SwiftUI
import XCTest

@MainActor
final class ConnectionArrowRenderingTests: XCTestCase {
    func testRoutedArrowsRenderBesideWindowBordersInBothThemes() async throws {
        let source = ManagedSession(name: "Parent", kind: .cli)
        let target = ManagedSession(name: "Worker", kind: .cli)
        let obstacle = UUID()
        let frames = [
            source.paneID: CGRect(x: 20, y: 60, width: 180, height: 180),
            target.paneID: CGRect(x: 650, y: 280, width: 180, height: 180),
            obstacle: CGRect(x: 280, y: 80, width: 250, height: 350),
        ]
        let connection = PaneConnection(source: source, target: target, kind: .subagent)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 880, height: 560),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        for dark in [false, true] {
            let host = NSHostingView(
                rootView: ZStack(alignment: .topLeading) {
                    (dark ? Color.black : Color.white)
                    ForEach(Array(frames.keys), id: \.self) { id in
                        if let frame = frames[id] {
                            RoundedRectangle(cornerRadius: 8).fill(dark ? Color(white: 0.15) : Color(white: 0.93))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.blue, lineWidth: 2))
                                .frame(width: frame.width, height: frame.height).offset(x: frame.minX, y: frame.minY)
                        }
                    }
                    PaneConnectionsView(connections: [connection], frames: frames)
                }.frame(width: 880, height: 560).environment(\.colorScheme, dark ? .dark : .light))
            window.contentView = host
            window.orderFrontRegardless()
            try await Task.sleep(for: .milliseconds(100))
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let points = try XCTUnwrap(
                PaneRouteCache().paths(
                    connections: [connection], frames: frames,
                    bounds: CGRect(x: 2, y: 2, width: 876, height: 556))[target.paneID])
            let scale = Double(bitmap.pixelsWide) / host.bounds.width
            for (a, b) in zip(points, points.dropFirst()) where hypot(a.x - b.x, a.y - b.y) > 12 {
                let p = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                let pixel = try XCTUnwrap(
                    bitmap.colorAt(x: Int(p.x * scale), y: Int(p.y * scale))?.usingColorSpace(.sRGB))
                XCTAssertGreaterThan(
                    pixel.redComponent - pixel.blueComponent, 0.12, "A routed segment must remain visible")
            }
            // This fixture routes below the blocker. Verify actual clear pixels between its border and the arrow.
            let gapPixel = try XCTUnwrap(
                bitmap.colorAt(x: Int(405 * scale), y: Int(436 * scale))?.usingColorSpace(.sRGB))
            for component in [gapPixel.redComponent, gapPixel.greenComponent, gapPixel.blueComponent] {
                XCTAssertEqual(
                    component, dark ? 0 : 1, accuracy: 0.03, "The gutter must remain visible in the native canvas")
            }
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: "/tmp/agentdeck-routed-arrows-\(dark ? "dark" : "light").png"))
        }
    }

    func testArrowheadHasFilledInteriorAndAntialiasedEdges() async throws {
        let source = ManagedSession(name: "Source", kind: .cli)
        let target = ManagedSession(name: "Target", kind: .cli)
        let frames = [
            source.paneID: CGRect(x: 10, y: 20, width: 80, height: 60),
            target.paneID: CGRect(x: 250, y: 110, width: 60, height: 60),
        ]
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 340, height: 210), styleMask: [.titled], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(
            rootView: PaneConnectionsView(
                connections: [PaneConnection(source: source, target: target, kind: .subagent)], frames: frames
            ).background(Color.black))
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(150))
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let scale = Double(bitmap.pixelsWide) / host.bounds.width
        func brightness(_ x: Double, _ y: Double) throws -> Double {
            let c = try XCTUnwrap(bitmap.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.deviceRGB))
            return max(c.redComponent, c.greenComponent, c.blueComponent)
        }
        let interior = try brightness(243, 142)
        XCTAssertGreaterThan(interior, 0.35, "Filled triangle covers its off-axis interior")
        var partialCoverage = 0
        for x in Int(241 * scale)..<Int(250 * scale) {
            for y in Int(135 * scale)..<Int(145 * scale) {
                let c = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let value = max(c.redComponent, c.greenComponent, c.blueComponent)
                if value > 0.02 && value < interior * 0.75 { partialCoverage += 1 }
            }
        }
        XCTAssertGreaterThan(partialCoverage, 3, "Diagonal arrow edges contain blended pixels")
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
            to: URL(fileURLWithPath: "/tmp/agentdeck-filled-arrow.png"))
    }
}
