import AppKit
import SwiftTerm
import SwiftUI
import XCTest

/// The focus ring is drawn over the pane's edge. These tests keep it off session content and keep a focus change
/// from resizing the terminal.
@MainActor
final class FocusRingClearanceTests: XCTestCase {
    private let paneSize = CGSize(width: 440, height: 300)

    func testContentInsetClearsTheRingOnStraightEdgesAndInsideItsCorners() {
        XCTAssertGreaterThanOrEqual(PaneChrome.contentInset, PaneChrome.focusRingWidth)
        XCTAssertGreaterThan(PaneChrome.focusRingWidth, PaneChrome.idleBorderWidth)
        for size in [CGSize(width: 200, height: 120), paneSize, CGSize(width: 2000, height: 1600)] {
            let pane = CGRect(origin: .zero, size: size)
            XCTAssertFalse(ringCovers(content(in: pane, inset: PaneChrome.contentInset), pane: pane), "\(size)")
            // Content that runs to the pane edge, as it did up to 0.1.38, lies under the ring.
            XCTAssertTrue(ringCovers(content(in: pane, inset: 0), pane: pane), "\(size)")
            // An inset of only the ring width leaves the square content corners under the ring's inner arc.
            XCTAssertTrue(ringCovers(content(in: pane, inset: PaneChrome.focusRingWidth), pane: pane), "\(size)")
        }
    }

    func testOnlyEdgesThatMeetTheBorderAreInset() {
        XCTAssertEqual(
            PaneChrome.borderEdges(isSplit: false, isHorizontal: true, isFirst: true), [.horizontal, .bottom])
        XCTAssertEqual(PaneChrome.borderEdges(isSplit: true, isHorizontal: true, isFirst: true), [.leading, .bottom])
        XCTAssertEqual(PaneChrome.borderEdges(isSplit: true, isHorizontal: true, isFirst: false), [.trailing, .bottom])
        XCTAssertEqual(PaneChrome.borderEdges(isSplit: true, isHorizontal: false, isFirst: true), .horizontal)
        XCTAssertEqual(
            PaneChrome.borderEdges(isSplit: true, isHorizontal: false, isFirst: false), [.horizontal, .bottom])

    }

    /// Adapted from the 0.1.38 gate's `focus-border-column0-metrics.swift`: the share of a first-column glyph's ink
    /// that lies under a border of a given width.
    func testFirstColumnGlyphInkIsNeverUnderTheBorder() throws {
        let name = AppSettings().fontName
        for points in [PaneTextScale.minimum, 5.5, 7, 9, 11, 12, 13, 24, PaneTextScale.maximum] {
            let font = try XCTUnwrap(NSFont(name: name, size: points))
            for character in ["R", "a", "$", ">", "+", "-", "f", "_", "j"] {
                let ink = try inkBounds(of: character, in: font)
                for border in [PaneChrome.idleBorderWidth, PaneChrome.focusRingWidth] {
                    XCTAssertEqual(
                        hiddenShare(of: ink, textOrigin: PaneChrome.contentInset, border: border), 0,
                        "\(name) \(points) pt '\(character)' under a \(border) pt border")
                }
            }
        }
        // Control: with text starting at the pane edge the same metric reports the 0.1.38 defect (50–59 % at 12 pt).
        let font = try XCTUnwrap(NSFont(name: name, size: 12))
        for character in ["R", "a", "$", ">", "+", "-", "f"] {
            let ink = try inkBounds(of: character, in: font)
            XCTAssertGreaterThan(hiddenShare(of: ink, textOrigin: 0, border: PaneChrome.focusRingWidth), 0.4)
        }
    }

