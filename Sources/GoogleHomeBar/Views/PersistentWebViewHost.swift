import AppKit
import GoogleHomeBarCore
import SwiftUI
import WebKit

/// Coordinates attaching the single shared `WKWebView` to whichever live container currently has
/// highest `WebViewHostPriority`. Immune to SwiftUI `withAnimation` enter/exit ordering races.
@MainActor
final class SharedWebViewAttachmentManager {
    static let shared = SharedWebViewAttachmentManager()

    private var arbitrator = WebViewHostArbitrator()
    private var containers: [UUID: WeakContainerBox] = [:]
    private weak var managedWebView: WKWebView?

    private struct WeakContainerBox {
        weak var view: WebViewContainerNSView?
    }

    func register(
        container: WebViewContainerNSView,
        webView: WKWebView,
        priority: WebViewHostPriority,
        zoom: Double
    ) {
        managedWebView = webView
        pruneDeadContainers()
        containers[container.hostId] = WeakContainerBox(view: container)
        arbitrator.register(hostId: container.hostId, priority: priority)
        reconcile(webView: webView, zoom: zoom)
    }

    func unregister(containerId: UUID) {
        containers.removeValue(forKey: containerId)
        pruneDeadContainers()
        arbitrator.unregister(hostId: containerId)
        if let webView = managedWebView {
            reconcile(webView: webView, zoom: nil)
        }
    }

    private func reconcile(webView: WKWebView, zoom: Double?) {
        pruneDeadContainers()
        guard let ownerId = arbitrator.activeOwnerId,
              let owner = containers[ownerId]?.view else {
            if webView.superview != nil {
                webView.removeFromSuperview()
            }
            return
        }

        owner.attachNow(webView)
        if let zoom, abs(webView.pageZoom - zoom) > 0.005 {
            webView.pageZoom = zoom
        }
    }

    private func pruneDeadContainers() {
        let deadIds = containers.compactMap { id, box in
            box.view == nil ? id : nil
        }
        for id in deadIds {
            containers.removeValue(forKey: id)
            arbitrator.unregister(hostId: id)
        }
    }
}

/// Mounts a single shared `WKWebView` inside SwiftUI without recreating it across tab switches,
/// popover closes, or when moving between the menu bar popover and the detached window.
struct PersistentWebViewHost: NSViewRepresentable {
    let webView: WKWebView
    let zoom: Double
    var priority: WebViewHostPriority = .visiblePopover
    var onDetach: (() -> Void)?

    func makeNSView(context: Context) -> WebViewContainerNSView {
        let container = WebViewContainerNSView()
        container.onDetach = onDetach
        SharedWebViewAttachmentManager.shared.register(
            container: container,
            webView: webView,
            priority: priority,
            zoom: zoom
        )
        return container
    }

    func updateNSView(_ container: WebViewContainerNSView, context: Context) {
        container.onDetach = onDetach
        SharedWebViewAttachmentManager.shared.register(
            container: container,
            webView: webView,
            priority: priority,
            zoom: zoom
        )
    }

    static func dismantleNSView(_ nsView: WebViewContainerNSView, coordinator: ()) {
        let hadWebView = nsView.currentlyOwnsWebView
        SharedWebViewAttachmentManager.shared.unregister(containerId: nsView.hostId)
        if hadWebView {
            nsView.onDetach?()
        }
    }
}

final class WebViewContainerNSView: NSView {
    let hostId = UUID()
    private weak var ownedWebView: WKWebView?
    var onDetach: (() -> Void)?

    var currentlyOwnsWebView: Bool {
        guard let webView = ownedWebView else { return false }
        return webView.superview === self
    }

    func attachNow(_ webView: WKWebView) {
        ownedWebView = webView
        webView.isHidden = false
        webView.alphaValue = 1.0
        if webView.superview !== self {
            webView.removeFromSuperview()
            webView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(webView)
            NSLayoutConstraint.activate([
                webView.leadingAnchor.constraint(equalTo: leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: trailingAnchor),
                webView.topAnchor.constraint(equalTo: topAnchor),
                webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
        webView.needsDisplay = true
    }

    override func layout() {
        super.layout()
        if let webView = ownedWebView, webView.superview === self {
            webView.needsDisplay = true
        }
    }
}
