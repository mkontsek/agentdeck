import AppKit
import XCTest

final class PaneFocusTests: XCTestCase {
    @MainActor
    func testInactivePaneConsumesClickAndDragBeforeContent() throws {
        _ = NSApplication.shared
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 300))
        let content = NSView(frame: container.bounds)
        let overlay = FocusClickView(frame: container.bounds)
        container.addSubview(content)
        container.addSubview(overlay)
        var focusCount = 0
        overlay.onFocus = { focusCount += 1 }
        let point = NSPoint(x: 50, y: 50)
        XCTAssertTrue(container.hitTest(point) === overlay)
        let click = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, eventNumber: 1, clickCount: 2, pressure: 1))
        overlay.mouseDown(with: click)
        overlay.mouseDragged(with: click)
        overlay.mouseUp(with: click)
        XCTAssertEqual(focusCount, 1)
        overlay.removeFromSuperview()
        XCTAssertTrue(container.hitTest(point) === content, "Focused content must receive subsequent clicks")
    }
}
