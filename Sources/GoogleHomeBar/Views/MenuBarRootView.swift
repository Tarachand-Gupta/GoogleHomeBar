import AppKit
import GoogleHomeBarCore
import SwiftUI

struct MenuBarRootView: View {
    @Bindable var coordinator: AppCoordinator

    var body: some View {
        let size = coordinator.settings.popoverSize.dimensions
        VStack(spacing: 0) {
            headerBar
            Divider()

            Group {
                if coordinator.selectedTab == .settings {
                    SettingsTabView(coordinator: coordinator)
                } else if !coordinator.accessEvaluation.isAllowed {
                    WiFiBlockedView(coordinator: coordinator)
                } else {
                    switch coordinator.selectedTab {
                    case .home:
                        GoogleHomeDashboardView(coordinator: coordinator, isDetachedHost: false)
                    case .cast:
                        CastDevicesView(coordinator: coordinator)
                    case .web:
                        GoogleHomeTabView(coordinator: coordinator, isDetachedHost: false)
                    case .settings:
                        SettingsTabView(coordinator: coordinator)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footerBar
        }
        .frame(width: size.width, height: size.height)
        .background(.windowBackground)
        .background {
            if !coordinator.isDetachedWindowOpen
                && coordinator.selectedTab != .web
                && coordinator.webController.authState != .signedOut {
                PersistentWebViewHost(
                    webView: coordinator.webController.webView,
                    zoom: coordinator.settings.webPageZoom
                )
                .opacity(0.001)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .onAppear {
            coordinator.wifiMonitor.refreshSnapshot()
            if coordinator.accessEvaluation.isAllowed {
                coordinator.webController.loadIfNeeded()
                if coordinator.wifiMonitor.snapshot.isOnWiFi {
                    coordinator.castManager.startBrowsing()
                }
                if coordinator.webController.authState == .signedIn {
                    Task { await coordinator.homeManager.refreshTraits(silent: true) }
                }
            }
        }
    }

    private var headerBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tint)
                    Text("Google Home")
                        .font(.system(size: 13, weight: .semibold))
                }

                networkPill

                Spacer()

                Button {
                    coordinator.refreshAll()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help("Refresh Google Home Devices (⌘R)")
                .keyboardShortcut("r", modifiers: .command)

                Button {
                    coordinator.openDetachedWindow()
                } label: {
                    Image(systemName: "macwindow.on.rectangle")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Open in Window")
                .help("Open in Resizable Window")
            }

            HStack(spacing: 4) {
                tabButton(.home, badgeCount: coordinator.homeManager.devicesInSelectedStructure.count)
                tabButton(.cast, badgeCount: coordinator.castManager.devices.count)
                tabButton(.web)
                tabButton(.settings)
            }
            .padding(3)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func tabButton(_ tab: AppTab, badgeCount: Int? = nil) -> some View {
        let isSelected = coordinator.selectedTab == tab
        return Button {
            coordinator.selectedTab = tab
            if (tab == .home || tab == .web) && coordinator.accessEvaluation.isAllowed {
                coordinator.webController.loadIfNeeded()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11, weight: .medium))
                Text(tab.title)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                if let badgeCount, badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            isSelected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.1),
                            in: Capsule()
                        )
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                isSelected ? Color(nsColor: .controlBackgroundColor) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .shadow(color: isSelected ? .black.opacity(0.08) : .clear, radius: 1, y: 0.5)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
    }

    private var networkPill: some View {
        let (dotColor, labelText): (Color, String) = {
            switch coordinator.accessEvaluation {
            case .allowed(let reason):
                return (.green, reason)
            case .blockedNoWiFi:
                return (.red, coordinator.settings.wifiGatingMode == .alwaysActive ? "Offline" : "No Wi-Fi")
            case .blockedAwayFromHome:
                return (.orange, "Away")
            }
        }()

        return HStack(spacing: 5) {
            Circle()
                .fill(dotColor)
                .frame(width: 6.5, height: 6.5)
            Text(labelText)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 140, alignment: .leading)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .foregroundStyle(.secondary)
    }

    private var footerBar: some View {
        HStack(spacing: 8) {
            if coordinator.sessionOverrideActive {
                Label("Override active", systemImage: "lock.open.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
                Button("Re-lock") {
                    coordinator.sessionOverrideActive = false
                }
                .buttonStyle(.link)
                .font(.system(size: 10.5))
            } else if coordinator.webController.authState == .signedIn {
                Text("Google Home · Live")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            } else if let ip = coordinator.wifiMonitor.snapshot.localIPv4Address {
                Text("Online · \(ip)")
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.tertiary)
            } else {
                Text("Connecting…")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if coordinator.castManager.activePlaybackCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .font(.system(size: 10))
                    Text("\(coordinator.castManager.activePlaybackCount) playing")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .foregroundStyle(.tint)
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

struct WiFiBlockedView: View {
    @Bindable var coordinator: AppCoordinator

    var body: some View {
        VStack(spacing: 14) {
            Spacer()

            switch coordinator.accessEvaluation {
            case .blockedNoWiFi:
                Image(systemName: "wifi.slash")
                    .font(.system(size: 38))
                    .foregroundStyle(.secondary)

                Text(coordinator.settings.wifiGatingMode == .alwaysActive ? "No Internet Connection" : "Connect to Wi-Fi")
                    .font(.headline)

                Text("Google Home controls activate automatically as soon as your Mac connects to the internet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 290)

                Button("Check Connection Now") {
                    coordinator.wifiMonitor.refreshSnapshot()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

            case .blockedAwayFromHome(let current, let expected):
                Image(systemName: "house.and.flag")
                    .font(.system(size: 38))
                    .foregroundStyle(.orange)

                Text("Away from Home Wi-Fi")
                    .font(.headline)

                VStack(spacing: 4) {
                    if let current {
                        Text("Current network: \(current)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let expected {
                        Text("Home network: \(expected)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                HStack(spacing: 10) {
                    Button("Unlock for Session") {
                        coordinator.sessionOverrideActive = true
                        coordinator.webController.loadIfNeeded()
                        if coordinator.wifiMonitor.snapshot.isOnWiFi {
                            coordinator.castManager.startBrowsing()
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Network Settings") {
                        coordinator.selectedTab = .settings
                    }
                    .buttonStyle(.bordered)
                }

            case .allowed:
                EmptyView()
            }

            Spacer()
        }
        .padding(24)
    }
}
