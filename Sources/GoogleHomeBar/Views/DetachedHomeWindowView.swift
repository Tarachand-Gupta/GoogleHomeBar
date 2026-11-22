import GoogleHomeBarCore
import SwiftUI

struct DetachedHomeWindowView: View {
    @Bindable var coordinator: AppCoordinator
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var selectedDeviceId: String?
    @State private var compactInlineDeviceId: String?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        let initial = coordinator.settings.uiStyle == .modern
            ? coordinator.homeManager.devicesInSelectedStructure.first?.id
            : nil
        _selectedDeviceId = State(initialValue: initial)
    }

    private var isModern: Bool {
        coordinator.settings.uiStyle == .modern
    }

    private var effectiveColorScheme: ColorScheme {
        coordinator.settings.appearanceMode.colorScheme ?? systemColorScheme
    }

    var body: some View {
        let palette = ModernPalette(colorScheme: effectiveColorScheme)

        GeometryReader { geo in
            let windowWidth = geo.size.width
            let isCompact = windowWidth < 800

            VStack(spacing: 0) {
                if isModern {
                    modernWindowHeader(palette: palette, windowWidth: windowWidth)
                } else {
                    classicWindowHeader(windowWidth: windowWidth)
                    Divider().opacity(0.45)
                }

                Group {
                    if coordinator.detachedWindowMode == .settings {
                        SettingsTabView(coordinator: coordinator)
                    } else if !coordinator.accessEvaluation.isAllowed {
                        WiFiBlockedView(coordinator: coordinator)
                    } else {
                        switch coordinator.detachedWindowMode {
                        case .devices:
                            devicesBody(palette: palette, windowWidth: windowWidth, isCompact: isCompact)
                        case .cast:
                            CastDevicesView(coordinator: coordinator)
                        case .web:
                            GoogleHomeTabView(coordinator: coordinator, isDetachedHost: true)
                        case .settings:
                            SettingsTabView(coordinator: coordinator)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 440, minHeight: 560)
        .background {
            if isModern {
                palette.canvas
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
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
            if !coordinator.homeManager.isDemoMode && coordinator.accessEvaluation.isAllowed {
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

    // MARK: - Unified Modern Header (Native Traffic Lights Pulled Directly Inside Header)

    private func modernWindowHeader(palette: ModernPalette, windowWidth: CGFloat) -> some View {
        let showBrandText = windowWidth >= 660
        let showRefreshText = windowWidth >= 620
        let showCounts = windowWidth >= 520

        return HStack(spacing: 10) {
            if showBrandText {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(palette.accentGradient)
                            .frame(width: 24, height: 24)
                        Image(systemName: "house.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.white)
                    }
                    Text("Google Home")
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            LiquidGlassGroup(spacing: 6) {
                HStack(spacing: 3) {
                    modernModePill(
                        .devices,
                        label: "Devices",
                        count: showCounts ? coordinator.homeManager.devicesInSelectedStructure.count : nil,
                        palette: palette
                    )
                    modernModePill(
                        .cast,
                        label: "Cast",
                        count: showCounts ? coordinator.castManager.devices.count : nil,
                        palette: palette
                    )
                    modernModePill(.web, label: "Web", count: nil, palette: palette)
                    modernModePill(.settings, label: "Settings", count: nil, palette: palette)
                }
                .padding(3.5)
                .liquidGlassSurface(in: Capsule(), interactive: true, shadowRadius: 6)
            }

            Spacer(minLength: 4)

            LiquidGlassGroup(spacing: 6) {
                HStack(spacing: 6) {
                    Button {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                        coordinator.settings.appearanceMode = (effectiveColorScheme == .dark) ? .light : .dark
                    } label: {
                        Image(systemName: effectiveColorScheme == .dark ? "sun.max.fill" : "moon.fill")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                            .frame(width: 28, height: 28)
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
                            if showRefreshText {
                                Text("Refresh")
                                    .font(.system(size: 11.5, weight: .semibold))
                            }
                        }
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, showRefreshText ? 11 : 0)
                        .frame(minWidth: 28, minHeight: 28)
                        .liquidGlassSurface(in: Capsule(), interactive: true, shadowRadius: 4)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.liquidGlassCapsule)
                    .accessibilityLabel("Refresh")
                    .keyboardShortcut("r", modifiers: .command)
                }
            }
        }
        // Leading inset reserves room for the native macOS traffic lights inside this header bar.
        .padding(.leading, 78)
        .padding(.trailing, 14)
        .frame(height: 46)
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
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                coordinator.detachedWindowMode = mode
            }
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            selected ? Color.white.opacity(0.24) : palette.card,
                            in: Capsule()
                        )
                }
            }
            .foregroundStyle(selected ? Color.white : palette.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5.5)
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

    // MARK: - Unified Classic Header (Traffic Lights Inside Header + Native Liquid Glass)

    private func classicWindowHeader(windowWidth: CGFloat) -> some View {
        let showBrandText = windowWidth >= 660
        let showRefreshText = windowWidth >= 620

        return HStack(spacing: 10) {
            if showBrandText {
                HStack(spacing: 7) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.tint)
                    Text("Google Home")
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

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
            .frame(maxWidth: 360)

            Spacer(minLength: 4)

            Button {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                coordinator.refreshAll()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11.5, weight: .semibold))
                    if showRefreshText {
                        Text("Refresh")
                            .font(.caption.weight(.semibold))
                    }
                }
                .padding(.horizontal, showRefreshText ? 11 : 0)
                .frame(minWidth: 28, minHeight: 28)
                .liquidGlassSurface(in: Capsule(), interactive: true)
                .contentShape(Capsule())
            }
            .buttonStyle(.liquidGlassCapsule)
            .accessibilityLabel("Refresh")
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.leading, 78)
        .padding(.trailing, 14)
        .frame(height: 46)
    }

    // MARK: - Responsive Devices Body (Single-Pane < 800px, Bounded Split >= 800px)

    @ViewBuilder
    private func devicesBody(palette: ModernPalette, windowWidth: CGFloat, isCompact: Bool) -> some View {
        if coordinator.webController.authState == .signedOut {
            GoogleSignInGateView(coordinator: coordinator, isDetachedHost: true)
        } else if isCompact {
            // Compact mobile-style single pane: Dashboard expands inline into Device Detail with Back button
            if isModern {
                ModernDashboardView(
                    coordinator: coordinator,
                    isDetachedHost: true,
                    externalSelection: nil,
                    inlineSelectedDeviceId: $compactInlineDeviceId
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GoogleHomeDashboardView(
                    coordinator: coordinator,
                    isDetachedHost: true,
                    externalSelection: nil
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            // Wide desktop split view with bounded container widths on both panes
            let inspectorWidth = min(420, max(360, windowWidth * 0.39))

            HStack(spacing: 0) {
                if isModern {
                    ModernDashboardView(
                        coordinator: coordinator,
                        isDetachedHost: true,
                        externalSelection: $selectedDeviceId,
                        inlineSelectedDeviceId: $compactInlineDeviceId
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    GoogleHomeDashboardView(
                        coordinator: coordinator,
                        isDetachedHost: true,
                        externalSelection: $selectedDeviceId
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Rectangle()
                    .fill(isModern ? palette.divider : Color.primary.opacity(0.10))
                    .frame(width: 1)

                detailInspectorPane(palette: palette)
                    .frame(width: inspectorWidth)
                    .frame(maxHeight: .infinity)
                    .background(isModern ? palette.canvas : Color.clear)
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
                Text("Click any device card to control brightness, RGB color, temperature, fan speed, and modes.")
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
