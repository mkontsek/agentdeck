import AppKit
import Combine
import WebKit

struct BrowserScriptError: Error {
    let message: String
}

/// Resumes a continuation at most once; WebKit completion handlers run on the main thread.
@MainActor
private final class ResumeOnce<Value> {
    var continuation: CheckedContinuation<Value, Never>?
    func resume(_ value: Value) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}

/// One WKWebView per browser session, backed by a shared or isolated persistent website data store.
@MainActor
final class BrowserController: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let id: UUID
    let webView: FocusProtectedWebView
    @Published var urlText: String
    @Published var title: String = ""
    @Published var isLoading: Bool = false
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false

    var onStateChange: ((UUID) -> Void)?
    var downloadDirectory: @MainActor () -> URL
    var onDownload: (@MainActor (DownloadEvent) -> Void)?
    private var navigationWaiters: [ObjectIdentifier: CheckedContinuation<String?, Never>] = [:]
    private var downloads: [ObjectIdentifier: WKDownload] = [:]
    private var downloadPaths: [ObjectIdentifier: String] = [:]
    private var reservedPaths: Set<String> = []
    private var urlObservation: NSKeyValueObservation?
    private var automationPanel: BrowserAutomationPanel?
    private(set) var isClosed = false
    private(set) var popupWindows: [UUID: BrowserPopupWindow] = [:]
    var onClose: (@MainActor () -> Void)?
    private let isPopup: Bool
    private let popupBudget: BrowserPopupBudget

    convenience init(
        id: UUID, profileID: UUID, url: String, keepsRenderingWhenOccluded: Bool = false,
        downloadDirectory: @escaping @MainActor () -> URL = { DownloadLocation.directory(from: "") },
        onDownload: (@MainActor (DownloadEvent) -> Void)? = nil
    ) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: profileID)
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        self.init(
            id: id, configuration: config, url: url, popupBudget: BrowserPopupBudget(),
            downloadDirectory: downloadDirectory, onDownload: onDownload)
        // A Safari UA keeps Google/OpenAI sign-in flows from rejecting the embedded view.
        webView.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        if keepsRenderingWhenOccluded { Self.disableOcclusionDetection(webView) }
        load(url)
    }

    /// A popup must use WebKit's configuration unchanged; WebKit performs its initial navigation.
    private init(
        id: UUID, configuration: WKWebViewConfiguration, url: String?, popupBudget: BrowserPopupBudget,
        downloadDirectory: @escaping @MainActor () -> URL,
        onDownload: (@MainActor (DownloadEvent) -> Void)?
    ) {
        self.id = id
        self.urlText = url ?? "about:blank"
        self.downloadDirectory = downloadDirectory
        self.onDownload = onDownload
        self.isPopup = url == nil
        self.popupBudget = popupBudget
        webView = FocusProtectedWebView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.sync() }
        }
    }

    func dispose() {
        guard !isClosed else { return }
        isClosed = true
        let children = popupWindows.values
        popupWindows.removeAll()
        for child in children { child.close() }
        closeAutomationPanel()
        cancelWaiters()
        onDownload = nil
        for download in downloads.values {
            download.delegate = nil
            download.cancel { _ in }
        }
        downloads.removeAll()
        downloadPaths.removeAll()
        reservedPaths.removeAll()
        onStateChange = nil
        urlObservation = nil
        webView.stopLoading()
        webView.pageFit.cancel()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
        onClose = nil
    }

    /// Agent browsers keep working while the user's own windows cover AgentDeck. WebKit otherwise pauses rendering
    /// and timers for occluded views; this flips its private switch when the running WebKit has it.
    private static func disableOcclusionDetection(_ webView: WKWebView) {
        let selector = Selector(("_setWindowOcclusionDetectionEnabled:"))
        guard webView.responds(to: selector) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
        let setter = unsafeBitCast(webView.method(for: selector), to: Setter.self)
        setter(webView, selector, false)
    }

    /// Hidden pages render in a non-key panel. Putting them in the main window lets WebKit clear that
    /// window's first responder even when its own becomeFirstResponder() rejects focus.
    func ensureInWindow() {
        guard !isClosed, webView.window == nil else { return }
        webView.allowsKeyboardFocus = false
        let panel: BrowserAutomationPanel
        if let existing = automationPanel {
            panel = existing
        } else {
            panel = BrowserAutomationPanel(
                contentRect: NSRect(x: -16384, y: -16384, width: 1024, height: 768),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = true
            panel.isExcludedFromWindowsMenu = true
            automationPanel = panel
        }
        guard let content = panel.contentView else { return }
        webView.removeFromSuperview()
        webView.autoresizingMask = [.width, .height]
        webView.frame = content.bounds
        content.addSubview(webView)
        panel.orderFrontRegardless()
    }

    func closeAutomationPanel() {
        automationPanel?.orderOut(nil)
        automationPanel?.close()
        automationPanel = nil
    }

    // MARK: Automation

    /// Load `text` and wait for the navigation to finish. Returns an error message, or nil on success.
    func navigate(_ text: String, timeoutSeconds: Double = 20) async -> String? {
        guard !isClosed else { return "browser closed" }
        guard let url = Self.url(from: text) else { return "invalid url \(text)" }
        guard let navigation = webView.load(URLRequest(url: url)) else { return "navigation could not start" }
        let key = ObjectIdentifier(navigation)
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(timeoutSeconds))
            guard !Task.isCancelled else { return }
            self?.navigationWaiters.removeValue(forKey: key)?.resume(
                returning: "timed out after \(Int(timeoutSeconds))s")
        }
        let result = await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
            navigationWaiters[key] = c
        }
        timeout.cancel()
        return result
    }

    private func finish(_ navigation: WKNavigation?, error: String?) {
        guard let navigation else { return }
        navigationWaiters.removeValue(forKey: ObjectIdentifier(navigation))?.resume(returning: error)
    }

    func cancelWaiters() {
        let waiters = navigationWaiters
        navigationWaiters.removeAll()
        for waiter in waiters.values { waiter.resume(returning: "browser closed") }
    }

    /// Evaluate JavaScript; the result is rendered as text (strings as-is, objects as JSON). A script that does
    /// not come back within the deadline fails instead of holding the caller's MCP connection open.
    func evaluate(_ script: String, timeoutSeconds: Double = 60) async -> Result<String, BrowserScriptError> {
        let once = ResumeOnce<Result<String, BrowserScriptError>>()
        return await withCheckedContinuation { c in
            once.continuation = c
            let timeout = Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                guard !Task.isCancelled else { return }
                once.resume(.failure(BrowserScriptError(message: "javascript timed out after \(timeoutSeconds)s")))
            }
            webView.evaluateJavaScript(script) { value, error in
                timeout.cancel()
                if let error {
                    let ns = error as NSError
                    let detail = ns.userInfo["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
                    once.resume(.failure(BrowserScriptError(message: "javascript error: \(detail)")))
                } else {
                    once.resume(.success(Self.render(value)))
                }
            }
        }
    }

    private static func render(_ value: Any?) -> String {
        switch value {
        case nil, is NSNull: return "null"
        case let s as String: return s
        case let n as NSNumber: return n.description
        default:
            if let value, JSONSerialization.isValidJSONObject(value),
                let d = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            {
                return String(decoding: d, as: UTF8.self)
            }
            return value.map { "\($0)" } ?? "null"
        }
    }

    /// PNG of the current page, at most `maxWidth` points wide.
    func snapshot(maxWidth: CGFloat = 1280) async -> Data? {
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = NSNumber(value: Double(min(maxWidth, max(320, webView.bounds.width))))
        return await withCheckedContinuation { (c: CheckedContinuation<Data?, Never>) in
            webView.takeSnapshot(with: config) { image, _ in
                guard let tiff = image?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
                    c.resume(returning: nil)
                    return
                }
                c.resume(returning: rep.representation(using: .png, properties: [:]))
            }
        }
    }

    func load(_ text: String) {
        guard !isClosed, let u = Self.url(from: text) else { return }
        webView.load(URLRequest(url: u))
    }

    /// Bare host names get https://; anything with a scheme (http, data, about, file…) is used as typed.
    static func url(from text: String) -> URL? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if s.range(of: "^[A-Za-z][A-Za-z0-9+.-]*:", options: .regularExpression) == nil { s = "https://" + s }
        return URL(string: s)
    }

    private func sync() {
        title = webView.title ?? ""
        isLoading = webView.isLoading
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        if let u = webView.url?.absoluteString { urlText = u }
        onStateChange?(id)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        self.webView.pageFit.cancel()
        sync()
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { sync() }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        sync()
        self.webView.pageFit.requestFit()
        finish(navigation, error: nil)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        sync()
        finish(navigation, error: error.localizedDescription)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        sync()
        finish(navigation, error: error.localizedDescription)
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        if isClosed || (isPopup && !Self.allowsPopupURL(navigationAction.request.url)) {
            decisionHandler(.cancel, preferences)
        } else if navigationAction.shouldPerformDownload {
            decisionHandler(.download, preferences)
        } else {
            decisionHandler(.allow, preferences)
        }
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        if Self.shouldDownload(navigationResponse) {
            decisionHandler(.download)
        } else {
            decisionHandler(.allow)
        }
    }

    private static func shouldDownload(_ navigationResponse: WKNavigationResponse) -> Bool {
        if !navigationResponse.canShowMIMEType { return true }
        guard let http = navigationResponse.response as? HTTPURLResponse else { return false }
        let disposition = http.value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        return disposition.contains("attachment")
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        accept(download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        accept(download)
    }

    private func accept(_ download: WKDownload) {
        guard !isClosed else {
            download.cancel { _ in }
            return
        }
        download.delegate = self
        downloads[ObjectIdentifier(download)] = download
        let pending = navigationWaiters
        navigationWaiters.removeAll()
        for waiter in pending.values { waiter.resume(returning: nil) }
    }

    // Keep the opener alive. Re-loading this request in the parent loses POST bodies and the window relationship.
    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard webView === self.webView, !isClosed, navigationAction.targetFrame == nil,
            Self.allowsPopupURL(navigationAction.request.url), popupBudget.count < BrowserPopupBudget.limit
        else { return nil }
        let child = BrowserController(
            id: UUID(), configuration: configuration, url: nil, popupBudget: popupBudget,
            downloadDirectory: downloadDirectory, onDownload: onDownload)
        child.webView.customUserAgent = webView.customUserAgent
        let popup = BrowserPopupWindow(controller: child, features: windowFeatures)
        let childID = child.id
        popupBudget.count += 1
        popupWindows[childID] = popup
        popup.onClose = { [weak self, budget = popupBudget] in
            budget.count -= 1
            self?.popupWindows.removeValue(forKey: childID)
        }
        popup.show()
        return child.webView
    }

    static func allowsPopupURL(_ url: URL?) -> Bool {
        guard let url else { return true }  // window.open() starts with an empty document.
        if url.absoluteString.isEmpty { return true }
        switch url.scheme?.lowercased() {
        case "http", "https": return url.host?.isEmpty == false
        case "about": return url.absoluteString == "about:blank"
        default: return false
        }
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard webView === self.webView else { return }
        onClose?()
    }

    // macOS WebKit shows no file chooser unless the UI delegate provides one: without this, an upload button or
    // `<input type=file>` in a page (Gemini, ChatGPT, SuperFaktura) silently does nothing.
    func webView(
        _ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor ([URL]?) -> Void
    ) {
        let panel = Self.uploadPanel(for: parameters, host: webView.url?.host)
        let finish: @MainActor (NSApplication.ModalResponse) -> Void = { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
        // A hidden companion browser is parked inside the main window, so the sheet still has somewhere to attach.
        if let window = webView.window ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window) { response in MainActor.assumeIsolated { finish(response) } }
        } else {
            finish(panel.runModal())
        }
    }

    static func uploadPanel(for parameters: WKOpenPanelParameters, host: String?) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canCreateDirectories = false
        panel.prompt = "Upload"
        panel.message =
            "Choose \(parameters.allowsMultipleSelection ? "files" : "a file") to upload to \(host ?? "this page")"
        return panel
    }
}

