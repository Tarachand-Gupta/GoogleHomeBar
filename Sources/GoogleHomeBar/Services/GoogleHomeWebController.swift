import AppKit
import Foundation
import Observation
import os
import WebKit

enum GoogleHomeSection: String, CaseIterable, Identifiable {
    case home

    var id: String { rawValue }

    var title: String { "Home" }
    var icon: String { "house.fill" }
    var url: URL { URL(string: "https://home.google.com/")! }
}

enum GoogleHomeAuthState: Equatable {
    case loading
    case signedOut
    case signedIn
}

struct FoyerRPCResult: Sendable {
    let ok: Bool
    let status: Int
    let body: String
    let error: String?
}

@Observable
@MainActor
final class GoogleHomeWebController: NSObject {
    // Standard macOS Safari UA so Google Sign-In works cleanly inside WKWebView.
    private static let safariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15"

    // macOS WKWebView requires Associated Domains (AASA) owned by the Relying Party for Passkeys.
    // On accounts.google.com, report platform Passkeys unavailable so Google offers Password / 2FA cleanly.
    private static let googleSignInPasskeyFallbackScript = """
    (function() {
      if (window.location.hostname !== 'accounts.google.com') return;
      try {
        if (window.PublicKeyCredential) {
          PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable = function() {
            return Promise.resolve(false);
          };
          PublicKeyCredential.isConditionalMediationAvailable = function() {
            return Promise.resolve(false);
          };
          if (typeof PublicKeyCredential.getClientCapabilities === 'function') {
            PublicKeyCredential.getClientCapabilities = function() {
              return Promise.resolve({});
            };
          }
        }
        if (navigator.credentials && typeof navigator.credentials.get === 'function') {
          var originalGet = navigator.credentials.get.bind(navigator.credentials);
          navigator.credentials.get = function(options) {
            if (options && options.publicKey) {
              return Promise.reject(new DOMException('Passkeys require Safari or an associated domain.', 'NotSupportedError'));
            }
            return originalGet(options);
          };
        }
      } catch (e) {}
    })();
    """

