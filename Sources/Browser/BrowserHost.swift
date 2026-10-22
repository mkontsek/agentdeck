import AppKit
import WebKit
import Combine

/// One isolated WKWebView per browser session. Each session has its own persistent website data store
/// (cookies, local storage, logins), so profiles never collide.
@MainActor
final class BrowserController: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let id: UUID
    let webView: WKWebView
    @Published var urlText: String
    @Published var title: String = ""
    @Published var isLoading: Bool = false
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false

    var onStateChange: ((UUID) -> Void)?

    init(id: UUID, profileID: UUID, url: String) {
        self.id = id
        self.urlText = url
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: profileID)
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        // A Safari UA keeps Google/OpenAI sign-in flows from rejecting the embedded view.
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        webView.allowsBackForwardNavigationGestures = true
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        load(url)
    }

    func load(_ text: String) {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return }
        if !s.contains("://") { s = "https://" + s }
        guard let u = URL(string: s) else { return }
        webView.load(URLRequest(url: u))
    }

    private func sync() {
        title = webView.title ?? ""
        isLoading = webView.isLoading
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        if let u = webView.url?.absoluteString { urlText = u }
        onStateChange?(id)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { sync() }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { sync() }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { sync() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { sync() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { sync() }

    // Open popups (OAuth windows etc.) in the same view.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let u = navigationAction.request.url { webView.load(URLRequest(url: u)) }
        return nil
    }
}

@MainActor
final class BrowserHost {
    private(set) var controllers: [UUID: BrowserController] = [:]
    var onStateChange: ((UUID) -> Void)?

    func controller(for session: ManagedSession) -> BrowserController {
        if let c = controllers[session.id] { return c }
        let c = BrowserController(id: session.id, profileID: session.browserProfileID, url: session.url ?? "https://")
        c.onStateChange = { [weak self] id in self?.onStateChange?(id) }
        controllers[session.id] = c
        return c
    }

    func dispose(id: UUID) {
        controllers[id]?.webView.removeFromSuperview()
        controllers[id] = nil
    }

    func isRunning(_ id: UUID) -> Bool { controllers[id] != nil }

    /// Remove the persisted profile data of a session (cookies, storage).
    static func deleteProfile(_ profileID: UUID) {
        WKWebsiteDataStore.remove(forIdentifier: profileID) { _ in }
    }
}
