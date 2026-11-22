import AppKit
import SwiftUI

/// AppKit-managed singleton window for the detachable Google Home view so closing it
/// never triggers SwiftUI's `Window` scene last-window auto-termination.
@MainActor
final class DetachedWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private weak var coordinator: AppCoordinator?

    func show(coordinator: AppCoordinator) {
        self.coordinator = coordinator

        if let existing = window {
            coordinator.isDetachedWindowOpen = true
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: DetachedHomeWindowView(coordinator: coordinator))
        hosting.sizingOptions = []

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "Google Home"
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        win.isOpaque = false
        win.backgroundColor = .clear
        win.contentViewController = hosting
        win.setContentSize(NSSize(width: 980, height: 680))
        win.minSize = NSSize(width: 440, height: 560)
        win.maxSize = NSSize(width: 1160, height: 960)
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self

        self.window = win
        coordinator.isDetachedWindowOpen = true
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        coordinator?.isDetachedWindowOpen = false
    }
}
