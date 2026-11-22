import Foundation
import Testing
@testable import GoogleHomeBarCore

@Suite("WebView Host Ownership Arbitration")
struct WebViewHostArbitratorTests {
    @Test("Background keep-alive update during animated tab switch cannot steal WKWebView from visible Web tab")
    func backgroundUpdateDoesNotStealFromVisibleTab() {
        var arb = WebViewHostArbitrator()
        let bgHost = UUID()
        let webTabHost = UUID()

        // 1. Popover opens on Devices tab: background keep-alive owns the WebView
        #expect(arb.register(hostId: bgHost, priority: .backgroundKeepAlive) == bgHost)

        // 2. User switches to Web tab (withAnimation): Web tab mounts while background host is still alive
        #expect(arb.register(hostId: webTabHost, priority: .visiblePopover) == webTabHost)

        // 3. SwiftUI calls updateNSView on the exiting background host during spring transition
        #expect(arb.register(hostId: bgHost, priority: .backgroundKeepAlive) == webTabHost)

        // 4. Exiting background host dismantles: visible Web tab STILL owns the WebView
        #expect(arb.unregister(hostId: bgHost) == webTabHost)
        #expect(arb.activeOwnerId == webTabHost)
    }

    @Test("Leaving Web tab returns WKWebView ownership to background keep-alive host automatically")
    func leavingWebTabRestoresKeepAlive() {
        var arb = WebViewHostArbitrator()
        let bgHost = UUID()
        let webTabHost = UUID()

        arb.register(hostId: bgHost, priority: .backgroundKeepAlive)
        #expect(arb.register(hostId: webTabHost, priority: .visiblePopover) == webTabHost)

        // User switches from Web back to Devices; GoogleHomeTabView dismantles
        #expect(arb.unregister(hostId: webTabHost) == bgHost)
        #expect(arb.activeOwnerId == bgHost)
    }

    @Test("Detached window visible Web tab preempts popover and hands ownership back on close")
    func detachedWindowPreemptsPopoverAndRestores() {
        var arb = WebViewHostArbitrator()
        let popoverBg = UUID()
        let popoverWeb = UUID()
        let windowWeb = UUID()

        arb.register(hostId: popoverBg, priority: .backgroundKeepAlive)
        #expect(arb.register(hostId: popoverWeb, priority: .visiblePopover) == popoverWeb)

        // Detached window opens on Web tab
        #expect(arb.register(hostId: windowWeb, priority: .visibleDetachedWindow) == windowWeb)

        // Popover updates while detached window is open -> detached window keeps ownership
        #expect(arb.register(hostId: popoverWeb, priority: .visiblePopover) == windowWeb)

        // Detached window closes -> popover Web tab immediately reclaims ownership
        #expect(arb.unregister(hostId: windowWeb) == popoverWeb)
    }

    @Test("Rapid repeated tab cycling always leaves visible Web tab in control")
    func rapidTabCycling() {
        var arb = WebViewHostArbitrator()
        let bgHost = UUID()
        arb.register(hostId: bgHost, priority: .backgroundKeepAlive)

        var lastWeb: UUID?
        for _ in 0..<10 {
            let nextWeb = UUID()
            #expect(arb.register(hostId: nextWeb, priority: .visiblePopover) == nextWeb)
            if let prev = lastWeb {
                #expect(arb.unregister(hostId: prev) == nextWeb)
            }
            // Background keep-alive updates interleaved with transitions
            #expect(arb.register(hostId: bgHost, priority: .backgroundKeepAlive) == nextWeb)
            lastWeb = nextWeb
        }
        #expect(arb.activeOwnerId == lastWeb)
        #expect(arb.registeredCount == 2)
    }
}