extension BrowserController: WKDownloadDelegate {
    func download(
        _ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
        completionHandler: @escaping @MainActor @Sendable (URL?) -> Void
    ) {
        guard !isClosed else {
            completionHandler(nil)
            return
        }
        let directory = downloadDirectory()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            onDownload?(
                .failed(
                    "could not create download folder \(directory.path.abbreviatingHome): \(error.localizedDescription)"
                ))
            completionHandler(nil)
            return
        }
        let destination = DownloadLocation.destinationURL(directory: directory, suggestedFilename: suggestedFilename) {
            url in
            reservedPaths.contains(url.path) || FileManager.default.fileExists(atPath: url.path)
        }
        let parent = destination.deletingLastPathComponent().standardizedFileURL.path
        guard parent == directory.standardizedFileURL.path else {
            onDownload?(.failed("refused a download name that left \(directory.path.abbreviatingHome)"))
            completionHandler(nil)
            return
        }
        let key = ObjectIdentifier(download)
        downloads[key] = download
        downloadPaths[key] = destination.path
        reservedPaths.insert(destination.path)
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        let key = ObjectIdentifier(download)
        if let path = downloadPaths[key] {
            onDownload?(.saved(URL(fileURLWithPath: path)))
        }
        release(download)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        _ = resumeData
        onDownload?(.failed("download failed: \(error.localizedDescription)"))
        release(download)
    }

    private func release(_ download: WKDownload) {
        let key = ObjectIdentifier(download)
        if let path = downloadPaths.removeValue(forKey: key) { reservedPaths.remove(path) }
        downloads.removeValue(forKey: key)
    }
}

