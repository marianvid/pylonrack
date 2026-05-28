import SwiftUI
import WebKit

struct WebViewPanel: NSViewRepresentable {
    let webView: WKWebView
    let url:     URL

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.autoresizesSubviews = true
        webView.autoresizingMask   = [.width, .height]
        webView.navigationDelegate = context.coordinator
        container.addSubview(webView)
        // Frame is set by SwiftUI layout before makeNSView returns via updateNSView
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let newFrame = nsView.bounds
        guard newFrame != webView.frame else { return }
        webView.frame = newFrame

        // Load URL the first time we have a real non-zero frame
        if context.coordinator.needsInitialLoad && !newFrame.isEmpty {
            context.coordinator.needsInitialLoad = false
            var req = URLRequest(url: url)
            req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            webView.load(req)
            NSLog("[WebViewPanel] Initial load triggered with frame %@", NSStringFromRect(newFrame))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let url: URL
        var needsInitialLoad = true

        init(url: URL) { self.url = url }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Dispatch resize so SPA (SvelteKit) recalculates layout after load
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
