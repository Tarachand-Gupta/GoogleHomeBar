import AppKit
import GoogleHomeBarCore
import SwiftUI

/// Trait-driven Modern device control view: composes controls dynamically from whatever
/// Google Smart Home traits any device declares, with full-area hit targets and dimmed off-state UX.
struct ModernDeviceDetailView: View {
    let device: GoogleHomeDevice
    let allDevices: [GoogleHomeDevice]
    @Bindable var homeManager: GoogleHomeManager
    var showBackButton: Bool = true
    var onSelectDevice: ((String) -> Void)?
    var onBack: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    @State private var lightModeTab: ModernLightTab = .warm
    @State private var localBrightness: Double = 100
    @State private var localKelvin: Double = 2700
    @State private var localHue: Double = 0.08
    @State private var whiteDialSide: Double = 1.0
    @State private var localTempC: Double = 24
    @State private var localFanPercent: Double = 50
    @State private var localHumidity: Double = 50
    @State private var localOpenPercent: Double = 0
    @State private var localVolume: Double = 50
    @State private var isDraggingControl = false
    @State private var showColorPalettePopover = false

    private enum ModernLightTab: String, CaseIterable, Identifiable {
        case warm = "Warm"
        case cool = "Cool"
        case color = "Color"
        var id: String { rawValue }
    }

    private enum PrimaryHeroKind {
        case colorLight
        case brightnessOnlyLight
        case climate
        case fan
        case humidity
        case openClose
        case genericStatus
    }

    private var isPending: Bool {
        homeManager.pendingDeviceIds.contains(device.id)
    }

    private var isOn: Bool {
        device.state.isOn ?? false
    }

    /// True when the device has an OnOff power switch and is currently switched off.
    private var isPoweredOff: Bool {
        device.supportsOnOff && !isOn
    }

    /// True whenever non-power controls should be visually dimmed and non-interactive.
    private var controlsInactive: Bool {
        !device.state.isOnline || isPoweredOff
    }

    private var primaryHero: PrimaryHeroKind {
        if device.supportsColor {
            return .colorLight
        }
        if device.supportsBrightness {
            return .brightnessOnlyLight
        }
        if device.supportsTemperatureSetting {
            return .climate
        }
        if device.supportsFanSpeed && (!device.state.availableFanSpeeds.isEmpty || device.state.supportsFanSpeedPercent || device.state.currentFanSpeedPercent != nil) {
            return .fan
        }
        if device.state.humiditySetpointPercent != nil {
            return .humidity
        }
        if device.state.openPercent != nil {
            return .openClose
        }
        return .genericStatus
    }

