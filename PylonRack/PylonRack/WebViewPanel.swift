import SwiftUI
import WebKit

struct WebViewPanel: NSViewRepresentable {
    let url:         URL
    var reloadToken: UUID = UUID()

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        load(url: url, in: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Reload when url changes OR when reloadToken changes (explicit reload_ui signal)
        if context.coordinator.lastURL != url || context.coordinator.lastToken != reloadToken {
            context.coordinator.lastURL   = url
            context.coordinator.lastToken = reloadToken
            load(url: url, in: nsView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(url: url, token: reloadToken) }

    private func load(url: URL, in webView: WKWebView) {
        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            // Clear cache before reload to ensure fresh content (e.g. model name in UI)
            WKWebsiteDataStore.default().removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: Date(timeIntervalSince1970: 0)
            ) {
                var request = URLRequest(url: url)
                request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                webView.load(request)
            }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastURL:   URL
        var lastToken: UUID

        init(url: URL, token: UUID) {
            lastURL   = url
            lastToken = token
        }

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
