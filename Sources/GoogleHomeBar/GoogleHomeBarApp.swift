import AppKit
import SwiftUI

@main
struct GoogleHomeBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var coordinator: AppCoordinator

    init() {
        let coord = AppCoordinator()
        _coordinator = State(initialValue: coord)
        let shouldOpenWindow = CommandLine.arguments.contains("--open-window")
        Task { @MainActor in
            if let delegate = NSApplication.shared.delegate as? AppDelegate {
                delegate.onReopenRequested = {
                    coord.openDetachedWindow()
                }
            }
            if shouldOpenWindow {
                coord.openDetachedWindow()
            }
        }
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
                .frame(width: 460, height: 520)
        }
    }
}
