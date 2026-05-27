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
        // Force layout pass — WKWebView with frame:.zero doesn't render until layout occurs
        DispatchQueue.main.async {
            nsView.needsLayout = true
            nsView.layoutSubtreeIfNeeded()
        }
    }
}
