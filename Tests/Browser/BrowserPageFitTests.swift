import AppKit
import SwiftUI
import WebKit
import XCTest

@MainActor
final class BrowserPageFitTests: XCTestCase {
    func testNativeWidthFitResizeNavigationAndManualOverride() async throws {
        let profile = UUID()
        let controller = BrowserController(id: UUID(), profileID: profile, url: "about:blank")
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 500, height: 350), styleMask: [.titled, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: WebViewRepresentable(webView: controller.webView, focused: true))
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            controller.dispose()
            window.close()
            BrowserHost.deleteProfile(profile)
        }
        controller.webView.loadHTMLString(
            "<style>body{margin:0;width:1200px;height:2400px}</style><h1>Width fit fixture</h1>", baseURL: nil)
        try await until { !controller.isLoading && abs(controller.webView.pageZoom - 500.0 / 1200) < 0.01 }
        let widthResult = await controller.evaluate(
            "document.documentElement.scrollWidth <= innerWidth + 2 && document.documentElement.scrollHeight > innerHeight"
        )
        guard case .success(let value) = widthResult else { return XCTFail("Could not inspect local width fixture") }
        XCTAssertEqual(value, "1", "Width fits; the long page still scrolls vertically")
        window.setContentSize(CGSize(width: 300, height: 350))
        try await until { abs(controller.webView.pageZoom - 0.25) < 0.01 }
        host.rootView = WebViewRepresentable(webView: controller.webView, zoom: 0.75, focused: true)
        try await until { controller.webView.pageZoom == 0.75 }
        window.setContentSize(CGSize(width: 450, height: 350))
        controller.webView.loadHTMLString(
            "<style>body{margin:0;width:1500px;height:2400px}</style><h1>Second page</h1>", baseURL: nil)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(controller.webView.pageZoom, 0.75)
        host.rootView = WebViewRepresentable(webView: controller.webView, focused: true)
        try await until { abs(controller.webView.pageZoom - 0.3) < 0.01 }
        window.setContentSize(CGSize(width: 1600, height: 500))
        try await until { controller.webView.pageZoom == 1 }
        controller.webView.pageFit.setZoom(manual: Double.greatestFiniteMagnitude)
        XCTAssertEqual(controller.webView.pageZoom, 4)
        controller.webView.pageFit.setZoom(manual: .nan)
        try await until { controller.webView.pageZoom == 1 }
        XCTAssertTrue(controller.webView.window === window)
    }

    private func until(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), "Native page fit timed out")
    }
}
