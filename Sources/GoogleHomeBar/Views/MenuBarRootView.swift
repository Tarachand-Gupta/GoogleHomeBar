import AppKit
import GoogleHomeBarCore
import SwiftUI

struct MenuBarRootView: View {
    @Bindable var coordinator: AppCoordinator
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var modernInlineDeviceId: String?
    @Namespace private var classicTabNamespace

    var body: some View {
        let size = coordinator.settings.popoverSize.dimensions
        Group {
            if coordinator.settings.uiStyle == .modern {
                modernPopoverShell
            } else {
                classicPopoverShell
            }
        }
        .frame(width: size.width, height: size.height)
        .preferredColorScheme(coordinator.settings.appearanceMode.colorScheme)
        .background {
            WindowAppearanceSync(appearance: coordinator.settings.appearanceMode.nsAppearance)
        }
        .background {
            // Keep a low-priority background host registered while the popover is open so WebKit
            // stays live on native tabs and cleanly yields ownership to GoogleHomeTabView on Web tab.
            if !coordinator.isDetachedWindowOpen {
                PersistentWebViewHost(
                    webView: coordinator.webController.webView,
                    zoom: coordinator.settings.webPageZoom,
                    priority: .backgroundKeepAlive
                )
                .opacity(0.001)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .transaction { $0.animation = nil }
            }
        }
        .background {
            // Preserve Cmd+Q shortcut even with the bottom Quit bar removed.
            Button("") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
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

    // MARK: - Modern UX Shell (No top tab bar, no bottom footer — floating pill dock)

    private var effectiveColorScheme: ColorScheme {
        coordinator.settings.appearanceMode.colorScheme ?? systemColorScheme
    }

    private var modernPopoverShell: some View {
        let palette = ModernPalette(colorScheme: effectiveColorScheme)
        let showingDeviceDetail = (coordinator.selectedTab == .home && modernInlineDeviceId != nil)
        let showDock = !showingDeviceDetail

        return Group {
            if coordinator.selectedTab == .web && coordinator.accessEvaluation.isAllowed {
                VStack(spacing: 0) {
                    GoogleHomeTabView(coordinator: coordinator, isDetachedHost: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if showDock {
                        ModernFloatingNavDock(
                            selectedTab: $coordinator.selectedTab,
                            castActiveCount: coordinator.castManager.activePlaybackCount,
                            onSelect: selectModernTab
                        )
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(palette.canvas)
                    }
                }
            } else {
                ZStack(alignment: .bottom) {
                    Group {
                        if coordinator.selectedTab == .settings {
                            SettingsTabView(coordinator: coordinator, bottomInsetForDock: true)
                        } else if !coordinator.accessEvaluation.isAllowed {
                            WiFiBlockedView(coordinator: coordinator)
                        } else {
                            switch coordinator.selectedTab {
                            case .home:
                                ModernDashboardView(
                                    coordinator: coordinator,
                                    isDetachedHost: false,
                                    inlineSelectedDeviceId: $modernInlineDeviceId
                                )
                            case .cast:
                                CastDevicesView(coordinator: coordinator, bottomInsetForDock: true)
                            case .web:
                                GoogleHomeTabView(coordinator: coordinator, isDetachedHost: false)
                            case .settings:
                                SettingsTabView(coordinator: coordinator, bottomInsetForDock: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    ModernFloatingNavDock(
                        selectedTab: $coordinator.selectedTab,
                        castActiveCount: coordinator.castManager.activePlaybackCount,
                        onSelect: selectModernTab
                    )
                    .padding(.bottom, 12)
                    .offset(y: showDock ? 0 : 28)
                    .scaleEffect(showDock ? 1.0 : 0.86)
                    .opacity(showDock ? 1.0 : 0.0)
                    .allowsHitTesting(showDock)
                    .accessibilityHidden(!showDock)
                    .animation(.spring(response: 0.34, dampingFraction: 0.84), value: showDock)
                }
            }
        }
        .background(palette.canvas)
    }

    private func selectModernTab(_ tab: AppTab) {
        if tab != .home {
            modernInlineDeviceId = nil
        }
        coordinator.selectedTab = tab
        if (tab == .home || tab == .web) && coordinator.accessEvaluation.isAllowed {
            coordinator.webController.loadIfNeeded()
        }
    }

    // MARK: - Classic UX Shell (Native macOS 26/27 Liquid Glass Popover)

    private var classicPopoverShell: some View {
        VStack(spacing: 0) {
            classicHeaderBar
            Divider().opacity(0.45)

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
        }
        .background(.ultraThinMaterial)
    }

    private var classicHeaderBar: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tint)
                    Text("Google Home")
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                }

                networkPill

                Spacer()

                if coordinator.sessionOverrideActive {
                    Button("Re-lock") {
                        coordinator.sessionOverrideActive = false
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 10.5))
                }

                LiquidGlassGroup(spacing: 6) {
                    HStack(spacing: 6) {
                        Button {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                            coordinator.refreshAll()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11.5, weight: .semibold))
                                .frame(width: 26, height: 26)
                                .liquidGlassSurface(in: Circle(), interactive: true)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.liquidGlassCircle)
                        .accessibilityLabel("Refresh Devices")
                        .help("Refresh Google Home Devices (⌘R)")
                        .keyboardShortcut("r", modifiers: .command)

                        Button {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                            coordinator.openDetachedWindow()
                        } label: {
                            Image(systemName: "macwindow.on.rectangle")
                                .font(.system(size: 11.5, weight: .semibold))
                                .frame(width: 26, height: 26)
                                .liquidGlassSurface(in: Circle(), interactive: true)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.liquidGlassCircle)
                        .accessibilityLabel("Open in Window")
                        .help("Open in Resizable Window")
                    }
                }
            }

            LiquidGlassGroup(spacing: 4) {
                HStack(spacing: 4) {
                    tabButton(.home, badgeCount: coordinator.homeManager.devicesInSelectedStructure.count)
                    tabButton(.cast, badgeCount: coordinator.castManager.devices.count)
                    tabButton(.web)
                    tabButton(.settings)
                }
                .padding(4)
                .liquidGlassSurface(in: Capsule(), interactive: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 9)
    }

    private func tabButton(_ tab: AppTab, badgeCount: Int? = nil) -> some View {
        let isSelected = coordinator.selectedTab == tab
        return Button {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                coordinator.selectedTab = tab
            }
            if (tab == .home || tab == .web) && coordinator.accessEvaluation.isAllowed {
                coordinator.webController.loadIfNeeded()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(tab.title)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                if let badgeCount, badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            isSelected ? Color.white.opacity(0.24) : Color.primary.opacity(0.10),
                            in: Capsule()
                        )
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.accentColor)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.75))
                        .matchedGeometryEffect(id: "classicActiveTab", in: classicTabNamespace)
                        .shadow(color: Color.accentColor.opacity(0.28), radius: 5, y: 1.5)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.liquidGlassCapsule)
        .foregroundStyle(isSelected ? Color.white : Color.secondary)
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
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .liquidGlassSurface(in: Capsule())
        .foregroundStyle(.secondary)
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
