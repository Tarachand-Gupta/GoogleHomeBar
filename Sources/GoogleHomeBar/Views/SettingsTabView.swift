import AppKit
import CoreLocation
import SwiftUI
import GoogleHomeBarCore

struct SettingsTabView: View {
    @Bindable var coordinator: AppCoordinator
    @Bindable var settings: AppSettings
    var bottomInsetForDock: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @State private var newSSIDText = ""
    @State private var showSignOutConfirm = false

    init(coordinator: AppCoordinator, bottomInsetForDock: Bool = false) {
        self.coordinator = coordinator
        self.settings = coordinator.settings
        self.bottomInsetForDock = bottomInsetForDock
    }

    private var isModern: Bool {
        settings.uiStyle == .modern
    }

    var body: some View {
        let palette = ModernPalette(colorScheme: colorScheme)

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if isModern {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Settings")
                                .font(.system(size: 19, weight: .bold, design: .rounded))
                                .foregroundStyle(palette.textPrimary)
                            Text("Switch UX style, Light/Dark theme, and network rules")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(palette.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.bottom, 2)
                }

                interfaceThemeSection(palette: palette)
                wifiSection(palette: palette)
                appearanceSection(palette: palette)
                systemSection(palette: palette)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, bottomInsetForDock ? 78 : 16)
        }
        .background(isModern ? palette.canvas : Color.clear)
    }

    // MARK: - Interface Style (Modern / Classic) & Theme (System / Light / Dark)

    private func interfaceThemeSection(palette: ModernPalette) -> some View {
        settingsCard(title: "Interface & Theme", icon: "paintbrush.pointed.fill", palette: palette) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Control Experience")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Picker("Control Experience", selection: $settings.uiStyle) {
                    ForEach(UIStylePreset.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(settings.uiStyle.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Appearance")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Picker("Appearance", selection: $settings.appearanceMode) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    // MARK: - Network & Home Wi-Fi

    private func wifiSection(palette: ModernPalette) -> some View {
        settingsCard(title: "Internet & Home Network", icon: "wifi", palette: palette) {
            Picker("Activation", selection: $settings.wifiGatingMode) {
                ForEach(WiFiGatingMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(coordinator.settings.wifiGatingMode.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Current Wi-Fi")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(currentWiFiSummary)
                        .font(.caption.monospacedDigit())
                }

                if coordinator.wifiMonitor.snapshot.currentSSID == nil && coordinator.wifiMonitor.snapshot.isOnWiFi {
                    HStack(spacing: 8) {
                        Text("macOS hides Wi-Fi names without Location access. Home devices and subnet matching still work without it.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        if coordinator.wifiMonitor.locationAuthStatus == .notDetermined {
                            Button("Allow SSID") {
                                coordinator.wifiMonitor.requestLocationPermissionForSSID()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                }
            }

            if coordinator.settings.wifiGatingMode == .homeWiFiOnly {
                Divider()

                HStack(spacing: 8) {
                    Button {
                        coordinator.saveCurrentAsHomeNetwork()
                    } label: {
                        Label("Save Current Wi-Fi as Home", systemImage: "house.badge.plus")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!coordinator.wifiMonitor.snapshot.isOnWiFi)

                    if !coordinator.settings.savedHomeSSIDs.isEmpty
                        || coordinator.settings.savedHomeSubnet != nil
                        || !coordinator.settings.savedHomeDeviceIDs.isEmpty {
                        Button("Clear") {
                            coordinator.clearSavedHomeNetwork()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                HStack(spacing: 6) {
                    TextField("Add Home Wi-Fi SSID manually", text: $newSSIDText)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .onSubmit(addEnteredSSID)
                    Button("Add", action: addEnteredSSID)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(newSSIDText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if !coordinator.settings.savedHomeSSIDs.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Saved Home SSIDs")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                        ForEach(coordinator.settings.savedHomeSSIDs, id: \.self) { ssid in
                            HStack {
                                Label(ssid, systemImage: "wifi")
                                    .font(.caption)
                                Spacer()
                                Button {
                                    coordinator.settings.removeHomeSSID(ssid)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                HStack(spacing: 12) {
                    if let subnet = coordinator.settings.savedHomeSubnet {
                        Label("Home LAN: \(subnet).x", systemImage: "network")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if !coordinator.settings.savedHomeDeviceIDs.isEmpty {
                        Label("\(coordinator.settings.savedHomeDeviceIDs.count) home Cast devices", systemImage: "hifispeaker.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            Toggle("Hide menu bar icon when away / off Wi-Fi", isOn: $settings.hideIconWhenOffWiFi)
                .font(.caption)
        }
    }

    // MARK: - Menu Bar & Web View

    private func appearanceSection(palette: ModernPalette) -> some View {
        settingsCard(title: "Menu Bar & Web View", icon: "macwindow", palette: palette) {
            HStack {
                Text("Popover Size")
                    .font(.caption)
                Spacer()
                Picker("", selection: $settings.popoverSize) {
                    ForEach(PopoverSizePreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
                .controlSize(.small)
            }

            HStack {
                Text("Default Tab")
                    .font(.caption)
                Spacer()
                Picker("", selection: $settings.defaultTab) {
                    Text("Devices").tag(AppTab.home)
                    Text("Cast").tag(AppTab.cast)
                    Text("Web").tag(AppTab.web)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 210)
                .controlSize(.small)
            }

            HStack {
                Text("Google Home Zoom")
                    .font(.caption)
                Spacer()
                Slider(
                    value: Binding(
                        get: { coordinator.settings.webPageZoom },
                        set: { val in
                            coordinator.settings.webPageZoom = val
                            coordinator.webController.setZoom(val)
                        }
                    ),
                    in: 0.65...1.25,
                    step: 0.05
                )
                .frame(width: 130)
                .controlSize(.small)
                Text("\(Int((coordinator.settings.webPageZoom * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .frame(width: 38, alignment: .trailing)
            }
        }
    }

    // MARK: - System & Google Account

    private func systemSection(palette: ModernPalette) -> some View {
        settingsCard(title: "System & Google Account", icon: "gearshape", palette: palette) {
            Toggle(
                "Launch GoogleHomeBar at Login",
                isOn: Binding(
                    get: { coordinator.settings.launchAtLoginEnabled },
                    set: { coordinator.settings.setLaunchAtLogin($0) }
                )
            )
            .font(.caption)

            if let error = coordinator.settings.launchAtLoginError {
                Text("Launch at Login requires running from the bundled .app (\(error)).")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            Divider()

            HStack {
                Button("Sign Out of Google Home", role: .destructive) {
                    showSignOutConfirm = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .confirmationDialog(
                    "Sign out of Google Home?",
                    isPresented: $showSignOutConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Sign Out", role: .destructive) {
                        coordinator.signOut()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This clears saved Google cookies in GoogleHomeBar and reloads the sign-in screen.")
                }

                Spacer()

                Button("Quit App") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var currentWiFiSummary: String {
        let snap = coordinator.wifiMonitor.snapshot
        guard snap.isOnWiFi else { return "Disconnected" }
        var parts: [String] = []
        if let ssid = snap.currentSSID, !ssid.isEmpty {
            parts.append(ssid)
        } else {
            parts.append("Connected")
        }
        if let ip = snap.localIPv4Address {
            parts.append(ip)
        }
        return parts.joined(separator: " · ")
    }

    private func addEnteredSSID() {
        let trimmed = newSSIDText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        coordinator.settings.addHomeSSID(trimmed)
        newSSIDText = ""
    }

    private func settingsCard<Content: View>(
        title: String,
        icon: String,
        palette: ModernPalette,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let radius: CGFloat = isModern ? 16 : 14
        return VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(isModern ? palette.textPrimary : .primary)

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(AdaptiveSettingsCardSurface(isModern: isModern, radius: radius, palette: palette))
    }
}

private struct AdaptiveSettingsCardSurface: ViewModifier {
    let isModern: Bool
    let radius: CGFloat
    let palette: ModernPalette

    func body(content: Content) -> some View {
        if isModern {
            content
                .background(palette.card, in: RoundedRectangle(cornerRadius: radius))
                .overlay(
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(palette.glassRimHighlight, lineWidth: 1)
                )
                .shadow(color: palette.cardShadow, radius: 8, y: 3)
        } else {
            content
                .liquidGlassSurface(in: RoundedRectangle(cornerRadius: radius), shadowRadius: 5)
        }
    }
}