    // Authenticated Google Home Foyer bridge running strictly inside home.google.com's own origin.
    // Captures GetHomeGraph / GetTraits responses and forwards GetTraits / UpdateTraits RPCs
    // using the page's live Google session headers without ever persisting tokens to disk.
    private static let homeFoyerBridgeScript = """
    (function() {
      if (window.location.hostname !== 'home.google.com') return;

      var capturedHeaders = {};
      var lastHomeGraphRequest = null;

      function post(msg) {
        try { window.webkit.messageHandlers.homeBridge.postMessage(msg); } catch (e) {}
      }
      post({ type: 'bridgeReady', href: window.location.href });

      var origOpen = XMLHttpRequest.prototype.open;
      var origSetHeader = XMLHttpRequest.prototype.setRequestHeader;
      var origSend = XMLHttpRequest.prototype.send;

      XMLHttpRequest.prototype.open = function(method, url) {
        this._ghbUrl = String(url || '');
        this._ghbMethod = String(method || 'GET');
        this._ghbHeaders = {};
        return origOpen.apply(this, arguments);
      };

      XMLHttpRequest.prototype.setRequestHeader = function(k, v) {
        if (this._ghbHeaders && this._ghbUrl && this._ghbUrl.indexOf('googlehomefoyer-pa.clients6.google.com') !== -1) {
          this._ghbHeaders[k] = v;
        }
        return origSetHeader.apply(this, arguments);
      };

      XMLHttpRequest.prototype.send = function(body) {
        var self = this;
        var url = this._ghbUrl || '';
        if (url.indexOf('googlehomefoyer') !== -1) {
          // Keep session RPC headers in memory only.
          var hdrs = this._ghbHeaders || {};
          Object.keys(hdrs).forEach(function(k) {
            if (k.toLowerCase() !== 'content-type' && k.toLowerCase() !== 'x-server-timeout') {
              capturedHeaders[k] = hdrs[k];
            }
          });
          if (url.indexOf('GetHomeGraph') !== -1 && typeof body === 'string') {
            lastHomeGraphRequest = body;
          }
          this.addEventListener('load', function() {
            var txt = '';
            try {
              if (self.responseType === '' || self.responseType === 'text') {
                txt = self.responseText || '';
              } else if (self.response instanceof ArrayBuffer) {
                txt = new TextDecoder('utf-8').decode(new Uint8Array(self.response));
              }
            } catch (e) {}
            if (self.status === 200 && txt.length > 0) {
              if (url.indexOf('GetHomeGraph') !== -1) {
                post({ type: 'homeGraph', raw: txt });
              } else if (url.indexOf('GetTraits') !== -1 || url.indexOf('UpdateTraits') !== -1) {
                post({ type: 'traits', raw: txt });
              }
            }
          });
        }
        return origSend.apply(this, arguments);
      };

      async function sha1Hex(text) {
        var buf = new TextEncoder().encode(text);
        var digest = await crypto.subtle.digest('SHA-1', buf);
        return Array.from(new Uint8Array(digest)).map(function(b) {
          return b.toString(16).padStart(2, '0');
        }).join('');
      }

      function readCookie(name) {
        var parts = (document.cookie || '').split(';');
        for (var i = 0; i < parts.length; i++) {
          var p = parts[i].trim();
          if (p.indexOf(name + '=') === 0) return p.slice(name.length + 1);
        }
        return null;
      }

      async function freshAuthHeader() {
        var sapisid = readCookie('SAPISID') || readCookie('__Secure-3PAPISID');
        if (!sapisid) return capturedHeaders['Authorization'] || capturedHeaders['authorization'] || null;
        var ts = Math.floor(Date.now() / 1000);
        var origin = 'https://home.google.com';
        var hash = await sha1Hex(ts + ' ' + sapisid + ' ' + origin);
        var p1 = readCookie('__Secure-1PAPISID');
        var p3 = readCookie('__Secure-3PAPISID');
        var parts = ['SAPISIDHASH ' + ts + '_' + hash];
        if (p1) {
          var h1 = await sha1Hex(ts + ' ' + p1 + ' ' + origin);
          parts.push('SAPISID1PHASH ' + ts + '_' + h1);
        }
        if (p3) {
          var h3 = await sha1Hex(ts + ' ' + p3 + ' ' + origin);
          parts.push('SAPISID3PHASH ' + ts + '_' + h3);
        }
        return parts.join(' ');
      }

      async function callFoyerRPC(rpcPath, bodyString) {
        if (!capturedHeaders['X-Goog-Api-Key'] && !capturedHeaders['x-goog-api-key']) {
          return { ok: false, status: 0, body: '', error: 'Google Home session is still initializing.' };
        }
        var url = 'https://googlehomefoyer-pa.clients6.google.com/$rpc/' + rpcPath;
        var auth = await freshAuthHeader();
        return await new Promise(function(resolve) {
          var xhr = new XMLHttpRequest();
          xhr.open('POST', url, true);
          xhr.withCredentials = true;
          xhr.setRequestHeader('Content-Type', 'application/json+protobuf');
          Object.keys(capturedHeaders).forEach(function(k) {
            if (k.toLowerCase() === 'authorization') return;
            xhr.setRequestHeader(k, capturedHeaders[k]);
          });
          if (auth) {
            xhr.setRequestHeader('Authorization', auth);
          }
          xhr.timeout = 12000;
          xhr.onload = function() {
            resolve({
              ok: xhr.status >= 200 && xhr.status < 300,
              status: xhr.status,
              body: xhr.responseText || '',
              error: xhr.status >= 200 && xhr.status < 300 ? null : ('HTTP ' + xhr.status)
            });
          };
          xhr.onerror = function() {
            resolve({ ok: false, status: 0, body: '', error: 'Network error calling Google Home.' });
          };
          xhr.ontimeout = function() {
            resolve({ ok: false, status: 0, body: '', error: 'Request timed out.' });
          };
          xhr.send(bodyString);
        });
      }

      window.__ghbBridge = {
        isReady: function() {
          return Boolean(capturedHeaders['X-Goog-Api-Key'] || capturedHeaders['x-goog-api-key']);
        },
        callRPC: callFoyerRPC,
        refreshHomeGraph: function() {
          var body = lastHomeGraphRequest || '[null,null,null,null,null,null,[["user.invite.unrestricted"],["structure.update.subscription_nestaware","routine.create","structure.update.membership","routine.read"],["device.execute.camera_onoff","device.read.camera_history","device.read.camera_notifications"]],1,null,[1,2],null,null,null,null,[1,2,3,4,5,6,7,8,9,10,11,12,14,15,16,17,18,19,20]]';
          return callFoyerRPC('google.internal.home.foyer.v1.StructuresService/GetHomeGraph', body);
        }
      };
    })();
    """

