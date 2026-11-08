import WebKit

/// Fit the document's CSS width after navigation or native viewport resizing; vertical scrolling stays native.
@MainActor
final class BrowserPageFit {
    private weak var webView: WKWebView?
    private var enabled = false
    private var manualZoom: Double?
    private var generation = 0
    private var pending: Task<Void, Never>?

    init(webView: WKWebView) { self.webView = webView }

    func setZoom(manual: Double?) {
        let manual = manual.flatMap { $0.isFinite && $0 > 0 ? min(4, max(0.05, $0)) : nil }
        let changed = !enabled || manual != manualZoom
        enabled = true
        manualZoom = manual
        if let manual, manual.isFinite, manual > 0 {
            cancel()
            if let webView, webView.pageZoom != CGFloat(manual) { webView.pageZoom = CGFloat(manual) }
        } else if changed {
            requestFit()
        }
    }

    func requestFit() {
        guard enabled, manualZoom == nil, let webView, webView.bounds.width > 1 else { return }
        cancel()
        let token = generation
        pending = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.measure(generation: token)
        }
    }

    private func measure(generation token: Int) {
        guard token == generation, manualZoom == nil, let webView else { return }
        let width = webView.bounds.width
        let url = webView.url
        // Measure at normal zoom so widening a previously shrunken pane can grow back to readable text.
        if webView.pageZoom != 1 { webView.pageZoom = 1 }
        webView.evaluateJavaScript(
            "Math.max(document.documentElement?.scrollWidth || 0, document.body?.scrollWidth || 0)",
            in: nil, in: .defaultClient
        ) { [weak self, weak webView] result in
            guard let self, token == self.generation, self.manualZoom == nil, let webView,
                webView.bounds.width == width, webView.url == url,
                case .success(let value) = result, let number = value as? NSNumber
            else { return }
            let documentWidth = number.doubleValue
            guard documentWidth.isFinite, documentWidth > 0 else { return }
            let zoom = min(1, max(0.05, width / documentWidth))
            if abs(webView.pageZoom - zoom) > 0.001 { webView.pageZoom = zoom }
        }
    }

    func cancel() {
        generation += 1
        pending?.cancel()
        pending = nil
    }

    deinit { pending?.cancel() }
}
