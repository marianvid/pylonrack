import SwiftUI
import WebKit

struct WebViewPanel: NSViewRepresentable {
    let url:         URL
    var reloadToken: UUID

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
        // Reload only when reloadToken changes (explicit signal from slot app)
        // NOT when toggling log/webview — preserve the existing session
        guard context.coordinator.lastToken != reloadToken else { return }
        context.coordinator.lastToken = reloadToken

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        nsView.load(request)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(token: reloadToken)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastToken: UUID

        init(token: UUID) {
            self.lastToken = token
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
