import GoogleHomeBarCore
import SwiftUI

struct DetachedHomeWindowView: View {
    @Bindable var coordinator: AppCoordinator
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var selectedDeviceId: String?
    @State private var unusedInlineSelection: String?

    private var isModern: Bool {
        coordinator.settings.uiStyle == .modern
    }

    private var effectiveColorScheme: ColorScheme {
        coordinator.settings.appearanceMode.colorScheme ?? systemColorScheme
    }

    var body: some View {
        let palette = ModernPalette(colorScheme: effectiveColorScheme)

        VStack(spacing: 0) {
            if isModern {
                modernWindowHeader(palette: palette)
            } else {
                classicWindowHeader
                Divider()
            }

            if coordinator.detachedWindowMode == .settings {
                SettingsTabView(coordinator: coordinator)
            } else if !coordinator.accessEvaluation.isAllowed {
                WiFiBlockedView(coordinator: coordinator)
            } else {
                switch coordinator.detachedWindowMode {
                case .devices:
                    devicesSplitView(palette: palette)
                case .cast:
                    CastDevicesView(coordinator: coordinator)
                case .web:
                    GoogleHomeTabView(coordinator: coordinator, isDetachedHost: true)
                case .settings:
                    SettingsTabView(coordinator: coordinator)
                }
            }
        }
        .frame(minWidth: 780, minHeight: 560)
        .background {
            if isModern {
                palette.canvas
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
        .preferredColorScheme(coordinator.settings.appearanceMode.colorScheme)
        .background {
            WindowAppearanceSync(appearance: coordinator.settings.appearanceMode.nsAppearance)
        }
        .background {
            // Keep a low-priority background host registered while the detached window is open so
            // WebKit stays live on native views and cleanly yields ownership to GoogleHomeTabView on Web tab.
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
            ensureModernSelectionIfReady()
        }
        .onChange(of: coordinator.homeManager.devices) { _, _ in
            ensureModernSelectionIfReady()
        }
    }

    private func ensureModernSelectionIfReady() {
        guard isModern else { return }
        if let current = selectedDeviceId, coordinator.homeManager.device(id: current) != nil {
            return
        }
        selectedDeviceId = coordinator.homeManager.devicesInSelectedStructure.first?.id
    }

    // MARK: - Modern Detached Header

    private func modernWindowHeader(palette: ModernPalette) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(palette.accentGradient)
                        .frame(width: 26, height: 26)
                    Image(systemName: "house.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white)
                }
                Text("Google Home")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
            }

            Spacer()

            LiquidGlassGroup(spacing: 6) {
                HStack(spacing: 4) {
                    modernModePill(.devices, label: "Devices", count: coordinator.homeManager.devicesInSelectedStructure.count, palette: palette)
                    modernModePill(.cast, label: "Cast", count: coordinator.castManager.devices.count, palette: palette)
                    modernModePill(.web, label: "Web", count: nil, palette: palette)
                    modernModePill(.settings, label: "Settings", count: nil, palette: palette)
                }
                .padding(4)
                .liquidGlassSurface(in: Capsule(), interactive: true, shadowRadius: 6)
            }

            Spacer()

            LiquidGlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                        coordinator.settings.appearanceMode = (effectiveColorScheme == .dark) ? .light : .dark
                    } label: {
                        Image(systemName: effectiveColorScheme == .dark ? "sun.max.fill" : "moon.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                            .frame(width: 30, height: 30)
                            .liquidGlassSurface(in: Circle(), interactive: true, shadowRadius: 4)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.liquidGlassCircle)
                    .accessibilityLabel(effectiveColorScheme == .dark ? "Switch to Light Mode" : "Switch to Dark Mode")
                    .help(effectiveColorScheme == .dark ? "Switch to Light Mode" : "Switch to Dark Mode")

                    Button {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                        coordinator.refreshAll()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11.5, weight: .semibold))
                            Text("Refresh")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .liquidGlassSurface(in: Capsule(), interactive: true, shadowRadius: 4)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.liquidGlassCapsule)
                    .keyboardShortcut("r", modifiers: .command)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(palette.canvas)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.divider)
                .frame(height: 1)
        }
    }

    private func modernModePill(
        _ mode: DetachedWindowMode,
        label: String,
        count: Int?,
        palette: ModernPalette
    ) -> some View {
        let selected = coordinator.detachedWindowMode == mode
        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                coordinator.detachedWindowMode = mode
            }
        } label: {
            HStack(spacing: 5) {
                Text(label)
                    .font(.system(size: 12, weight: selected ? .semibold : .medium))
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            selected ? Color.white.opacity(0.24) : palette.card,
                            in: Capsule()
                        )
                }
            }
            .foregroundStyle(selected ? Color.white : palette.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                if selected {
                    Capsule()
                        .fill(palette.accentGradient)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.75))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.liquidGlassCapsule)
    }

    // MARK: - Classic Detached Header (Native macOS Liquid Glass)

    private var classicWindowHeader: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "house.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tint)
                Text("Google Home")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }

            Spacer()

            Picker("View", selection: $coordinator.detachedWindowMode) {
                Text("Devices (\(coordinator.homeManager.devicesInSelectedStructure.count))")
                    .tag(DetachedWindowMode.devices)
                Text("Cast (\(coordinator.castManager.devices.count))")
                    .tag(DetachedWindowMode.cast)
                Text("Web")
                    .tag(DetachedWindowMode.web)
                Text("Settings")
                    .tag(DetachedWindowMode.settings)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 380)

            Spacer()

            Button {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                coordinator.refreshAll()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .liquidGlassSurface(in: Capsule(), interactive: true)
                    .contentShape(Capsule())
            }
            .buttonStyle(.liquidGlassCapsule)
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: - Devices Split View (Modern or Classic)

    private func devicesSplitView(palette: ModernPalette) -> some View {
        Group {
            if coordinator.webController.authState == .signedOut {
                if isModern {
                    ModernDashboardView(
                        coordinator: coordinator,
                        isDetachedHost: true,
                        externalSelection: $selectedDeviceId,
                        inlineSelectedDeviceId: $unusedInlineSelection
                    )
                } else {
                    GoogleHomeDashboardView(
                        coordinator: coordinator,
                        isDetachedHost: true,
                        externalSelection: $selectedDeviceId
                    )
                }
            } else {
                HSplitView {
                    if isModern {
                        ModernDashboardView(
                            coordinator: coordinator,
                            isDetachedHost: true,
                            externalSelection: $selectedDeviceId,
                            inlineSelectedDeviceId: $unusedInlineSelection
                        )
                        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        GoogleHomeDashboardView(
                            coordinator: coordinator,
                            isDetachedHost: true,
                            externalSelection: $selectedDeviceId
                        )
                        .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                    }

                    detailInspectorPane(palette: palette)
                        .frame(minWidth: 360, idealWidth: 410, maxWidth: 480, maxHeight: .infinity)
                        .background(isModern ? palette.canvas : Color.clear)
                }
            }
        }
    }

    @ViewBuilder
    private func detailInspectorPane(palette: ModernPalette) -> some View {
        if let devId = selectedDeviceId,
           let device = coordinator.homeManager.device(id: devId) {
            if isModern {
                ModernDeviceDetailView(
                    device: device,
                    allDevices: coordinator.homeManager.devicesInSelectedStructure,
                    homeManager: coordinator.homeManager,
                    showBackButton: false,
                    onSelectDevice: { nextId in selectedDeviceId = nextId }
                )
            } else {
                GoogleHomeDeviceDetailView(
                    device: device,
                    homeManager: coordinator.homeManager,
                    showBackButton: false
                )
            }
        } else {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 32))
                    .foregroundStyle(isModern ? palette.textSecondary : Color.secondary)
                Text("Full Device Controls")
                    .font(.headline)
                    .foregroundStyle(isModern ? palette.textPrimary : Color.primary)
                Text("Click any device card — or its ••• button — to control brightness, RGB color, temperature, fan speed, and modes.")
                    .font(.caption)
                    .foregroundStyle(isModern ? palette.textSecondary : Color.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isModern ? palette.canvas : Color.clear)
        }
    }
}
