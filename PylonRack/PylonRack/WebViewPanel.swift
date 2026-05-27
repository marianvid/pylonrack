import SwiftUI
import WebKit

struct WebViewPanel: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.autoresizesSubviews = true
        webView.autoresizingMask      = [.width, .height]
        webView.frame                 = container.bounds
        container.addSubview(webView)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let wv = nsView.subviews.first as? WKWebView else { return }
        if wv.frame != nsView.bounds {
            wv.frame = nsView.bounds
            // Dispatch resize event so SPA (SvelteKit/React) recalculates layout
            wv.evaluateJavaScript("window.dispatchEvent(new Event('resize'))", completionHandler: nil)
        }
    }
}
