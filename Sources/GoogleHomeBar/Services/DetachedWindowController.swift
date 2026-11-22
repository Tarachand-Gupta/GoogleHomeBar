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
            contentRect: NSRect(x: 0, y: 0, width: 1020, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Google Home"
        win.contentViewController = hosting
        win.setContentSize(NSSize(width: 1020, height: 700))
        win.minSize = NSSize(width: 720, height: 500)
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
