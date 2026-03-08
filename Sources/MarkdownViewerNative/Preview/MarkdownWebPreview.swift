import AppKit
import SwiftUI
import WebKit

struct MarkdownWebPreview: NSViewRepresentable {
    let html: String
    let baseURL: URL
    let zoomLevel: Double
    let colorScheme: ColorScheme
    let navigationRequest: OutlineNavigationRequest?

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var lastLoadedDocument: String?
        var lastNavigationRequest: OutlineNavigationRequest?

        func scrollToAnchor(_ id: String, animated: Bool) {
            let escapedID = id
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            let behavior = animated ? "smooth" : "instant"
            let script = """
            (function() {
              const target = document.getElementById('\(escapedID)');
              if (!target) { return false; }
              target.scrollIntoView({ behavior: '\(behavior)', block: 'start', inline: 'nearest' });
              return true;
            })();
            """
            webView?.evaluateJavaScript(script, completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let request = lastNavigationRequest {
                scrollToAnchor(request.id, animated: false)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard
                navigationAction.navigationType == .linkActivated,
                let url = navigationAction.request.url,
                let scheme = url.scheme?.lowercased(),
                ["http", "https"].contains(scheme)
            else {
                decisionHandler(.allow)
                return
            }

            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.setAccessibilityIdentifier("detail.webPreview")
        context.coordinator.webView = webView
        update(webView: webView, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        update(webView: nsView, coordinator: context.coordinator)
    }

    private func update(webView: WKWebView, coordinator: Coordinator) {
        let fullDocument = HTMLPreviewRenderer.document(for: html, colorScheme: colorScheme)

        if coordinator.lastLoadedDocument != fullDocument {
            coordinator.lastLoadedDocument = fullDocument
            webView.loadHTMLString(fullDocument, baseURL: baseURL)
        }

        if abs(webView.pageZoom - zoomLevel) > 0.001 {
            webView.pageZoom = zoomLevel
        }

        if coordinator.lastNavigationRequest != navigationRequest {
            coordinator.lastNavigationRequest = navigationRequest
            if let navigationRequest {
                coordinator.scrollToAnchor(navigationRequest.id, animated: true)
            }
        }
    }
}
