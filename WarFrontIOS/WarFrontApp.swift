import SwiftUI
import WebKit

@main
struct WarFrontApp: App {
    var body: some Scene {
        WindowGroup { WarFrontView().ignoresSafeArea() }
    }
}

struct WarFrontView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = UIColor(red: 0.06, green: 0.10, blue: 0.14, alpha: 1)
        web.scrollView.isScrollEnabled = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.navigationDelegate = context.coordinator
        if let root = Bundle.main.url(forResource: "Web", withExtension: nil) {
            do {
                let server = LocalWebServer(root: root)
                try server.start()
                context.coordinator.server = server
                web.load(URLRequest(url: server.url))
            } catch {
                web.loadHTMLString("<h3>WarFront local server failed: \(error)</h3>", baseURL: nil)
            }
        } else {
            web.loadHTMLString("<h3>WarFront assets not found.</h3>", baseURL: nil)
        }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        var server: LocalWebServer?
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = action.request.url,
               url.host != "127.0.0.1", url.scheme != "about" {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            NSLog("WarFront navigation failed: %@", String(describing: error))
        }
    }
}
