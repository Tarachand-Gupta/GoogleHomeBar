import AppKit
import SwiftUI
import WebKit

/// Mounts a single shared `WKWebView` inside SwiftUI without recreating it across popover closes
/// or when moving between the menu bar popover and the detached window.
struct PersistentWebViewHost: NSViewRepresentable {
    let webView: WKWebView
    let zoom: Double
    var onDetach: (() -> Void)?

    func makeNSView(context: Context) -> WebViewContainerNSView {
        let container = WebViewContainerNSView()
        container.onDetach = onDetach
        container.attach(webView)
        return container
    }

    func updateNSView(_ container: WebViewContainerNSView, context: Context) {
        container.onDetach = onDetach
        container.attach(webView)
        if abs(webView.pageZoom - zoom) > 0.005 {
            webView.pageZoom = zoom
        }
    }

    static func dismantleNSView(_ nsView: WebViewContainerNSView, coordinator: ()) {
        nsView.detachIfOwned()
    }
}

final class WebViewContainerNSView: NSView {
    private weak var ownedWebView: WKWebView?
    var onDetach: (() -> Void)?

    func attach(_ webView: WKWebView) {
        ownedWebView = webView
        guard webView.superview !== self else { return }
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func detachIfOwned() {
        if let webView = ownedWebView, webView.superview === self {
            webView.removeFromSuperview()
            onDetach?()
        }
    }
}
