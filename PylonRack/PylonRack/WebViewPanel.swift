import SwiftUI
import WebKit

struct WebViewPanel: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        webView.load(request)

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Reload only if URL changed
        if nsView.url?.absoluteString != url.absoluteString {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            nsView.load(request)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!,
                     withError error: Error) {
            NSLog("[WebViewPanel] Navigation error: %@", error.localizedDescription)
        }
        func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError error: Error) {
            NSLog("[WebViewPanel] Load error: %@", error.localizedDescription)
        }
        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            NSLog("[WebViewPanel] Loaded: %@", webView.url?.absoluteString ?? "?")
        }
    }
}
