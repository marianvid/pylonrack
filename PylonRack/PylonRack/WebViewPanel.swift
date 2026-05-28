import SwiftUI
import WebKit

struct WebViewPanel: NSViewRepresentable {
    let webView: WKWebView
    let url:     URL

    func makeNSView(context: Context) -> WebViewContainer {
        let container = WebViewContainer(webView: webView, url: url)
        webView.autoresizingMask   = [.width, .height]
        webView.navigationDelegate = context.coordinator
        container.autoresizesSubviews = true
        container.addSubview(webView)
        return container
    }

    func updateNSView(_ nsView: WebViewContainer, context: Context) {
        webView.frame = nsView.bounds
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // NSView subclass — triggers load when added to window hierarchy with real size
    final class WebViewContainer: NSView {
        let webView: WKWebView
        let url:     URL
        private var loaded = false

        init(webView: WKWebView, url: URL) {
            self.webView = webView
            self.url     = url
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, !loaded else { return }
            // Schedule after layout pass so bounds are non-zero
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.loaded, !self.bounds.isEmpty else { return }
                self.loaded = true
                self.webView.frame = self.bounds
                var req = URLRequest(url: self.url)
                req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                self.webView.load(req)
                NSLog("[WebViewPanel] Loading %@ with frame %@",
                      self.url.absoluteString, NSStringFromRect(self.bounds))
            }
        }

        override func layout() {
            super.layout()
            webView.frame = bounds
            // If not yet loaded but now have a real frame, trigger load
            if !loaded && !bounds.isEmpty {
                loaded = true
                var req = URLRequest(url: url)
                req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                webView.load(req)
                NSLog("[WebViewPanel] Loading %@ from layout with frame %@",
                      url.absoluteString, NSStringFromRect(bounds))
            }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                webView.evaluateJavaScript(
                    "window.dispatchEvent(new Event('resize'))",
                    completionHandler: nil
                )
            }
            NSLog("[WebViewPanel] Loaded: %@", webView.url?.absoluteString ?? "?")
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!,
                     withError error: Error) {
            NSLog("[WebViewPanel] Error: %@", error.localizedDescription)
        }
    }
}