    var body: some View {
        let palette = ModernPalette(colorScheme: colorScheme)

        VStack(spacing: 0) {
            topNavBar(palette: palette)

            if allDevices.count > 1, let onSelectDevice {
                deviceSwitcherPills(palette: palette, onSelect: onSelectDevice)
                    .padding(.bottom, 6)
            }

            ScrollView {
                VStack(spacing: 14) {
                    if !device.state.isOnline {
                        offlineBanner(palette: palette)
                    }

                    if let error = homeManager.lastError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(error)
                                .font(.caption)
                                .lineLimit(2)
                            Spacer()
                        }
                        .foregroundStyle(.orange)
                        .padding(10)
                        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                    }

                    // Primary hero control (for color lights, center power dome stays bright when off)
                    if primaryHero == .colorLight {
                        colorLightHeroSection(palette: palette)
                    } else {
                        nonColorHeroSection(palette: palette)
                            .saturation(controlsInactive ? 0.05 : 1.0)
                            .opacity(controlsInactive ? 0.42 : 1.0)
                            .disabled(controlsInactive)
                            .allowsHitTesting(!controlsInactive)
                    }

                    // Composable trait cards (work automatically for single-trait and combo devices)
                    secondaryTraitSections(palette: palette)
                        .saturation(controlsInactive ? 0.05 : 1.0)
                        .opacity(controlsInactive ? 0.42 : 1.0)
                        .disabled(controlsInactive)
                        .allowsHitTesting(!controlsInactive)
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 16)
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.22), value: controlsInactive)
            }

            // Bottom CTA bar (Turn On stays fully highlighted whenever device is online & off)
            bottomActionBar(palette: palette)
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)
                .background(palette.canvas)
        }
        .background(palette.canvas)
        .onAppear { syncLocalValues(forceMode: true) }
        .onChange(of: device.id) { _, _ in syncLocalValues(forceMode: true) }
        .onChange(of: device.state) { _, _ in
            if !isDraggingControl {
                syncLocalValues(forceMode: false)
            }
        }
    }

    // MARK: - Top Navigation Header

    private func topNavBar(palette: ModernPalette) -> some View {
        LiquidGlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                if showBackButton, let onBack {
                    Button {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                        onBack()
                    } label: {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                            .frame(width: 34, height: 34)
                            .liquidGlassSurface(in: Circle(), interactive: true, shadowRadius: 5)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.liquidGlassCircle)
                    .accessibilityLabel("Back to Devices")
                } else {
                    Color.clear.frame(width: 34, height: 34)
                }

                Spacer()

                VStack(spacing: 2) {
                    HStack(spacing: 5) {
                        Text(device.name)
                            .font(.system(size: 15.5, weight: .bold, design: .rounded))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                        if isPending {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }

                    Text(subtitleText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    Task { await homeManager.refreshTraits(for: [device.id], silent: false) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 34, height: 34)
                        .liquidGlassSurface(in: Circle(), interactive: true, shadowRadius: 5)
                        .contentShape(Circle())
                }
                .buttonStyle(.liquidGlassCircle)
                .accessibilityLabel("Refresh \(device.name)")
                .help("Refresh state from Google Home")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var subtitleText: String {
        var parts: [String] = []
        if let mfr = device.manufacturer, !mfr.isEmpty {
            parts.append(mfr.uppercased())
        }
        if let model = device.model, !model.isEmpty {
            parts.append(model)
        } else {
            parts.append(device.roomName)
        }
        return parts.joined(separator: " · ")
    }

    private func deviceSwitcherPills(palette: ModernPalette, onSelect: @escaping (String) -> Void) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(allDevices) { item in
                        let selected = item.id == device.id
                        Button {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                            onSelect(item.id)
                        } label: {
                            Text(item.name)
                                .font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                                .foregroundStyle(selected ? Color.white : palette.textSecondary)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 6)
                                .background {
                                    if selected {
                                        Capsule()
                                            .fill(palette.accentGradient)
                                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.75))
                                            .shadow(color: palette.accent.opacity(0.30), radius: 5, y: 2)
                                    }
                                }
                                .modifier(DetailGlassPillModifier(isGlass: !selected))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.liquidGlassCapsule)
                        .id(item.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
            .frame(height: 36)
            .horizontalEdgeFade(width: 18)
            .padding(.horizontal, 8)
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
            .onAppear {
                proxy.scrollTo(device.id, anchor: .center)
            }
            .onChange(of: device.id) { _, newId in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(newId, anchor: .center)
                }
            }
        }
    }

    private func offlineBanner(palette: ModernPalette) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(palette.textSecondary)
            Text("Device is currently offline in Google Home.")
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer()
        }
        .padding(11)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.border, lineWidth: 1))
    }

    // MARK: - Primary Hero Sections

    private func colorLightHeroSection(palette: ModernPalette) -> some View {
        ModernColorRingDial(
            isOn: isOn,
            isOnline: device.state.isOnline,
            supportsPowerToggle: device.supportsOnOff,
            mode: dialMode,
            kelvin: $localKelvin,
            kelvinRange: activeKelvinRange,
            hue: $localHue,
            whiteSide: $whiteDialSide,
            brightnessPercent: Int(localBrightness.rounded()),
            currentColor: currentLightDisplayColor,
            onTogglePower: {
                if device.state.isOnline && device.supportsOnOff {
                    homeManager.togglePower(deviceId: device.id)
                }
            },
            onKelvinChanged: { newK, finalCommit in
                isDraggingControl = !finalCommit
                let roundedK = Int((newK / 100.0).rounded()) * 100
                homeManager.setColorTemperature(
                    deviceId: device.id,
                    kelvin: roundedK,
                    debounced: !finalCommit
                )
            },
            onColorChanged: { rgbInt, finalCommit in
                isDraggingControl = !finalCommit
                homeManager.setColorRGB(
                    deviceId: device.id,
                    rgbInt: rgbInt,
                    debounced: !finalCommit
                )
            }
        )
        .padding(.top, 2)
    }

    @ViewBuilder
    private func nonColorHeroSection(palette: ModernPalette) -> some View {
        switch primaryHero {
        case .colorLight:
            EmptyView()
        case .brightnessOnlyLight:
            brightnessOnlyHero(palette: palette)
        case .climate:
            climateHeroSection(palette: palette)
        case .fan:
            fanHeroSection(palette: palette)
        case .humidity:
            humidityHeroSection(palette: palette)
        case .openClose:
            openCloseHeroSection(palette: palette)
        case .genericStatus:
            genericStatusHero(palette: palette)
        }
    }

    private func brightnessOnlyHero(palette: ModernPalette) -> some View {
        ModernArcControlDial(
            value: $localBrightness,
            range: 1...100,
            isOn: isOn,
            isDisabled: controlsInactive,
            accentColor: palette.accent,
            centerIcon: isOn ? "sun.max.fill" : "sun.max",
            centerValueText: isOn ? "\(Int(localBrightness.rounded()))%" : "Off",
            minLabel: "1%",
            midLabel: "50%",
            maxLabel: "100%",
            statusIcons: ["lightbulb.fill"],
            onStepMinus: {
                let next = max(1.0, localBrightness.rounded() - 10)
                localBrightness = next
                homeManager.setBrightness(deviceId: device.id, percent: Int(next), debounced: false)
            },
            onStepPlus: {
                let next = min(100.0, localBrightness.rounded() + 10)
                localBrightness = next
                homeManager.setBrightness(deviceId: device.id, percent: Int(next), debounced: false)
            },
            onValueChanged: { val, finalCommit in
                isDraggingControl = !finalCommit
                homeManager.setBrightness(
                    deviceId: device.id,
                    percent: Int(val.rounded()),
                    debounced: !finalCommit
                )
            }
        )
    }

    private func climateHeroSection(palette: ModernPalette) -> some View {
        let unit = device.state.temperatureUnit
        let minT = device.state.minTempC
        let maxT = max(device.state.maxTempC, minT + 1)

        return VStack(spacing: 11) {
            ModernArcControlDial(
                value: $localTempC,
                range: minT...maxT,
                isOn: isOn,
                isDisabled: controlsInactive,
                accentColor: acAccentColor(palette: palette),
                centerIcon: "thermometer.medium",
                centerValueText: "\(Int(localTempC.rounded()))°\(unit)",
                minLabel: "\(Int(minT.rounded()))°",
                midLabel: "\(Int(((minT + maxT) / 2.0).rounded()))°",
                maxLabel: "\(Int(maxT.rounded()))°",
                statusIcons: acModeIcons,
                onStepMinus: {
                    let next = max(minT, localTempC.rounded() - 1)
                    localTempC = next
                    homeManager.setThermostatSetpoint(deviceId: device.id, tempC: next, debounced: false)
                },
                onStepPlus: {
                    let next = min(maxT, localTempC.rounded() + 1)
                    localTempC = next
                    homeManager.setThermostatSetpoint(deviceId: device.id, tempC: next, debounced: false)
                },
                onValueChanged: { val, finalCommit in
                    isDraggingControl = !finalCommit
                    homeManager.setThermostatSetpoint(
                        deviceId: device.id,
                        tempC: val.rounded(),
                        debounced: !finalCommit
                    )
                }
            )

            // 3-Column Live Metrics Card
            HStack(spacing: 0) {
                metricCell(
                    label: "CURRENT",
                    value: device.state.ambientTempC.map { "\(Int($0.rounded()))°\(unit)" } ?? "—",
                    palette: palette
                )

                Divider()
                    .frame(height: 30)
                    .overlay(palette.divider)

                metricCell(
                    label: "TARGET",
                    value: "\(Int(localTempC.rounded()))°\(unit)",
                    palette: palette
                )

                Divider()
                    .frame(height: 30)
                    .overlay(palette.divider)

                metricCell(
                    label: device.supportsFanSpeed ? "FAN" : "STATUS",
                    value: acThirdMetricValue,
                    palette: palette
                )
            }
            .padding(.vertical, 12)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.border, lineWidth: 1))
            .shadow(color: palette.cardShadow, radius: 8, y: 3)

            if !device.state.availableThermostatModes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mode")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)

                    let modes = device.state.availableThermostatModes
                    if modes.count <= 4 {
                        HStack(spacing: 4) {
                            ForEach(modes, id: \.self) { mode in
                                thermostatModePill(mode: mode, palette: palette)
                            }
                        }
                        .padding(4)
                        .background(palette.surfaceSubtle, in: Capsule())
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], spacing: 6) {
                            ForEach(modes, id: \.self) { mode in
                                thermostatModePill(mode: mode, palette: palette)
                                    .background(
                                        (isOn && device.state.thermostatMode?.lowercased() == mode.lowercased())
                                            ? Color.clear
                                            : palette.surfaceSubtle,
                                        in: Capsule()
                                    )
                            }
                        }
                    }
                }
            }
        }
    }

    private func thermostatModePill(mode: String, palette: ModernPalette) -> some View {
        let active = isOn && device.state.thermostatMode?.lowercased() == mode.lowercased()
        return Button {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            homeManager.setThermostatMode(deviceId: device.id, mode: mode)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: ModernClimateHeroCard.modeSymbol(mode))
                    .font(.system(size: 11.5, weight: .semibold))
                Text(GoogleHomeDevice.prettyThermostatMode(mode))
                    .font(.system(size: 11.5, weight: active ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(active ? Color.white : palette.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 9)
            .background {
                if active {
                    Capsule()
                        .fill(palette.accentGradient)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.75))
                        .shadow(color: palette.accent.opacity(0.28), radius: 5, y: 2)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.liquidGlassCapsule)
        .disabled(controlsInactive)
    }

    @ViewBuilder
    private func fanHeroSection(palette: ModernPalette) -> some View {
        let speeds = device.state.availableFanSpeeds
        if speeds.count > 1 {
            let count = speeds.count
            let currentIdx = speeds.firstIndex(where: { $0.speedName == device.state.currentFanSpeed }) ?? 0
            let currentLabel = speeds.indices.contains(currentIdx) ? speeds[currentIdx].displayLabel : "1"

            VStack(spacing: 14) {
                ModernArcControlDial(
                    value: Binding(
                        get: { Double(currentIdx) },
                        set: { newVal in
                            let idx = min(max(Int(newVal.rounded()), 0), count - 1)
                            if speeds[idx].speedName != device.state.currentFanSpeed {
                                homeManager.setFanSpeed(deviceId: device.id, speedName: speeds[idx].speedName)
                            }
                        }
                    ),
                    range: 0...Double(count - 1),
                    isOn: isOn,
                    isDisabled: controlsInactive,
                    accentColor: palette.accent,
                    centerIcon: "fan.fill",
                    centerValueText: isOn ? "Speed \(currentLabel)" : "Off",
                    minLabel: speeds.first?.displayLabel ?? "1",
                    midLabel: speeds[count / 2].displayLabel,
                    maxLabel: speeds.last?.displayLabel ?? "\(count)",
                    statusIcons: ["wind", "fan"],
                    onStepMinus: {
                        let prev = max(0, currentIdx - 1)
                        homeManager.setFanSpeed(deviceId: device.id, speedName: speeds[prev].speedName)
                    },
                    onStepPlus: {
                        let next = min(count - 1, currentIdx + 1)
                        homeManager.setFanSpeed(deviceId: device.id, speedName: speeds[next].speedName)
                    },
                    onValueChanged: { newVal, finalCommit in
                        isDraggingControl = !finalCommit
                        let idx = min(max(Int(newVal.rounded()), 0), count - 1)
                        if finalCommit || speeds[idx].speedName != device.state.currentFanSpeed {
                            homeManager.setFanSpeed(deviceId: device.id, speedName: speeds[idx].speedName)
                        }
                    }
                )

                // Direct speed step pills (full-area clickable capsules)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Fan Speed")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)

                    HStack(spacing: 4) {
                        ForEach(speeds) { opt in
                            let active = isOn && device.state.currentFanSpeed == opt.speedName
                            Button {
                                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                                homeManager.setFanSpeed(deviceId: device.id, speedName: opt.speedName)
                            } label: {
                                Text(opt.displayLabel)
                                    .font(.system(size: 12.5, weight: active ? .bold : .medium).monospacedDigit())
                                    .foregroundStyle(active ? Color.white : palette.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background {
                                        if active {
                                            Capsule()
                                                .fill(palette.accentGradient)
                                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.75))
                                                .shadow(color: palette.accent.opacity(0.28), radius: 5, y: 2)
                                        }
                                    }
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.liquidGlassCapsule)
                            .disabled(controlsInactive)
                        }
                    }
                    .padding(4)
                    .background(palette.surfaceSubtle, in: Capsule())
                }
            }
        } else {
            // Continuous 0–100% fan speed hero dial
            ModernArcControlDial(
                value: $localFanPercent,
                range: 0...100,
                isOn: isOn,
                isDisabled: controlsInactive,
                accentColor: palette.accent,
                centerIcon: "fan.fill",
                centerValueText: isOn ? "\(Int(localFanPercent.rounded()))%" : "Off",
                minLabel: "0%",
                midLabel: "50%",
                maxLabel: "100%",
                statusIcons: ["wind", "fan"],
                onStepMinus: {
                    let next = max(0, localFanPercent.rounded() - 10)
                    localFanPercent = next
                    homeManager.setFanSpeedPercent(deviceId: device.id, percent: Int(next), debounced: false)
                },
                onStepPlus: {
                    let next = min(100, localFanPercent.rounded() + 10)
                    localFanPercent = next
                    homeManager.setFanSpeedPercent(deviceId: device.id, percent: Int(next), debounced: false)
                },
                onValueChanged: { val, finalCommit in
                    isDraggingControl = !finalCommit
                    homeManager.setFanSpeedPercent(
                        deviceId: device.id,
                        percent: Int(val.rounded()),
                        debounced: !finalCommit
                    )
                }
            )
        }
    }

    private func humidityHeroSection(palette: ModernPalette) -> some View {
        let minH = Double(device.state.minHumidityPercent)
        let maxH = Double(max(device.state.maxHumidityPercent, device.state.minHumidityPercent + 5))

        return VStack(spacing: 12) {
            ModernArcControlDial(
                value: $localHumidity,
                range: minH...maxH,
                isOn: device.supportsOnOff ? isOn : true,
                isDisabled: controlsInactive,
                accentColor: palette.accent,
                centerIcon: "humidity.fill",
                centerValueText: "\(Int(localHumidity.rounded()))%",
                minLabel: "\(Int(minH))%",
                midLabel: "\(Int(((minH + maxH) / 2.0).rounded()))%",
                maxLabel: "\(Int(maxH))%",
                statusIcons: ["drop.fill"],
                onStepMinus: {
                    let next = max(minH, localHumidity.rounded() - 5)
                    localHumidity = next
                    homeManager.setHumiditySetpoint(deviceId: device.id, percent: Int(next), debounced: false)
                },
                onStepPlus: {
                    let next = min(maxH, localHumidity.rounded() + 5)
                    localHumidity = next
                    homeManager.setHumiditySetpoint(deviceId: device.id, percent: Int(next), debounced: false)
                },
                onValueChanged: { val, finalCommit in
                    isDraggingControl = !finalCommit
                    homeManager.setHumiditySetpoint(
                        deviceId: device.id,
                        percent: Int(val.rounded()),
                        debounced: !finalCommit
                    )
                }
            )

            if let ambient = device.state.humidityAmbientPercent {
                HStack(spacing: 0) {
                    metricCell(label: "CURRENT", value: "\(ambient)%", palette: palette)
                    Divider().frame(height: 28).overlay(palette.divider)
                    metricCell(label: "TARGET", value: "\(Int(localHumidity.rounded()))%", palette: palette)
                }
                .padding(.vertical, 12)
                .background(palette.card, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.border, lineWidth: 1))
                .shadow(color: palette.cardShadow, radius: 8, y: 3)
            }
        }
    }

    private func openCloseHeroSection(palette: ModernPalette) -> some View {
        VStack(spacing: 12) {
            ModernArcControlDial(
                value: $localOpenPercent,
                range: 0...100,
                isOn: localOpenPercent > 0,
                isDisabled: controlsInactive,
                accentColor: palette.accent,
                centerIcon: localOpenPercent > 0 ? device.deviceType.sfSymbol : device.deviceType.offSymbol,
                centerValueText: "\(Int(localOpenPercent.rounded()))%",
                minLabel: "0%",
                midLabel: "50%",
                maxLabel: "100%",
                statusIcons: ["arrow.up.and.down"],
                onStepMinus: {
                    let next = max(0, localOpenPercent.rounded() - 10)
                    localOpenPercent = next
                    homeManager.setOpenPercent(deviceId: device.id, percent: Int(next), debounced: false)
                },
                onStepPlus: {
                    let next = min(100, localOpenPercent.rounded() + 10)
                    localOpenPercent = next
                    homeManager.setOpenPercent(deviceId: device.id, percent: Int(next), debounced: false)
                },
                onValueChanged: { val, finalCommit in
                    isDraggingControl = !finalCommit
                    homeManager.setOpenPercent(
                        deviceId: device.id,
                        percent: Int(val.rounded()),
                        debounced: !finalCommit
                    )
                }
            )

            HStack(spacing: 4) {
                ForEach([("Close", 0), ("Half", 50), ("Open", 100)], id: \.1) { title, pct in
                    let active = abs(Int(localOpenPercent.rounded()) - pct) <= 5
                    Button {
                        localOpenPercent = Double(pct)
                        homeManager.setOpenPercent(deviceId: device.id, percent: pct, debounced: false)
                    } label: {
                        Text(title)
                            .font(.system(size: 12, weight: active ? .semibold : .medium))
                            .foregroundStyle(active ? Color.white : palette.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background {
                                if active {
                                    Capsule()
                                        .fill(palette.accentGradient)
                                        .shadow(color: palette.accent.opacity(0.28), radius: 5, y: 2)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(controlsInactive)
                }
            }
            .padding(4)
            .background(palette.surfaceSubtle, in: Capsule())
        }
    }

    /// Clean sculpted status emblem for Switches, Plugs, Outlets, Locks, Speakers, TVs, Vacuums, Sensors.
    private func genericStatusHero(palette: ModernPalette) -> some View {
        let activeHighlight = !controlsInactive && (isOn || device.state.isRunning == true || device.state.isLocked == false)
        let accent = activeHighlight ? palette.accent : palette.textMuted

        return VStack(spacing: 12) {
            ZStack {
                if activeHighlight {
                    Circle()
                        .fill(palette.accent.opacity(palette.isDark ? 0.24 : 0.16))
                        .frame(width: 132, height: 132)
                        .blur(radius: 14)
                }

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [palette.domeTop, palette.domeBottom],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 116, height: 116)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                activeHighlight ? palette.accent.opacity(0.45) : palette.border,
                                lineWidth: activeHighlight ? 2 : 1.5
                            )
                    )
                    .shadow(color: palette.domeShadow, radius: 14, y: 6)

                VStack(spacing: 6) {
                    Image(systemName: activeHighlight ? device.deviceType.sfSymbol : device.deviceType.offSymbol)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(accent)

                    Text(device.statusSummary)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 10)
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Composable Secondary Trait Sections (Work on ANY Device Automatically)

    @ViewBuilder
    private func secondaryTraitSections(palette: ModernPalette) -> some View {
        VStack(spacing: 14) {
            // Brightness bar (shown when light has a Color Ring Dial; brightness-only already uses an arc dial)
            if primaryHero == .colorLight && device.supportsBrightness {
                brightnessSliderSection(palette: palette)
            }

            // Warm / Cool / Color tabs + preset swatches (only for traits actually supported by this light)
            if primaryHero == .colorLight {
                colorControlsSection(palette: palette)
            }

            // Fan speed slider/pills on combo devices (e.g. AC with fan speed, or ceiling fan with light)
            if primaryHero != .fan && device.supportsFanSpeed {
                if !device.state.availableFanSpeeds.isEmpty {
                    modernFanSpeedSliderCard(palette: palette)
                } else if device.state.supportsFanSpeedPercent || device.state.currentFanSpeedPercent != nil {
                    continuousFanSpeedCard(palette: palette)
                }
            }

            // Humidity card if not already primary hero
            if primaryHero != .humidity && device.state.humiditySetpointPercent != nil {
                secondaryHumidityCard(palette: palette)
            }

            // Open/Close card if not already primary hero
            if primaryHero != .openClose, let openPct = device.state.openPercent {
                secondaryOpenCloseCard(openPct: openPct, palette: palette)
            }

            // Volume & Mute card (Speakers, TVs, Soundbars)
            if device.state.volumePercent != nil {
                volumeCard(palette: palette)
            }

            // Lock / Unlock card
            if let isLocked = device.state.isLocked {
                lockCard(isLocked: isLocked, palette: palette)
            }

            // Start / Stop / Pause card (Vacuums, Washers, Dishwashers, Coffee Makers)
            if let isRunning = device.state.isRunning {
                startStopCard(isRunning: isRunning, palette: palette)
            }

            // Dynamic Modes from Google Home (works for every manufacturer automatically)
            extraModesSection(palette: palette)

            // Dynamic Toggles from Google Home (full-row clickable)
            extraTogglesSection(palette: palette)
        }
    }

    private func brightnessSliderSection(palette: ModernPalette) -> some View {
        VStack(spacing: 6) {
            ModernTrackSlider(
                value: $localBrightness,
                in: 1...100,
                accent: palette.accent,
                isDisabled: controlsInactive
            ) { editing in
                isDraggingControl = editing
                if !editing {
                    homeManager.setBrightness(
                        deviceId: device.id,
                        percent: Int(localBrightness.rounded()),
                        debounced: false
                    )
                }
            }
            .onChange(of: localBrightness) { _, newVal in
                if isDraggingControl {
                    homeManager.setBrightness(
                        deviceId: device.id,
                        percent: Int(newVal.rounded()),
                        debounced: true
                    )
                }
            }

            HStack {
                Image(systemName: "sun.max")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Text("\(Int(localBrightness.rounded()))%")
                    .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(.horizontal, 4)
    }

    private func colorControlsSection(palette: ModernPalette) -> some View {
        VStack(spacing: 14) {
            if availableLightTabs.count > 1 {
                HStack(spacing: 4) {
                    ForEach(availableLightTabs) { tab in
                        let selected = lightModeTab == tab
                        Button {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                            selectLightTab(tab)
                        } label: {
                            Text(tab.rawValue)
                                .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                                .foregroundStyle(selected ? Color.white : palette.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background {
                                    if selected {
                                        Capsule()
                                            .fill(palette.accentGradient)
                                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.75))
                                            .shadow(color: palette.accent.opacity(0.28), radius: 5, y: 2)
                                    }
                                }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.liquidGlassCapsule)
                        .disabled(controlsInactive)
                    }
                }
                .padding(4)
                .background(palette.surfaceSubtle, in: Capsule())
            }

            lightPresetSwatchesRow(palette: palette)
        }
    }

    private var availableLightTabs: [ModernLightTab] {
        var tabs: [ModernLightTab] = []
        if device.state.supportsColorTemp {
            tabs.append(.warm)
            tabs.append(.cool)
        }
        if device.state.supportsRGBColor {
            tabs.append(.color)
        }
        return tabs.isEmpty ? [.warm, .cool] : tabs
    }

    private var dialMode: ModernColorRingDial.Mode {
        switch lightModeTab {
        case .warm: return .warmWhite
        case .cool: return .coolWhite
        case .color: return .rgbColor
        }
    }

    private var activeKelvinRange: ClosedRange<Double> {
        let minK = Double(device.state.colorTempMinK)
        let maxK = Double(max(device.state.colorTempMaxK, device.state.colorTempMinK + 1000))
        let split = min(max(3800.0, minK + 400.0), maxK - 400.0)
        switch lightModeTab {
        case .warm: return minK...split
        case .cool: return split...maxK
        case .color: return minK...maxK
        }
    }

    private var currentLightDisplayColor: Color {
        if lightModeTab == .color {
            if let rgb = device.state.colorRGB, rgb != 0 {
                return GoogleHomeColorUtil.normalizedLightColor(fromRGBInt: rgb, isDark: colorScheme == .dark)
            }
            return Color(hue: localHue, saturation: 0.88, brightness: colorScheme == .dark ? 0.96 : 0.78)
        }
        let rgb = GoogleHomeFoyerCodec.kelvinToRGB(Int(localKelvin.rounded()))
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    private func selectLightTab(_ tab: ModernLightTab) {
        withAnimation(.easeOut(duration: 0.2)) {
            lightModeTab = tab
        }
        switch tab {
        case .warm:
            let targetK = min(max(2700, device.state.colorTempMinK), Int(activeKelvinRange.upperBound))
            localKelvin = Double(targetK)
            homeManager.setColorTemperature(deviceId: device.id, kelvin: targetK, debounced: false)
        case .cool:
            let targetK = min(max(5500, Int(activeKelvinRange.lowerBound)), device.state.colorTempMaxK)
            localKelvin = Double(targetK)
            homeManager.setColorTemperature(deviceId: device.id, kelvin: targetK, debounced: false)
        case .color:
            let rgb = device.state.colorRGB ?? Self.rgbInt(hue: localHue, saturation: 0.92, brightness: 1.0)
            homeManager.setColorRGB(deviceId: device.id, rgbInt: rgb, debounced: false)
        }
    }

    private func lightPresetSwatchesRow(palette: ModernPalette) -> some View {
        HStack(spacing: 11) {
            if lightModeTab == .color {
                let featured = featuredColorSwatches
                ForEach(featured.prefix(5)) { swatch in
                    let isSelected = device.state.colorRGB == swatch.rgbInt
                    Button {
                        if let h = Self.hue(fromRGBInt: swatch.rgbInt) {
                            localHue = h
                        }
                        homeManager.setColorRGB(deviceId: device.id, rgbInt: swatch.rgbInt, debounced: false)
                    } label: {
                        Circle()
                            .fill(GoogleHomeDeviceDetailView.color(fromRGBInt: swatch.rgbInt))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        isSelected ? palette.accent : palette.border,
                                        lineWidth: isSelected ? 2.5 : 1
                                    )
                            )
                            .shadow(color: palette.cardShadow, radius: 3, y: 1)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(controlsInactive)
                    .accessibilityLabel(swatch.displayName.capitalized)
                    .help(swatch.displayName.capitalized)
                }

                Button {
                    showColorPalettePopover.toggle()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 28, height: 28)
                        .background(palette.surfaceSubtle, in: Circle())
                        .overlay(Circle().strokeBorder(palette.border, lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(controlsInactive)
                .accessibilityLabel("More colors")
                .help("All Google Home colors & custom picker")
                .popover(isPresented: $showColorPalettePopover) {
                    allColorsPopover(palette: palette)
                }
            } else {
                let minK = device.state.colorTempMinK
                let maxK = device.state.colorTempMaxK
                let presets: [(String, Int)] = lightModeTab == .warm
                    ? [
                        ("Candle", max(minK, 2000)),
                        ("Amber", max(minK, 2400)),
                        ("Warm", max(minK, 2700)),
                        ("Soft", max(minK, 3200)),
                        ("Neutral", min(maxK, 3800)),
                    ]
                    : [
                        ("Daylight", max(minK, 5000)),
                        ("Pure", min(maxK, 6000)),
                        ("Cool", min(maxK, 6500)),
                        ("Bright", min(maxK, 7500)),
                        ("Ice", min(maxK, 8800)),
                    ]

                ForEach(presets, id: \.0) { label, kelvin in
                    let rgb = GoogleHomeFoyerCodec.kelvinToRGB(kelvin)
                    let isSelected = abs(Int(localKelvin.rounded()) - kelvin) < 250
                    Button {
                        localKelvin = Double(kelvin)
                        homeManager.setColorTemperature(deviceId: device.id, kelvin: kelvin, debounced: false)
                    } label: {
                        Circle()
                            .fill(Color(red: rgb.r, green: rgb.g, blue: rgb.b))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        isSelected ? palette.accent : palette.border,
                                        lineWidth: isSelected ? 2.5 : 1
                                    )
                            )
                            .shadow(color: palette.cardShadow, radius: 3, y: 1)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(controlsInactive)
                    .accessibilityLabel("\(label) \(kelvin)K")
                    .help("\(label) (\(kelvin)K)")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    private func allColorsPopover(palette: ModernPalette) -> some View {
        let swatches = featuredColorSwatches
        let cols = Array(repeating: GridItem(.fixed(28), spacing: 8), count: 6)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Google Home Colors")
                    .font(.caption.weight(.semibold))
                Spacer()
                ColorPicker(
                    "Custom",
                    selection: Binding(
                        get: {
                            if let rgb = device.state.colorRGB {
                                return GoogleHomeDeviceDetailView.color(fromRGBInt: rgb)
                            }
                            return currentLightDisplayColor
                        },
                        set: { newColor in
                            if let rgb = GoogleHomeDeviceDetailView.rgbInt(from: newColor) {
                                if let h = Self.hue(fromRGBInt: rgb) { localHue = h }
                                homeManager.setColorRGB(deviceId: device.id, rgbInt: rgb, debounced: true)
                            }
                        }
                    ),
                    supportsOpacity: false
                )
                .font(.caption)
            }

            ScrollView {
                LazyVGrid(columns: cols, spacing: 8) {
                    ForEach(swatches) { swatch in
                        let selected = device.state.colorRGB == swatch.rgbInt
                        Button {
                            if let h = Self.hue(fromRGBInt: swatch.rgbInt) { localHue = h }
                            homeManager.setColorRGB(deviceId: device.id, rgbInt: swatch.rgbInt, debounced: false)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(GoogleHomeDeviceDetailView.color(fromRGBInt: swatch.rgbInt))
                                    .frame(width: 26, height: 26)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(
                                                selected ? palette.accent : Color.primary.opacity(0.18),
                                                lineWidth: selected ? 2 : 0.75
                                            )
                                    )
                                if selected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(swatch.useDarkCheckmark ? Color.black : Color.white)
                                }
                            }
                            .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help(swatch.displayName.capitalized)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 200)
        }
        .padding(12)
        .frame(width: 244)
    }

    private var featuredColorSwatches: [GoogleHomeColorSwatch] {
        let nonWhite = device.state.supportedColors.filter { !$0.isWhitePreset }
        if !nonWhite.isEmpty {
            let order = [
                "crimson", "orange red", "gold", "lime", "deep sky blue", "blue violet",
                "magenta", "turquoise", "coral", "green", "azure", "hot pink",
            ]
            var result: [GoogleHomeColorSwatch] = []
            var used = Set<String>()
            for key in order {
                if let match = nonWhite.first(where: { $0.nameKey.lowercased() == key }) {
                    result.append(match)
                    used.insert(match.nameKey)
                }
            }
            for swatch in nonWhite where !used.contains(swatch.nameKey) {
                result.append(swatch)
            }
            return result
        }
        return [
            GoogleHomeColorSwatch(nameKey: "crimson", displayName: "Crimson", rgbInt: 0xDC143C),
            GoogleHomeColorSwatch(nameKey: "orange_red", displayName: "Orange", rgbInt: 0xFF6F3C),
            GoogleHomeColorSwatch(nameKey: "gold", displayName: "Gold", rgbInt: 0xFFD700, useDarkCheckmark: true),
            GoogleHomeColorSwatch(nameKey: "lime", displayName: "Lime", rgbInt: 0x32CD32),
            GoogleHomeColorSwatch(nameKey: "deep_sky_blue", displayName: "Sky Blue", rgbInt: 0x1E90FF),
            GoogleHomeColorSwatch(nameKey: "violet", displayName: "Violet", rgbInt: 0x8A2BE2),
            GoogleHomeColorSwatch(nameKey: "magenta", displayName: "Magenta", rgbInt: 0xE020A0),
        ]
    }

    // MARK: - Shared Secondary Trait Cards

    private func modernFanSpeedSliderCard(palette: ModernPalette) -> some View {
        let speeds = device.state.availableFanSpeeds
        let count = max(speeds.count, 1)
        let currentIndex = speeds.firstIndex(where: { $0.speedName == device.state.currentFanSpeed }) ?? 0
        let currentLabel = speeds.indices.contains(currentIndex)
            ? speeds[currentIndex].displayLabel
            : "Auto"

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Fan")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Text(currentLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }

            if count > 1 {
                ModernTrackSlider(
                    value: Binding(
                        get: { Double(currentIndex) },
                        set: { val in
                            let idx = min(max(Int(val.rounded()), 0), count - 1)
                            if speeds[idx].speedName != device.state.currentFanSpeed {
                                homeManager.setFanSpeed(deviceId: device.id, speedName: speeds[idx].speedName)
                            }
                        }
                    ),
                    in: 0...Double(count - 1),
                    accent: palette.accent,
                    isDisabled: controlsInactive,
                    thumbSymbol: "fan.fill"
                )
            }

            HStack(spacing: 2) {
                ForEach(speeds) { opt in
                    let active = device.state.currentFanSpeed == opt.speedName
                    Button {
                        homeManager.setFanSpeed(deviceId: device.id, speedName: opt.speedName)
                    } label: {
                        Text(opt.displayLabel)
                            .font(.system(size: 10.5, weight: active ? .bold : .medium))
                            .foregroundStyle(active ? palette.accent : palette.textMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(controlsInactive)
                }
            }
        }
    }

    private func continuousFanSpeedCard(palette: ModernPalette) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Fan Speed")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Text("\(Int(localFanPercent.rounded()))%")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(palette.textPrimary)
            }

            ModernTrackSlider(
                value: $localFanPercent,
                in: 0...100,
                accent: palette.accent,
                isDisabled: controlsInactive,
                thumbSymbol: "fan.fill"
            ) { editing in
                isDraggingControl = editing
                if !editing {
                    homeManager.setFanSpeedPercent(
                        deviceId: device.id,
                        percent: Int(localFanPercent.rounded()),
                        debounced: false
                    )
                }
            }
            .onChange(of: localFanPercent) { _, val in
                if isDraggingControl {
                    homeManager.setFanSpeedPercent(deviceId: device.id, percent: Int(val.rounded()), debounced: true)
                }
            }
        }
    }

    private func secondaryHumidityCard(palette: ModernPalette) -> some View {
        let minH = Double(device.state.minHumidityPercent)
        let maxH = Double(max(device.state.maxHumidityPercent, device.state.minHumidityPercent + 5))
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Target Humidity")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Text("\(Int(localHumidity.rounded()))%")
                    .font(.system(size: 12.5, weight: .bold).monospacedDigit())
                    .foregroundStyle(palette.textPrimary)
            }
            ModernTrackSlider(
                value: $localHumidity,
                in: minH...maxH,
                accent: palette.accent,
                isDisabled: controlsInactive
            ) { editing in
                isDraggingControl = editing
                if !editing {
                    homeManager.setHumiditySetpoint(deviceId: device.id, percent: Int(localHumidity.rounded()), debounced: false)
                }
            }
        }
        .padding(14)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.border, lineWidth: 1))
    }

    private func secondaryOpenCloseCard(openPct: Int, palette: ModernPalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Open Position")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Text("\(openPct)%")
                    .font(.system(size: 12.5, weight: .bold).monospacedDigit())
                    .foregroundStyle(palette.textPrimary)
            }
            ModernTrackSlider(
                value: $localOpenPercent,
                in: 0...100,
                accent: palette.accent,
                isDisabled: controlsInactive
            ) { editing in
                isDraggingControl = editing
                if !editing {
                    homeManager.setOpenPercent(deviceId: device.id, percent: Int(localOpenPercent.rounded()), debounced: false)
                }
            }
        }
        .padding(14)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.border, lineWidth: 1))
    }

    private func volumeCard(palette: ModernPalette) -> some View {
        let muted = device.state.isMuted ?? false
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    homeManager.setMuted(deviceId: device.id, muted: !muted)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(muted ? palette.danger : palette.accent)
                        Text("Volume")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(controlsInactive)

                Spacer()

                Text(muted ? "Muted" : "\(Int(localVolume.rounded()))%")
                    .font(.system(size: 12.5, weight: .bold).monospacedDigit())
                    .foregroundStyle(palette.textPrimary)
            }

            ModernTrackSlider(
                value: $localVolume,
                in: 0...100,
                accent: palette.accent,
                isDisabled: controlsInactive
            ) { editing in
                isDraggingControl = editing
                if !editing {
                    homeManager.setVolume(deviceId: device.id, percent: Int(localVolume.rounded()), debounced: false)
                }
            }
            .onChange(of: localVolume) { _, val in
                if isDraggingControl {
                    homeManager.setVolume(deviceId: device.id, percent: Int(val.rounded()), debounced: true)
                }
            }
        }
        .padding(14)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.border, lineWidth: 1))
    }

    private func lockCard(isLocked: Bool, palette: ModernPalette) -> some View {
        HStack {
            Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isLocked ? palette.accent : .orange)
                .frame(width: 26)
            Text(isLocked ? "Locked" : "Unlocked")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Button {
                homeManager.setLocked(deviceId: device.id, locked: !isLocked)
            } label: {
                Text(isLocked ? "Unlock" : "Lock")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(palette.accentGradient, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(controlsInactive)
        }
        .padding(14)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.border, lineWidth: 1))
    }

    private func startStopCard(isRunning: Bool, palette: ModernPalette) -> some View {
        let isPaused = device.state.isPaused ?? false
        return HStack(spacing: 8) {
            Button {
                homeManager.setRunning(deviceId: device.id, running: !isRunning)
            } label: {
                Label(isRunning ? "Stop" : "Start", systemImage: isRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        isRunning
                            ? LinearGradient(colors: [palette.danger, palette.dangerDeep], startPoint: .top, endPoint: .bottom)
                            : palette.accentGradient,
                        in: Capsule()
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(controlsInactive)

            if isRunning && device.state.isPausable {
                Button {
                    homeManager.setPaused(deviceId: device.id, paused: !isPaused)
                } label: {
                    Label(isPaused ? "Resume" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(palette.surfaceSubtle, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(controlsInactive)
            }
        }
        .padding(12)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.border, lineWidth: 1))
    }

    @ViewBuilder
    private func extraModesSection(palette: ModernPalette) -> some View {
        let visibleModes = device.state.modes.filter { mode in
            !(device.supportsColor && mode.modeName.lowercased() == "light_mode")
        }
        if !visibleModes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(visibleModes) { mode in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(mode.displayName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)

                        if mode.settings.count <= 4 {
                            HStack(spacing: 4) {
                                ForEach(mode.settings) { setting in
                                    modeSettingPill(mode: mode, setting: setting, palette: palette)
                                }
                            }
                            .padding(4)
                            .background(palette.surfaceSubtle, in: Capsule())
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], spacing: 6) {
                                ForEach(mode.settings) { setting in
                                    let active = mode.currentSetting == setting.settingName
                                    modeSettingPill(mode: mode, setting: setting, palette: palette)
                                        .background(active ? Color.clear : palette.surfaceSubtle, in: Capsule())
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func modeSettingPill(
        mode: GoogleHomeModeOption,
        setting: GoogleHomeModeSettingOption,
        palette: ModernPalette
    ) -> some View {
        let active = mode.currentSetting == setting.settingName
        return Button {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            homeManager.setMode(
                deviceId: device.id,
                modeName: mode.modeName,
                settingName: setting.settingName
            )
        } label: {
            Text(setting.displayLabel)
                .font(.system(size: 11.5, weight: active ? .semibold : .medium))
                .foregroundStyle(active ? Color.white : palette.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background {
                    if active {
                        Capsule()
                            .fill(palette.accentGradient)
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.75))
                            .shadow(color: palette.accent.opacity(0.26), radius: 4, y: 2)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.liquidGlassCapsule)
        .disabled(controlsInactive)
    }

    @ViewBuilder
    private func extraTogglesSection(palette: ModernPalette) -> some View {
        if !device.state.toggles.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(device.state.toggles.enumerated()), id: \.element.id) { index, toggle in
                    if index > 0 {
                        Divider()
                            .overlay(palette.divider)
                            .padding(.horizontal, 12)
                    }
                    // Full-row clickable toggle button so clicking icon, label, empty space, OR pill all work
                    Button {
                        guard !controlsInactive else { return }
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                        homeManager.setToggle(
                            deviceId: device.id,
                            toggleName: toggle.toggleName,
                            enabled: !toggle.isOn
                        )
                    } label: {
                        HStack {
                            Image(systemName: Self.iconForToggle(toggle.toggleName))
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(toggle.isOn ? palette.accent : palette.textSecondary)
                                .frame(width: 24)
                            Text(toggle.displayName)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                            ModernPillSwitchTrack(
                                isOn: toggle.isOn,
                                isDisabled: controlsInactive,
                                accentColor: palette.accent
                            )
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(LiquidGlassPressStyle(shape: RoundedRectangle(cornerRadius: 12), pressScale: 0.985, flashOpacity: 0.12))
                    .disabled(controlsInactive)
                    .accessibilityLabel("\(toggle.displayName), \(toggle.isOn ? "On" : "Off")")
                }
            }
            .background(palette.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.border, lineWidth: 1))
            .shadow(color: palette.cardShadow, radius: 6, y: 2)
        }
    }

    // MARK: - Helpers for Climate Metrics

    private var acModeIcons: [String] {
        switch device.state.thermostatMode?.lowercased() {
        case "heat": return ["flame.fill", "fan", "wind"]
        case "dry": return ["drop.fill", "fan", "wind"]
        default: return ["snowflake", "fan", "wind"]
        }
    }

    private func acAccentColor(palette: ModernPalette) -> Color {
        switch device.state.thermostatMode?.lowercased() {
        case "heat": return .orange
        default: return palette.accent
        }
    }

    private var acThirdMetricValue: String {
        if let speed = device.state.currentFanSpeed {
            return device.state.availableFanSpeeds
                .first(where: { $0.speedName == speed })?.displayLabel
                ?? GoogleHomeDevice.prettySpeedLabel(speed)
        }
        if let pct = device.state.currentFanSpeedPercent {
            return "\(pct)%"
        }
        return isOn ? "Active" : "Standby"
    }

    private func metricCell(label: String, value: String, palette: ModernPalette) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(palette.textMuted)
            Text(value)
                .font(.system(size: 14.5, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Bottom Action Bar (Only Turn-On Button Stays Highlighted When Off)

    @ViewBuilder
    private func bottomActionBar(palette: ModernPalette) -> some View {
        if device.supportsOnOff {
            if device.deviceType == .light || device.supportsBrightness {
                HStack(spacing: 10) {
                    // Quick brightness presets dim & lock when the light is off
                    HStack(spacing: 10) {
                        quickLightIconButton(symbol: "moon.fill", helpText: "Dim 25%", palette: palette) {
                            localBrightness = 25
                            homeManager.setBrightness(deviceId: device.id, percent: 25, debounced: false)
                        }
                        quickLightIconButton(symbol: "sun.min.fill", helpText: "Relax 60%", palette: palette) {
                            localBrightness = 60
                            homeManager.setBrightness(deviceId: device.id, percent: 60, debounced: false)
                        }
                        quickLightIconButton(symbol: "sun.max.fill", helpText: "Bright 100%", palette: palette) {
                            localBrightness = 100
                            homeManager.setBrightness(deviceId: device.id, percent: 100, debounced: false)
                        }
                    }
                    .saturation(controlsInactive ? 0.05 : 1.0)
                    .opacity(controlsInactive ? 0.38 : 1.0)
                    .disabled(controlsInactive)
                    .allowsHitTesting(!controlsInactive)

                    Spacer(minLength: 4)

                    // Turn On stays vibrantly highlighted when off; Turn Off stays crisp when on
                    Button {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                        homeManager.setPower(deviceId: device.id, on: !isOn)
                    } label: {
                        HStack(spacing: 6) {
                            if !isOn {
                                Image(systemName: "power")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            Text(isOn ? "Turn Off" : "Turn On")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(isOn ? palette.textPrimary : Color.white)
                        .frame(minWidth: 136)
                        .padding(.vertical, 10)
                        .background {
                            if isOn {
                                Capsule()
                                    .fill(Color.clear)
                                    .liquidGlassSurface(in: Capsule(), interactive: true, shadowRadius: 6)
                            } else {
                                Capsule()
                                    .fill(palette.accentGradient)
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 0.8))
                            }
                        }
                        .shadow(
                            color: isOn ? .clear : palette.accent.opacity(0.42),
                            radius: isOn ? 0 : 10,
                            y: isOn ? 0 : 3
                        )
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.liquidGlassCapsule)
                    .disabled(!device.state.isOnline)
                    .opacity(device.state.isOnline ? 1.0 : 0.45)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(palette.canvas)
            } else {
                // Full-width Crimson "Turn Off" / Vibrant Highlighted Cobalt "Turn On" button
                Button {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    homeManager.setPower(deviceId: device.id, on: !isOn)
                } label: {
                    HStack(spacing: 7) {
                        if !isOn {
                            Image(systemName: "power")
                                .font(.system(size: 13, weight: .bold))
                        }
                        Text(isOn ? "Turn Off" : "Turn On")
                            .font(.system(size: 13.5, weight: .bold))
                    }
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: isOn
                                ? [palette.danger, palette.dangerDeep]
                                : [palette.accent, palette.accentDeep],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8)
                    )
                    .shadow(
                        color: (isOn ? palette.danger : palette.accent).opacity(isOn ? 0.32 : 0.44),
                        radius: isOn ? 8 : 12,
                        y: 3
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(LiquidGlassPressStyle(shape: Capsule(), pressScale: 0.965, flashOpacity: 0.22))
                .disabled(!device.state.isOnline)
                .opacity(device.state.isOnline ? 1.0 : 0.45)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(palette.canvas)
            }
        }
    }

    private func quickLightIconButton(
        symbol: String,
        helpText: String,
        palette: ModernPalette,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .frame(width: 34, height: 34)
                .liquidGlassSurface(in: Circle(), interactive: true, shadowRadius: 4)
                .contentShape(Circle())
        }
        .buttonStyle(.liquidGlassCircle)
        .disabled(controlsInactive)
        .accessibilityLabel(helpText)
        .help(helpText)
    }

    // MARK: - Sync & Color Math

    private func syncLocalValues(forceMode: Bool) {
        if let b = device.state.brightness {
            localBrightness = Double(max(1, min(100, b)))
        }
        if let k = device.state.colorTemperatureK {
            localKelvin = Double(max(device.state.colorTempMinK, min(device.state.colorTempMaxK, k)))
        }
        if let rgb = device.state.colorRGB, rgb != 0, let h = Self.hue(fromRGBInt: rgb) {
            localHue = h
        }
        if let t = device.state.targetTempC {
            localTempC = max(device.state.minTempC, min(device.state.maxTempC, t))
        }
        if let fp = device.state.currentFanSpeedPercent {
            localFanPercent = Double(max(0, min(100, fp)))
        }
        if let hum = device.state.humiditySetpointPercent {
            localHumidity = Double(max(device.state.minHumidityPercent, min(device.state.maxHumidityPercent, hum)))
        }
        if let open = device.state.openPercent {
            localOpenPercent = Double(max(0, min(100, open)))
        }
        if let vol = device.state.volumePercent {
            localVolume = Double(max(0, min(100, vol)))
        }
        if forceMode {
            let tabs = availableLightTabs
            if device.state.colorRGB != nil && device.state.colorTemperatureK == nil && tabs.contains(.color) {
                lightModeTab = .color
            } else if let k = device.state.colorTemperatureK, k >= 3900, tabs.contains(.cool) {
                lightModeTab = .cool
            } else if let first = tabs.first {
                lightModeTab = first
            }
        }
    }

    static func hue(fromRGBInt rgb: Int) -> Double? {
        let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let b = CGFloat(rgb & 0xFF) / 255.0
        let nsColor = NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
        var h: CGFloat = 0
        var s: CGFloat = 0
        var v: CGFloat = 0
        var a: CGFloat = 0
        nsColor.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        return Double(h)
    }

    static func rgbInt(hue: Double, saturation: Double, brightness: Double) -> Int {
        let nsColor = NSColor(
            hue: CGFloat(hue.truncatingRemainder(dividingBy: 1.0)),
            saturation: CGFloat(saturation),
            brightness: CGFloat(brightness),
            alpha: 1.0
        ).usingColorSpace(.sRGB) ?? .white
        let r = Int((min(max(nsColor.redComponent, 0), 1) * 255).rounded())
        let g = Int((min(max(nsColor.greenComponent, 0), 1) * 255).rounded())
        let b = Int((min(max(nsColor.blueComponent, 0), 1) * 255).rounded())
        return (r << 16) | (g << 8) | b
    }

    private static func iconForToggle(_ toggleName: String) -> String {
        switch toggleName.lowercased() {
        case "led_toggle": return "lightbulb.led.fill"
        case "sleep_toggle": return "moon.zzz.fill"
        default: return "switch.2"
        }
    }
}

// MARK: - Interactive Rotary Color & Temperature Ring Dial

struct ModernColorRingDial: View {
    enum Mode {
        case warmWhite
        case coolWhite
        case rgbColor
    }

    let isOn: Bool
    let isOnline: Bool
    let supportsPowerToggle: Bool
    let mode: Mode
    @Binding var kelvin: Double
    let kelvinRange: ClosedRange<Double>
    @Binding var hue: Double
    @Binding var whiteSide: Double
    let brightnessPercent: Int
    let currentColor: Color
    let onTogglePower: () -> Void
    let onKelvinChanged: (Double, Bool) -> Void
    let onColorChanged: (Int, Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private let dialSize: CGFloat = 216
    private let ringRadius: CGFloat = 76
    private let ringLineWidth: CGFloat = 24
    private let tickCount = 36

    private var ringInteractive: Bool {
        isOnline && (!supportsPowerToggle || isOn)
    }

    private var thumbAngleRad: Double {
        switch mode {
        case .rgbColor:
            return (hue * 2.0 * .pi) - (.pi / 2.0)
        case .warmWhite, .coolWhite:
            let span = max(kelvinRange.upperBound - kelvinRange.lowerBound, 1)
            let t = min(max((kelvin - kelvinRange.lowerBound) / span, 0), 1)
            let thetaFromTop = acos(min(max(1.0 - 2.0 * t, -1.0), 1.0)) * (whiteSide >= 0 ? 1.0 : -1.0)
            return thetaFromTop - (.pi / 2.0)
        }
    }

    var body: some View {
        let palette = ModernPalette(colorScheme: colorScheme)
        let center = CGPoint(x: dialSize / 2, y: dialSize / 2)
        let thumbPos = CGPoint(
            x: center.x + CGFloat(cos(thumbAngleRad)) * ringRadius,
            y: center.y + CGFloat(sin(thumbAngleRad)) * ringRadius
        )

        ZStack {
            // Outer ticks + color ring + thumb: grayed out & non-interactive while light is off
            ZStack {
                Canvas { context, size in
                    let c = CGPoint(x: size.width / 2, y: size.height / 2)
                    let activeNorm = normalizeAngle(thumbAngleRad)
                    for i in 0..<tickCount {
                        let ang = (Double(i) / Double(tickCount)) * 2.0 * .pi
                        let diff = abs(shortestAngleDelta(ang, activeNorm))
                        let isNearest = diff < (.pi / Double(tickCount)) && ringInteractive
                        let rInner: CGFloat = isNearest ? 94 : 96
                        let rOuter: CGFloat = isNearest ? 105 : 103
                        var path = Path()
                        path.move(to: CGPoint(x: c.x + cos(ang) * rInner, y: c.y + sin(ang) * rInner))
                        path.addLine(to: CGPoint(x: c.x + cos(ang) * rOuter, y: c.y + sin(ang) * rOuter))
                        context.stroke(
                            path,
                            with: .color(isNearest ? palette.accent : palette.dialTick),
                            style: StrokeStyle(lineWidth: isNearest ? 2.0 : 1.1, lineCap: .round)
                        )
                    }
                }

                Circle()
                    .strokeBorder(
                        AngularGradient(
                            gradient: Gradient(colors: ringGradientColors),
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        lineWidth: ringLineWidth
                    )
                    .frame(width: ringRadius * 2 + ringLineWidth, height: ringRadius * 2 + ringLineWidth)

                Circle()
                    .fill(ringInteractive ? currentColor : palette.textMuted)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white, lineWidth: 2.5)
                    )
                    .shadow(color: Color.black.opacity(0.28), radius: 4, y: 1)
                    .position(thumbPos)
            }
            .saturation(ringInteractive ? 1.0 : 0.05)
            .opacity(ringInteractive ? 1.0 : 0.34)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard ringInteractive else { return }
                        let dx = Double(drag.location.x - center.x)
                        let dy = Double(drag.location.y - center.y)
                        guard hypot(dx, dy) >= 56 else { return }
                        applyDrag(dx: dx, dy: dy, finalCommit: false)
                    }
                    .onEnded { drag in
                        guard ringInteractive else { return }
                        let dx = Double(drag.location.x - center.x)
                        let dy = Double(drag.location.y - center.y)
                        guard hypot(dx, dy) >= 56 else { return }
                        applyDrag(dx: dx, dy: dy, finalCommit: true)
                    }
            )
            .allowsHitTesting(ringInteractive)
        }
        .frame(width: dialSize, height: dialSize)
        // Center power dome sits in an overlay OUTSIDE the ring's DragGesture so clicks never conflict
        // and stays vibrantly highlighted as a Turn On button when the light is off.
        .overlay {
            Button(action: onTogglePower) {
                ZStack {
                    if isOn && isOnline {
                        Circle()
                            .fill(currentColor.opacity(palette.isDark ? 0.30 : 0.22))
                            .frame(width: 122, height: 122)
                            .blur(radius: 10)
                    } else if !isOn && isOnline && supportsPowerToggle {
                        Circle()
                            .fill(palette.accent.opacity(palette.isDark ? 0.24 : 0.16))
                            .frame(width: 120, height: 120)
                            .blur(radius: 10)
                    }

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [palette.domeTop, palette.domeBottom],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 112, height: 112)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    (!isOn && isOnline && supportsPowerToggle)
                                        ? palette.accent.opacity(0.65)
                                        : Color.white.opacity(palette.isDark ? 0.12 : 0.90),
                                    lineWidth: (!isOn && isOnline && supportsPowerToggle) ? 2.0 : 1.5
                                )
                        )
                        .shadow(color: palette.domeShadow, radius: 14, y: 6)

                    VStack(spacing: 4) {
                        Image(systemName: isOn ? "lightbulb.fill" : "power")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(
                                isOn
                                    ? currentColor
                                    : (isOnline ? palette.accent : palette.textMuted)
                            )
                            .shadow(color: isOn ? currentColor.opacity(0.4) : .clear, radius: 4)

                        Text(centerPrimaryLabel)
                            .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(palette.textPrimary)

                        Text(isOn ? centerSecondaryLabel : "Tap to Turn On")
                            .font(.system(size: 10, weight: isOn ? .medium : .semibold))
                            .foregroundStyle(isOn ? palette.textSecondary : palette.accent)
                    }
                }
                .contentShape(Circle())
            }
            .buttonStyle(LiquidGlassPressStyle(shape: Circle(), pressScale: 0.94, flashOpacity: 0.16))
            .disabled(!isOnline || !supportsPowerToggle)
            .opacity(isOnline ? 1.0 : 0.45)
            .accessibilityLabel(isOn ? "Turn off light" : "Turn on light")
        }
    }

    private var centerPrimaryLabel: String {
        if !isOn { return "Off" }
        switch mode {
        case .rgbColor: return "\(brightnessPercent)%"
        case .warmWhite, .coolWhite: return "\(Int(kelvin.rounded()))K"
        }
    }

    private var centerSecondaryLabel: String {
        switch mode {
        case .warmWhite: return "Warm White"
        case .coolWhite: return "Cool White"
        case .rgbColor: return "Color Mode"
        }
    }

    private var ringGradientColors: [Color] {
        switch mode {
        case .rgbColor:
            return [
                Color(hue: 0.00, saturation: 0.90, brightness: 0.98),
                Color(hue: 0.12, saturation: 0.90, brightness: 0.98),
                Color(hue: 0.25, saturation: 0.85, brightness: 0.95),
                Color(hue: 0.42, saturation: 0.85, brightness: 0.95),
                Color(hue: 0.56, saturation: 0.90, brightness: 0.98),
                Color(hue: 0.72, saturation: 0.88, brightness: 0.98),
                Color(hue: 0.86, saturation: 0.88, brightness: 0.98),
                Color(hue: 1.00, saturation: 0.90, brightness: 0.98),
            ]
        case .warmWhite:
            return [
                Color(red: 0.96, green: 0.67, blue: 0.22),
                Color(red: 0.94, green: 0.79, blue: 0.36),
                Color(red: 0.89, green: 0.87, blue: 0.56),
                Color(red: 0.78, green: 0.89, blue: 0.72),
                Color(red: 0.89, green: 0.87, blue: 0.56),
                Color(red: 0.94, green: 0.79, blue: 0.36),
                Color(red: 0.96, green: 0.67, blue: 0.22),
            ]
        case .coolWhite:
            return [
                Color(red: 0.96, green: 0.90, blue: 0.74),
                Color(red: 0.86, green: 0.92, blue: 0.94),
                Color(red: 0.68, green: 0.84, blue: 0.98),
                Color(red: 0.52, green: 0.75, blue: 0.98),
                Color(red: 0.68, green: 0.84, blue: 0.98),
                Color(red: 0.86, green: 0.92, blue: 0.94),
                Color(red: 0.96, green: 0.90, blue: 0.74),
            ]
        }
    }

    private func applyDrag(dx: Double, dy: Double, finalCommit: Bool) {
        switch mode {
        case .rgbColor:
            var ang = atan2(dx, -dy)
            if ang < 0 { ang += 2.0 * .pi }
            let nextHue = min(max(ang / (2.0 * .pi), 0.0), 0.999)
            hue = nextHue
            let rgb = ModernDeviceDetailView.rgbInt(hue: nextHue, saturation: 0.92, brightness: 1.0)
            onColorChanged(rgb, finalCommit)
        case .warmWhite, .coolWhite:
            let thetaFromTop = atan2(dx, -dy)
            whiteSide = thetaFromTop >= 0 ? 1.0 : -1.0
            let t = (1.0 - cos(thetaFromTop)) / 2.0
            let nextK = kelvinRange.lowerBound + t * (kelvinRange.upperBound - kelvinRange.lowerBound)
            kelvin = nextK
            onKelvinChanged(nextK, finalCommit)
        }
    }

    private func normalizeAngle(_ rad: Double) -> Double {
        let twoPi = 2.0 * .pi
        let m = rad.truncatingRemainder(dividingBy: twoPi)
        return m < 0 ? m + twoPi : m
    }

    private func shortestAngleDelta(_ a: Double, _ b: Double) -> Double {
        var d = (a - b).truncatingRemainder(dividingBy: 2.0 * .pi)
        if d > .pi { d -= 2.0 * .pi }
        if d < -.pi { d += 2.0 * .pi }
        return d
    }
}

// MARK: - Interactive 240° Arc Dial (AC Temperature, Smart Fan Speed, Brightness, Humidity, Blinds)

struct ModernArcControlDial: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let isOn: Bool
    let isDisabled: Bool
    let accentColor: Color
    let centerIcon: String
    let centerValueText: String
    let minLabel: String
    let midLabel: String
    let maxLabel: String
    let statusIcons: [String]
    let onStepMinus: () -> Void
    let onStepPlus: () -> Void
    let onValueChanged: (Double, Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private let dialWidth: CGFloat = 248
    private let dialHeight: CGFloat = 200
    private let arcRadius: CGFloat = 74
    private let startDeg: Double = 150.0
    private let sweepDeg: Double = 240.0

    private var fraction: Double {
        let span = max(range.upperBound - range.lowerBound, 0.001)
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    private var thumbAngleDeg: Double {
        startDeg + sweepDeg * fraction
    }

    var body: some View {
        let palette = ModernPalette(colorScheme: colorScheme)
        let center = CGPoint(x: dialWidth / 2, y: dialHeight / 2 + 12)
        let thumbRad = thumbAngleDeg * .pi / 180.0
        let thumbPos = CGPoint(
            x: center.x + CGFloat(cos(thumbRad)) * arcRadius,
            y: center.y + CGFloat(sin(thumbRad)) * arcRadius
        )
        let pointerPos = CGPoint(
            x: center.x + CGFloat(cos(thumbRad)) * (arcRadius - 15),
            y: center.y + CGFloat(sin(thumbRad)) * (arcRadius - 15)
        )

        ZStack {
            Canvas { context, _ in
                let tickCount = 24
                for i in 0...tickCount {
                    let f = Double(i) / Double(tickCount)
                    let rad = (startDeg + sweepDeg * f) * .pi / 180.0
                    let isMajor = (i == 0 || i == tickCount / 2 || i == tickCount)
                    let rInner: CGFloat = arcRadius + 10
                    let rOuter: CGFloat = arcRadius + (isMajor ? 18 : 15)
                    var tickPath = Path()
                    tickPath.move(to: CGPoint(x: center.x + cos(rad) * rInner, y: center.y + sin(rad) * rInner))
                    tickPath.addLine(to: CGPoint(x: center.x + cos(rad) * rOuter, y: center.y + sin(rad) * rOuter))
                    context.stroke(
                        tickPath,
                        with: .color(f <= fraction && isOn ? accentColor.opacity(0.65) : palette.dialTick),
                        style: StrokeStyle(lineWidth: isMajor ? 1.8 : 1.1, lineCap: .round)
                    )
                }

                var trackPath = Path()
                trackPath.addArc(
                    center: center,
                    radius: arcRadius,
                    startAngle: .degrees(startDeg),
                    endAngle: .degrees(startDeg + sweepDeg),
                    clockwise: false
                )
                context.stroke(
                    trackPath,
                    with: .color(palette.dialTrack),
                    style: StrokeStyle(lineWidth: 7.5, lineCap: .round)
                )

                if fraction > 0.005 {
                    var activePath = Path()
                    activePath.addArc(
                        center: center,
                        radius: arcRadius,
                        startAngle: .degrees(startDeg),
                        endAngle: .degrees(thumbAngleDeg),
                        clockwise: false
                    )
                    context.stroke(
                        activePath,
                        with: .color(isOn ? accentColor : palette.textMuted.opacity(0.45)),
                        style: StrokeStyle(lineWidth: 8.5, lineCap: .round)
                    )
                }
            }

            Text(minLabel)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(palette.textSecondary)
                .position(
                    x: center.x + CGFloat(cos(startDeg * .pi / 180.0)) * (arcRadius + 32),
                    y: center.y + CGFloat(sin(startDeg * .pi / 180.0)) * (arcRadius + 28)
                )

            Text(midLabel)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(palette.textSecondary)
                .position(x: center.x, y: center.y - arcRadius - 29)

            Text(maxLabel)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(palette.textSecondary)
                .position(
                    x: center.x + CGFloat(cos((startDeg + sweepDeg) * .pi / 180.0)) * (arcRadius + 32),
                    y: center.y + CGFloat(sin((startDeg + sweepDeg) * .pi / 180.0)) * (arcRadius + 28)
                )

            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 7))
                .foregroundStyle(isOn ? accentColor : palette.textMuted)
                .rotationEffect(.degrees(thumbAngleDeg - 90))
                .position(pointerPos)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [palette.domeTop, palette.domeBottom],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 104, height: 104)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                Color.white.opacity(palette.isDark ? 0.12 : 0.90),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: palette.domeShadow, radius: 14, y: 6)

                VStack(spacing: 4) {
                    Image(systemName: centerIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isOn ? accentColor : palette.textMuted)

                    Text(centerValueText)
                        .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(palette.textPrimary)
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)
                        .padding(.horizontal, 8)

                    HStack(spacing: 7) {
                        ForEach(statusIcons, id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(isOn ? accentColor.opacity(0.82) : palette.textMuted)
                        }
                    }
                }
            }
            .position(center)

            Circle()
                .fill(Color.white)
                .frame(width: 18, height: 18)
                .overlay(
                    Circle()
                        .strokeBorder(isOn ? accentColor : palette.textSecondary, lineWidth: 3)
                )
                .shadow(color: Color.black.opacity(0.22), radius: 4, y: 1.5)
                .position(thumbPos)
        }
        .frame(width: dialWidth, height: dialHeight)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    guard !isDisabled else { return }
                    let dx = Double(drag.location.x - center.x)
                    let dy = Double(drag.location.y - center.y)
                    let dist = hypot(dx, dy)
                    guard dist >= 54 && dist <= 112 else { return }
                    if let next = valueForPoint(dx: dx, dy: dy) {
                        value = next
                        onValueChanged(next, false)
                    }
                }
                .onEnded { drag in
                    guard !isDisabled else { return }
                    let dx = Double(drag.location.x - center.x)
                    let dy = Double(drag.location.y - center.y)
                    let dist = hypot(dx, dy)
                    guard dist >= 54 && dist <= 112 else { return }
                    if let next = valueForPoint(dx: dx, dy: dy) {
                        value = next
                        onValueChanged(next, true)
                    }
                }
        )
        // Stepper buttons sit outside the arc DragGesture with native Liquid Glass + press bounce
        .overlay(alignment: .bottom) {
            LiquidGlassGroup(spacing: 48) {
                HStack(spacing: 52) {
                    Button {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                        onStepMinus()
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                            .frame(width: 32, height: 32)
                            .liquidGlassSurface(in: Circle(), interactive: true, shadowRadius: 4)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.liquidGlassCircle)
                    .disabled(isDisabled || value <= range.lowerBound)
                    .accessibilityLabel("Decrease")

                    Button {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                        onStepPlus()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                            .frame(width: 32, height: 32)
                            .liquidGlassSurface(in: Circle(), interactive: true, shadowRadius: 4)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.liquidGlassCircle)
                    .disabled(isDisabled || value >= range.upperBound)
                    .accessibilityLabel("Increase")
                }
            }
            .padding(.bottom, 0)
        }
    }

    private func valueForPoint(dx: Double, dy: Double) -> Double? {
        var deg = atan2(dy, dx) * 180.0 / .pi
        if deg < 0 { deg += 360.0 }
        let offset = deg >= startDeg ? (deg - startDeg) : (deg + (360.0 - startDeg))
        let f: Double
        if offset <= sweepDeg {
            f = offset / sweepDeg
        } else if offset < sweepDeg + 35.0 {
            f = 1.0
        } else if offset > 360.0 - 35.0 {
            f = 0.0
        } else {
            return nil
        }
        return range.lowerBound + f * (range.upperBound - range.lowerBound)
    }
}

private struct DetailGlassPillModifier: ViewModifier {
    let isGlass: Bool
    func body(content: Content) -> some View {
        if isGlass {
            content.liquidGlassSurface(in: Capsule(), interactive: true, shadowRadius: 4)
        } else {
            content
        }
    }
}