@MainActor
final class BrowserHost {
    private(set) var controllers: [UUID: BrowserController] = [:]
    var onStateChange: ((UUID) -> Void)?
    var downloadDirectory: @MainActor () -> URL = { DownloadLocation.directory(from: "") }
    var onDownload: (@MainActor (DownloadEvent) -> Void)?

    func controller(for session: ManagedSession, sharedProfileID: UUID) -> BrowserController {
        if let c = controllers[session.id] { return c }
        let c = BrowserController(
            id: session.id, profileID: session.browserDataStoreID(sharedProfileID: sharedProfileID),
            url: session.url ?? "about:blank", keepsRenderingWhenOccluded: session.agentOwnerID != nil,
            downloadDirectory: { [weak self] in
                self?.downloadDirectory() ?? DownloadLocation.directory(from: "")
            },
            onDownload: { [weak self] event in self?.onDownload?(event) })
        c.onStateChange = { [weak self] id in self?.onStateChange?(id) }
        controllers[session.id] = c
        return c
    }

    func dispose(id: UUID) {
        controllers.removeValue(forKey: id)?.dispose()
    }

    func isRunning(_ id: UUID) -> Bool { controllers[id] != nil }

    /// Remove the persisted profile data of a session (cookies, storage).
    static func deleteProfile(_ profileID: UUID) {
        WKWebsiteDataStore.remove(forIdentifier: profileID) { _ in }
    }
}
