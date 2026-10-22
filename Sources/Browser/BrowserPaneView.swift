import SwiftUI
import WebKit

struct BrowserPaneView: View {
    @EnvironmentObject var store: AppStore
    let session: ManagedSession

    var body: some View {
        if store.runtime[session.id]?.isRunning == true,
            let controller = store.browsers.controllers[session.id]
        {
            BrowserInner(controller: controller)
        } else {
            Button("Start browser") { store.restartSession(session.id) }
                .buttonStyle(.borderedProminent)
        }
    }
}

private struct BrowserInner: View {
    @ObservedObject var controller: BrowserController

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
                if controller.isLoading { ProgressView().controlSize(.small) }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 6).padding(.vertical, 4)
            Divider()
            WebViewRepresentable(webView: controller.webView)
        }
    }
}

struct WebViewRepresentable: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> NSView {
        let c = NSView()
        c.autoresizesSubviews = true
        attach(c)
        return c
    }

    func updateNSView(_ c: NSView, context: Context) { attach(c) }

    private func attach(_ c: NSView) {
        if webView.superview !== c {
            webView.removeFromSuperview()
            webView.frame = c.bounds
            webView.autoresizingMask = [.width, .height]
            c.addSubview(webView)
        }
    }
}
