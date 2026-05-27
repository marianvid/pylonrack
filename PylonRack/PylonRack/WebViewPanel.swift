import SwiftUI
import WebKit

// WebViewPanel wraps a persistent WKWebView owned by SlotConnection.
// The WKWebView is created once on manifest and survives log toggle, slot selection changes.
// Reload is triggered by SlotConnection.dispatch(.reloadUI) directly on the WKWebView instance.

struct WebViewPanel: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        NSLog("[WebViewPanel] makeNSView called — url: %@", webView.url?.absoluteString ?? "loading")
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Nothing — WKWebView is managed by SlotConnection
    }
}
