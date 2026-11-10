import SwiftUI
import WebKit

struct BrowserPaneView: View {
    @EnvironmentObject var store: AppStore
    let session: ManagedSession

    var body: some View {
        if store.runtime[session.id]?.isRunning == true,
            let controller = store.browsers.controllers[session.id]
        {
            BrowserInner(controller: controller, session: session)
        } else {
            Button("Start browser") { store.restartSession(session.id) }
                .buttonStyle(.borderedProminent)
        }
    }
}

private struct BrowserInner: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.isGlassBallCollapsed) private var collapsed
    @Environment(\.isGlassBallTransitioning) private var transitioning
    @ObservedObject var controller: BrowserController
    let session: ManagedSession

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button {
                    controller.webView.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }.disabled(!controller.canGoBack)
                Button {
                    controller.webView.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                }.disabled(!controller.canGoForward)
                Button {
                    if controller.isLoading { controller.webView.stopLoading() } else { controller.webView.reload() }
                } label: {
                    Image(systemName: controller.isLoading ? "xmark" : "arrow.clockwise")
                }
                TextField("URL", text: $controller.urlText)
                    .textFieldStyle(.roundedBorder).font(.caption)
                    .onSubmit { controller.load(controller.urlText) }
                Menu {
                    ForEach(BrowserProfileMode.allCases) { mode in
                        Button(mode.label) { store.setBrowserProfileMode(mode, for: session.id) }
                    }
                } label: {
                    Image(systemName: session.browserProfileMode == .shared ? "person.2.fill" : "person.fill")
                }
                .help(
                    session.browserProfileMode == .shared
                        ? "Shared sign-ins · saved locally across AgentDeck panes"
                        : "Separate account · this pane’s own saved sign-ins"
                )
                .accessibilityLabel("Browser profile: \(session.browserProfileMode.label)")
                if controller.isLoading { ProgressView().controlSize(.small) }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 6).padding(.vertical, 4)
            Divider()
            WebViewRepresentable(
                webView: controller.webView,
                zoom: store.browserZoomOverride(for: session),
                focused: !collapsed && !store.isDemoMode && store.focusedSessionID == session.id
                    && store.settings.workspaceMode == .sessions, collapsed: collapsed, transitioning: transitioning)
        }
    }
}

struct WebViewRepresentable: NSViewRepresentable {
    let webView: FocusProtectedWebView
    var zoom: Double? = nil
    let focused: Bool
    var collapsed = false
    var transitioning = false

    func makeNSView(context: Context) -> BrowserContainerView {
        let c = BrowserContainerView()
        c.autoresizesSubviews = true
        attach(c)
        return c
    }

    func updateNSView(_ c: BrowserContainerView, context: Context) { attach(c) }

    static func dismantleNSView(_ c: BrowserContainerView, coordinator: ()) {
        c.focusWhenAttached = false
        for case let view as FocusProtectedWebView in c.subviews {
            view.allowsKeyboardFocus = false
            view.isHidden = false
            view.autoresizingMask = [.width, .height]
            view.removeFromSuperview()
        }
    }

    private func attach(_ c: BrowserContainerView) {
        webView.isHidden = collapsed
        webView.pageFit.setZoom(manual: zoom)
        webView.allowsKeyboardFocus = focused
        if webView.superview !== c {
            webView.removeFromSuperview()
            webView.frame = c.bounds
            webView.autoresizingMask = [.width, .height]
            c.addSubview(webView)
        }
        c.focusWhenAttached = focused
        if transitioning || collapsed {
            webView.autoresizingMask = []
        } else if webView.autoresizingMask.isEmpty {
            webView.frame = c.bounds
            webView.autoresizingMask = [.width, .height]
        }
        c.focusBrowserIfNeeded()
    }
}

final class BrowserContainerView: NSView {
    var focusWhenAttached = false
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusBrowserIfNeeded()
    }

    func focusBrowserIfNeeded() {
        guard focusWhenAttached, let window, let browser = subviews.first as? FocusProtectedWebView else { return }
        focusWhenAttached = false
        guard window.firstResponder == nil || window.firstResponder === window else { return }
        browser.requestKeyboardFocus()
    }
}
