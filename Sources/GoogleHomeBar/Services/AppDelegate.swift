import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var onReopenRequested: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep the menu bar utility alive even when transient system popovers, AutoFill UI,
        // or the detached Google Home window close.
        ProcessInfo.processInfo.disableAutomaticTermination("GoogleHomeBar menu bar utility")
        ProcessInfo.processInfo.disableSuddenTermination()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            onReopenRequested?()
        }
        return true
    }
}