    private let logger = Logger(subsystem: "com.playground.GoogleHomeBar", category: "HomeBridge")
    let webView: WKWebView

    private(set) var currentURL: URL?
    private(set) var pageTitle: String = "Google Home"
    private(set) var isLoading = false
    private(set) var estimatedProgress: Double = 0
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var lastError: String?
    private(set) var hasLoadedInitially = false
    private(set) var authState: GoogleHomeAuthState = .loading
    var isInteractiveSignInActive = false

    private static let directGoogleSignInURL =
        URL(string: "https://accounts.google.com/ServiceLogin?continue=https%3A%2F%2Fhome.google.com%2F")!

    var onHomeGraphPayload: ((Data) -> Void)?
    var onTraitsPayload: ((Data) -> Void)?

    private var progressObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?
    private var loadingObservation: NSKeyValueObservation?
    private var backObservation: NSKeyValueObservation?
    private var forwardObservation: NSKeyValueObservation?

    private var popupWindows: [ObjectIdentifier: NSWindow] = [:]

    var activeSection: GoogleHomeSection? {
        guard let host = currentURL?.host?.lowercased(), host.contains("home.google.com") else {
            return nil
        }
        return .home
    }

    var isOnGoogleSignIn: Bool {
        let host = currentURL?.host?.lowercased() ?? ""
        let path = currentURL?.path.lowercased() ?? ""
        return host == "accounts.google.com"
            || (host == "home.google.com" && (
                path.hasPrefix("/welcome")
                    || path.hasPrefix("/intl/")
                    || path.hasPrefix("/us/")
                    || path.hasPrefix("/gb/")
                    || path.hasPrefix("/in/")
            ))
    }

    init(initialZoom: Double = 0.85) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.userContentController.addUserScript(
            WKUserScript(
                source: Self.googleSignInPasskeyFallbackScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        config.userContentController.addUserScript(
            WKUserScript(
                source: Self.homeFoyerBridgeScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )

        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 680), configuration: config)
        wv.customUserAgent = Self.safariUserAgent
        wv.allowsBackForwardNavigationGestures = true
        wv.pageZoom = initialZoom
        self.webView = wv

        super.init()

        wv.configuration.userContentController.add(self, name: "homeBridge")
        wv.navigationDelegate = self
        wv.uiDelegate = self
        setupObservers()
    }

    func loadIfNeeded() {
        guard !hasLoadedInitially, authState != .signedOut else { return }
        hasLoadedInitially = true
        navigate(to: .home)
    }

    func beginInteractiveSignIn() {
        lastError = nil
        hasLoadedInitially = true
        authState = .signedOut
        isInteractiveSignInActive = true
        webView.load(URLRequest(url: Self.directGoogleSignInURL))
    }