    func testRingStaysOffTheTerminalAndFocusKeepsItsGrid() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        store.settings.workspaceMode = .sessions
        let session = store.addSession(ManagedSession(name: "Fixture", kind: .cli), start: false)
        // No process is started; the flag only hides the "Not running" card and its accent-coloured button.
        store.runtime[session.id]?.isRunning = true
        let terminal = store.terminals.makeView(for: session.id, font: store.font(for: session))
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: paneSize), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }

        for scheme in [ColorScheme.dark, .light] {
            store.terminals.applyTheme(dark: scheme == .dark)
            let host = NSHostingView(
                rootView: PaneFixture(sessionID: session.id, size: paneSize).environmentObject(store)
                    .preferredColorScheme(scheme))
            window.contentView = host
            window.orderFrontRegardless()
            for points in [PaneTextScale.minimum, 12, PaneTextScale.maximum] {
                var sized = try XCTUnwrap(store.session(session.id))
                sized.fontSizeOverride = points
                store.updateSession(sized)
                var layouts: [TerminalLayout] = []
                for focused in [true, false, true] {
                    store.focusedSessionID = focused ? session.id : nil
                    try await Task.sleep(for: .milliseconds(250))
                    host.layoutSubtreeIfNeeded()
                    XCTAssertEqual(terminal.font.pointSize, points)
                    let context = "\(scheme) \(points) pt focused=\(focused)"
                    let layout = try self.layout(of: terminal, in: host)
                    layouts.append(layout)
                    let pane = CGRect(origin: .zero, size: host.bounds.size)
                    XCTAssertEqual(layout.frame.minX, PaneChrome.contentInset, accuracy: 0.01, context)
                    XCTAssertEqual(pane.maxX - layout.frame.maxX, PaneChrome.contentInset, accuracy: 0.01, context)
                    XCTAssertEqual(pane.maxY - layout.frame.maxY, PaneChrome.contentInset, accuracy: 0.01, context)
                    XCTAssertFalse(ringCovers(layout.frame, pane: pane), context)
                    XCTAssertGreaterThan(layout.columns, 0, context)
                    XCTAssertGreaterThan(layout.rows, 0, context)
                    try assertRenderedRing(
                        in: host, clears: layout.frame, focused: focused, dark: scheme == .dark, context: context)
                }
                XCTAssertEqual(layouts[1], layouts[0], "\(scheme) \(points) pt: losing focus resized the terminal")
                XCTAssertEqual(layouts[2], layouts[0], "\(scheme) \(points) pt: gaining focus resized the terminal")
            }
        }
    }

    /// A terminal beside or above its owned browser meets the border on fewer edges and paints its own gutter.
    func testSplitPaneKeepsTheTerminalClearOfTheRingAndPaintsItsGutter() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(stateURL: directory.appendingPathComponent("state.json"))
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        store.settings.workspaceMode = .sessions
        let session = store.addSession(ManagedSession(name: "Fixture", kind: .cli), start: false)
        store.runtime[session.id]?.isRunning = true
        let terminal = store.terminals.makeView(for: session.id, font: store.font(for: session))
        // The browser is never started; a stopped browser pane shows only its start button.
        var browser = ManagedSession(name: "Fixture browser", kind: .browser)
        browser.agentOwnerID = session.id
        browser = store.addSession(browser, start: false)
        let members = store.visibleSessions(in: try XCTUnwrap(store.pane(containing: session.id))).map(\.id)
        XCTAssertEqual(members, [session.id, browser.id])
        store.terminals.applyTheme(dark: true)
        store.focusedSessionID = nil
        let inset = PaneChrome.contentInset

        for size in [CGSize(width: 900, height: 400), CGSize(width: 440, height: 400)] {
            let window = NSWindow(
                contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let host = NSHostingView(
                rootView: PaneFixture(sessionID: session.id, size: size).environmentObject(store)
                    .preferredColorScheme(.dark))
            window.contentView = host
            window.orderFrontRegardless()
            try await Task.sleep(for: .milliseconds(350))
            host.layoutSubtreeIfNeeded()
            let context = "split \(Int(size.width))x\(Int(size.height))"
            let layout = try self.layout(of: terminal, in: host)
            let pane = CGRect(origin: .zero, size: host.bounds.size)
            XCTAssertEqual(layout.frame.minX, inset, accuracy: 0.01, context)
            if SubagentSplitLayout.automatic.isHorizontal(in: size) {
                // Side by side: the terminal meets the bottom border and ends at the divider.
                XCTAssertEqual(pane.maxY - layout.frame.maxY, inset, accuracy: 0.01, context)
                XCTAssertLessThan(layout.frame.maxX, pane.midX + 100, context)
            } else {
                // Stacked: the terminal meets both side borders and ends at the divider.
                XCTAssertEqual(pane.maxX - layout.frame.maxX, inset, accuracy: 0.01, context)
                XCTAssertLessThan(layout.frame.maxY, pane.maxY - 100, context)
            }
            XCTAssertFalse(ringCovers(layout.frame, pane: pane), context)
            try assertRenderedRing(in: host, clears: layout.frame, focused: false, dark: true, context: context)
        }
    }

    // MARK: Geometry

    /// Session content in pane coordinates (origin top-left): below a header, inset from the other three edges.
    private func content(in pane: CGRect, inset: CGFloat) -> CGRect {
        let header: CGFloat = 28
        return CGRect(
            x: pane.minX + inset, y: pane.minY + header, width: pane.width - 2 * inset,
            height: pane.height - header - inset)
    }

    /// The ring is the pane's rounded rectangle minus the same shape inset by the ring width. That inner shape is
    /// convex, so a rectangle is clear of the ring exactly when its four corners are inside it.
    private func ringCovers(_ rect: CGRect, pane: CGRect) -> Bool {
        let width = PaneChrome.focusRingWidth
        let radius = PaneChrome.cornerRadius - width
        let interior = CGPath(
            roundedRect: pane.insetBy(dx: width, dy: width), cornerWidth: radius, cornerHeight: radius, transform: nil)
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY),
        ]
        return !corners.allSatisfy { interior.contains($0) }
    }

    // MARK: Glyph metrics

    private func inkBounds(of character: String, in font: NSFont) throws -> CGRect {
        let units = Array(character.utf16)
        var glyph = CGGlyph(0)
        XCTAssertTrue(CTFontGetGlyphsForCharacters(font as CTFont, units, &glyph, units.count))
        let ink = font.boundingRect(forCGGlyph: glyph)
        return try XCTUnwrap(ink.width > 0 ? ink : nil, "'\(character)' has no ink in \(font.fontName)")
    }

    /// The terminal draws column 0 from the left edge of its view, which sits `textOrigin` points inside the pane.
    private func hiddenShare(of ink: CGRect, textOrigin: CGFloat, border: CGFloat) -> CGFloat {
        max(0, min(textOrigin + ink.maxX, border) - (textOrigin + ink.minX)) / ink.width
    }

    // MARK: Hosted pane

    private struct TerminalLayout: Equatable {
        /// In pane coordinates with the origin at the top-left.
        let frame: CGRect
        let columns: Int
        let rows: Int
    }

    private func layout(of terminal: DeckTerminalView, in host: NSView) throws -> TerminalLayout {
        XCTAssertTrue(terminal.window === host.window)
        var frame = terminal.convert(terminal.bounds, to: host)
        if !host.isFlipped { frame.origin.y = host.bounds.height - frame.maxY }
        let size = terminal.terminalDimensions
        return TerminalLayout(frame: frame, columns: size.cols, rows: size.rows)
    }

    /// Scans the rendered pane along the terminal's middle row and middle column. The opaque border colour must
    /// stop before the terminal on the left, right and bottom; the translucent glow is not the border. Without the
    /// glow, the gutter must continue the terminal background.
    private func assertRenderedRing(
        in host: NSView, clears terminal: CGRect, focused: Bool, dark: Bool, context: String
    ) throws {
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let name = "agentdeck-focus-ring-\(context.replacingOccurrences(of: " ", with: "-")).png"
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: FileManager.default.temporaryDirectory.appendingPathComponent(name))
        let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
        func isBorder(_ x: Int, _ y: Int) -> Bool {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
            return color.redComponent < 0.35 && color.blueComponent > 0.75
        }
        let row = Int(terminal.midY * scale)
        let column = Int(terminal.midX * scale)
        // The scan is meaningful only if it can see the border: 3 pt in is ring when focused and past the idle line.
        XCTAssertEqual(isBorder(Int(3 * scale), row), focused, "left border at 3 pt, \(context)")
        XCTAssertTrue(isBorder(Int(0.5 * scale), row), "left border at 0.5 pt, \(context)")
        let covered =
            (Int(terminal.minX * scale)..<Int(terminal.maxX * scale)).filter { isBorder($0, row) }.count
            + (Int(terminal.minY * scale)..<Int(terminal.maxY * scale)).filter { isBorder(column, $0) }.count
        XCTAssertEqual(covered, 0, "border pixels over the terminal, \(context)")
        guard !focused else { return }
        // Compared in the bitmap's own colour space; the idle border ends at 1.5 pt and the terminal starts at 6.
        let gutter = try XCTUnwrap(bitmap.colorAt(x: Int((PaneChrome.contentInset - 1) * scale), y: row))
        let background = try XCTUnwrap(TerminalHost.backgroundColor(dark: dark).usingColorSpace(bitmap.colorSpace))
        XCTAssertEqual(gutter.redComponent, background.redComponent, accuracy: 0.02, "gutter red, \(context)")
        XCTAssertEqual(gutter.greenComponent, background.greenComponent, accuracy: 0.02, "gutter green, \(context)")
        XCTAssertEqual(gutter.blueComponent, background.blueComponent, accuracy: 0.02, "gutter blue, \(context)")
    }
}

/// Reads the pane from the store on every update, as PaneGridView does.
private struct PaneFixture: View {
    @EnvironmentObject var store: AppStore
    let sessionID: UUID
    let size: CGSize

    var body: some View {
        if let pane = store.pane(containing: sessionID) {
            PaneView(pane: pane, size: PaneSize(width: size.width, height: size.height), mode: .fixed)
        }
    }
}
