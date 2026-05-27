import SwiftUI
import WebKit

struct WebViewPanel: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> NSView {
        // Wrap WKWebView in a container NSView — container gets proper frame from SwiftUI
        // WKWebView is autoresized to fill container, which triggers correct layout
        let container = NSView()
        container.autoresizesSubviews = true
        webView.autoresizingMask      = [.width, .height]
        webView.frame                 = container.bounds
        container.addSubview(webView)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Ensure WKWebView fills container whenever layout changes
        if let wv = nsView.subviews.first as? WKWebView {
            wv.frame = nsView.bounds
        }
    }
}
