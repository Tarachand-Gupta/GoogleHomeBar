import GoogleHomeBarCore
import SwiftUI

struct DetachedHomeWindowView: View {
    @Bindable var coordinator: AppCoordinator
    @State private var selectedDeviceId: String?

    var body: some View {
        VStack(spacing: 0) {
            windowHeader
            Divider()

            if !coordinator.accessEvaluation.isAllowed {
                WiFiBlockedView(coordinator: coordinator)
            } else {
                switch coordinator.detachedWindowMode {
                case .devices:
                    devicesSplitView
                case .cast:
                    CastDevicesView(coordinator: coordinator)
                case .web:
                    GoogleHomeTabView(coordinator: coordinator, isDetachedHost: true)
                }
            }
        }
        .frame(minWidth: 780, minHeight: 540)
        .background {
            // Keep the single WKWebView alive inside the visible window when showing native views
            // so WebKit never occlusion-throttles the Google Home session bridge.
            if coordinator.detachedWindowMode != .web && coordinator.webController.authState != .signedOut {
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

    private var windowHeader: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "house.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tint)
                Text("Google Home")
                    .font(.system(size: 14, weight: .semibold))
            }

            Spacer()

            Picker("View", selection: $coordinator.detachedWindowMode) {
                Text("Devices (\(coordinator.homeManager.devicesInSelectedStructure.count))")
                    .tag(DetachedWindowMode.devices)
                Text("Cast (\(coordinator.castManager.devices.count))")
                    .tag(DetachedWindowMode.cast)
                Text("Web")
                    .tag(DetachedWindowMode.web)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)

            Spacer()

            Button {
                coordinator.refreshAll()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.bar)
    }

    private var devicesSplitView: some View {
        Group {
            if coordinator.webController.authState == .signedOut {
                GoogleHomeDashboardView(
                    coordinator: coordinator,
                    isDetachedHost: true,
                    externalSelection: $selectedDeviceId
                )
            } else {
                HSplitView {
                    GoogleHomeDashboardView(
                        coordinator: coordinator,
                        isDetachedHost: true,
                        externalSelection: $selectedDeviceId
                    )
                    .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)

                    detailInspectorPane
                        .frame(minWidth: 340, idealWidth: 400, maxWidth: 480, maxHeight: .infinity)
                        .background(Color(nsColor: .windowBackgroundColor))
                }
            }
        }
    }

    @ViewBuilder
    private var detailInspectorPane: some View {
        if let devId = selectedDeviceId,
           let device = coordinator.homeManager.device(id: devId) {
            GoogleHomeDeviceDetailView(
                device: device,
                homeManager: coordinator.homeManager,
                showBackButton: false
            )
        } else {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("Full Device Controls")
                    .font(.headline)
                Text("Hold any device tile — or click its sliders icon — to control brightness, RGB color, temperature, fan speed, and modes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
                Spacer()
            }
            .padding(24)
        }
    }
}
