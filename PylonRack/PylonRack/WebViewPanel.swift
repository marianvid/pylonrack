import SwiftUI
import WebKit

struct WebViewPanel: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.autoresizesSubviews = true
        webView.autoresizingMask      = [.width, .height]
        webView.navigationDelegate    = context.coordinator
        container.addSubview(webView)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Only update frame — no resize dispatch here (causes blank on re-render)
        webView.frame = nsView.bounds
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Dispatch resize after page fully loaded — fixes SPA layout on first render
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                webView.evaluateJavaScript(
                    "window.dispatchEvent(new Event('resize'))",
                    completionHandler: nil
                )
            }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!,
                     withError error: Error) {
            NSLog("[WebViewPanel] Navigation error: %@", error.localizedDescription)
        }
    }
}