    func cancelInteractiveSignIn() {
        isInteractiveSignInActive = false
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
    }

    func navigate(to section: GoogleHomeSection) {
        lastError = nil
        hasLoadedInitially = true
        if authState != .signedIn {
            authState = .loading
        }
        webView.load(URLRequest(url: section.url))
    }

    func reload() {
        lastError = nil
        if authState == .signedOut && !isInteractiveSignInActive {
            beginInteractiveSignIn()
        } else if webView.url == nil || webView.url?.absoluteString == "about:blank" {
            navigate(to: .home)
        } else {
            webView.reload()
        }
    }

    func goBack() {
        if webView.canGoBack {
            webView.goBack()
        }
    }

    func goForward() {
        if webView.canGoForward {
            webView.goForward()
        }
    }

    func setZoom(_ zoom: Double) {
        let clamped = min(max(zoom, 0.5), 1.5)
        if abs(webView.pageZoom - clamped) > 0.005 {
            webView.pageZoom = clamped
        }
    }

    func openInDefaultBrowser() {
        let target = currentURL ?? GoogleHomeSection.home.url
        NSWorkspace.shared.open(target)
    }

    func setSignedOutPreviewOnly() {
        authState = .signedOut
        isInteractiveSignInActive = false
        hasLoadedInitially = true
    }

    func clearSessionAndSignOut() {
        authState = .signedOut
        isInteractiveSignInActive = false
        hasLoadedInitially = true
        lastError = nil
        pageTitle = "Signed Out"
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)

        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()

        // 1. Delete all Google / Nest cookies directly from WKHTTPCookieStore (including session cookies).
        store.httpCookieStore.getAllCookies { cookies in
            for cookie in cookies {
                let domain = cookie.domain.lowercased()
                if domain.contains("google") || domain.contains("gstatic") || domain.contains("nest") || domain.contains("youtube") {
                    store.httpCookieStore.delete(cookie)
                }
            }
        }

        // 2. Purge all persistent site storage / caches / IndexedDB records for Google & Nest domains.
        store.fetchDataRecords(ofTypes: types) { records in
            let googleRecords = records.filter { record in
                let name = record.displayName.lowercased()
                return name.contains("google") || name.contains("gstatic") || name.contains("nest")
            }
            store.removeData(ofTypes: types, for: googleRecords) {
                // Stay cleanly in .signedOut so our custom Sign-In gate is shown instead of home.google.com/welcome.
            }
        }
    }

    // MARK: - Authenticated Foyer RPC Execution

    func callFoyerRPC(path: String, bodyJSON: String) async -> FoyerRPCResult {
        do {
            let result = try await webView.callAsyncJavaScript(
                """
                if (!window.__ghbBridge) {
                  return { ok: false, status: 0, body: '', error: 'Google Home session not loaded.' };
                }
                return await window.__ghbBridge.callRPC(rpcPath, rpcBody);
                """,
                arguments: ["rpcPath": path, "rpcBody": bodyJSON],
                in: nil,
                contentWorld: .page
            )
            return Self.parseJSResult(result)
        } catch {
            return FoyerRPCResult(ok: false, status: 0, body: "", error: error.localizedDescription)
        }
    }

    func refreshHomeGraphRPC() async -> FoyerRPCResult {
        do {
            let result = try await webView.callAsyncJavaScript(
                """
                if (!window.__ghbBridge || !window.__ghbBridge.isReady()) {
                  return { ok: false, status: 0, body: '', error: 'Not ready' };
                }
                return await window.__ghbBridge.refreshHomeGraph();
                """,
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
            return Self.parseJSResult(result)
        } catch {
            return FoyerRPCResult(ok: false, status: 0, body: "", error: error.localizedDescription)
        }
    }

    private static func parseJSResult(_ raw: Any?) -> FoyerRPCResult {
        guard let dict = raw as? [String: Any] else {
            return FoyerRPCResult(ok: false, status: 0, body: "", error: "Empty response from Google Home.")
        }
        let ok = (dict["ok"] as? Bool) ?? false
        let status = (dict["status"] as? Int) ?? 0
        let body = (dict["body"] as? String) ?? ""
        let error = dict["error"] as? String
        return FoyerRPCResult(ok: ok, status: status, body: body, error: error)
    }

    private func setupObservers() {
        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.estimatedProgress = self.webView.estimatedProgress
            }
        }
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentURL = self.webView.url
                if self.isOnGoogleSignIn {
                    self.authState = .signedOut
                }
            }
        }
        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let title = self.webView.title ?? "Google Home"
                self.pageTitle = title.isEmpty ? "Google Home" : title
            }
        }
        loadingObservation = webView.observe(\.isLoading, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isLoading = self.webView.isLoading
            }
        }
        backObservation = webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.canGoBack = self.webView.canGoBack
            }
        }
        forwardObservation = webView.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.canGoForward = self.webView.canGoForward
            }
        }
    }
}

