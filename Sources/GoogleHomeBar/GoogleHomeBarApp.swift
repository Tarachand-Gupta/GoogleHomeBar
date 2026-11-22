import AppKit
import SwiftUI

@main
struct GoogleHomeBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var coordinator: AppCoordinator

    init() {
        let shouldOpenWindow = CommandLine.arguments.contains("--open-window")
        let shouldOpenPopover = CommandLine.arguments.contains("--open-popover")
        let isDemo = CommandLine.arguments.contains("--demo")
        let isDemoSignedOut = CommandLine.arguments.contains("--demo-signed-out")
        let coord = AppCoordinator(isDemoMode: isDemo)
        _coordinator = State(initialValue: coord)
        Task { @MainActor in
            if isDemoSignedOut {
                coord.webController.setSignedOutPreviewOnly()
            }
            if let delegate = NSApplication.shared.delegate as? AppDelegate {
                delegate.onReopenRequested = {
                    coord.openDetachedWindow()
                }
            }
            if shouldOpenWindow {
                coord.openDetachedWindow()
            } else if shouldOpenPopover {
                Self.openPopoverPreviewWindow(coordinator: coord)
            }
        }
    }

    @MainActor
    private static var popoverPreviewWindow: NSWindow?

    @MainActor
    private static func openPopoverPreviewWindow(coordinator: AppCoordinator) {
        NSApp.activate(ignoringOtherApps: true)
        let hosting = NSHostingController(rootView: MenuBarRootView(coordinator: coordinator))
        let size = coordinator.settings.popoverSize.dimensions
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "GoogleHomeBar"
        win.appearance = coordinator.settings.appearanceMode.nsAppearance
        win.contentViewController = hosting
        win.setContentSize(size)
        win.center()
        win.isReleasedWhenClosed = false
        popoverPreviewWindow = win
        win.makeKeyAndOrderFront(nil)
    }

    var body: some Scene {
        MenuBarExtra(
            isInserted: Binding(
                get: { coordinator.shouldShowMenuBarIcon },
                set: { _ in }
            )
        ) {
            MenuBarRootView(coordinator: coordinator)
        } label: {
            Image(systemName: coordinator.menuBarSymbolName)
                .accessibilityLabel(coordinator.menuBarTitle)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsTabView(coordinator: coordinator)
                .frame(width: 460, height: 560)
                .preferredColorScheme(coordinator.settings.appearanceMode.colorScheme)
                .background {
                    WindowAppearanceSync(appearance: coordinator.settings.appearanceMode.nsAppearance)
                }
        }
    }
}