extension GoogleHomeWebController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "homeBridge",
              let dict = message.body as? [String: Any],
              let type = dict["type"] as? String else {
            return
        }

        switch type {
        case "bridgeReady":
            let href = (dict["href"] as? String) ?? ""
            logger.debug("homeBridge ready on \(href, privacy: .public)")
        case "homeGraph":
            guard let raw = dict["raw"] as? String, let data = raw.data(using: .utf8) else { return }
            logger.info("homeBridge received GetHomeGraph (\(data.count, privacy: .public)B)")
            authState = .signedIn
            isInteractiveSignInActive = false
            onHomeGraphPayload?(data)
        case "traits":
            guard let raw = dict["raw"] as? String, let data = raw.data(using: .utf8) else { return }
            logger.info("homeBridge received Traits (\(data.count, privacy: .public)B)")
            authState = .signedIn
            isInteractiveSignInActive = false
            onTraitsPayload?(data)
        default:
            break
        }
    }
}

extension GoogleHomeWebController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        lastError = nil
        if isOnGoogleSignIn {
            authState = .signedOut
            return
        }
        // Detect unauthenticated Google Home marketing page (no SAPISID cookie present on home.google.com).
        if let host = webView.url?.host?.lowercased(), host == "home.google.com", authState != .signedIn {
            webView.evaluateJavaScript("Boolean(document.cookie && (document.cookie.indexOf('SAPISID=') !== -1 || document.cookie.indexOf('__Secure-3PAPISID=') !== -1))") { [weak self] result, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let hasAuthCookie = result as? Bool, !hasAuthCookie, self.authState != .signedIn {
                        self.authState = .signedOut
                    }
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleLoadError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleLoadError(error)
    }

    private func handleLoadError(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }
        lastError = error.localizedDescription
    }
}

extension GoogleHomeWebController: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        let popupWebView = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 680), configuration: configuration)
        popupWebView.customUserAgent = Self.safariUserAgent
        popupWebView.navigationDelegate = self
        popupWebView.uiDelegate = self

        let width = windowFeatures.width?.doubleValue ?? 520
        let height = windowFeatures.height?.doubleValue ?? 680
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: max(width, 420), height: max(height, 560)),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Google Sign-In"
        window.contentView = popupWebView
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let key = ObjectIdentifier(popupWebView)
        popupWindows[key] = window
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.popupWindows.removeValue(forKey: key)
            }
        }
        return popupWebView
    }

    func webViewDidClose(_ webView: WKWebView) {
        let key = ObjectIdentifier(webView)
        if let window = popupWindows.removeValue(forKey: key) {
            window.close()
        }
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
    ) {
        let host = origin.host.lowercased()
        if host == "home.google.com" || host.hasSuffix(".google.com") {
            decisionHandler(.grant)
        } else {
            decisionHandler(.deny)
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "Google Home"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completionHandler()
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "Google Home"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }
}
