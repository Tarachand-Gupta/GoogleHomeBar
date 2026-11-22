import AppKit
import GoogleHomeBarCore
import SwiftUI

struct GoogleHomeDeviceDetailView: View {
    let device: GoogleHomeDevice
    @Bindable var homeManager: GoogleHomeManager
    var showBackButton: Bool = true
    var onBack: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var colorTab: LightColorTab = .white
    @State private var localBrightness: Double = 100
    @State private var localKelvin: Double = 4000
    @State private var localTempC: Double = 24
    @State private var isDraggingSlider = false
    @State private var showAllSwatches = false

    private enum LightColorTab: String, CaseIterable, Identifiable {
        case white = "White"
        case colour = "Colour"
        var id: String { rawValue }
    }

    private var isPending: Bool {
        homeManager.pendingDeviceIds.contains(device.id)
    }

    private var isOn: Bool {
        device.state.isOn ?? false
    }

    private var controlsInactive: Bool {
        !device.state.isOnline || (device.supportsOnOff && !isOn)
    }

    var body: some View {
        VStack(spacing: 0) {
            detailHeader
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !device.state.isOnline {
                        offlineBanner
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
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }

                    if device.hasRichControls {
                        VStack(alignment: .leading, spacing: 14) {
                            if device.deviceType == .light || device.supportsBrightness || device.supportsColor {
                                lightControls
                            }

                            if device.supportsTemperatureSetting {
                                thermostatControls
                            }

                            if device.supportsFanSpeed {
                                fanSpeedControls
                            }

                            if let hum = device.state.humiditySetpointPercent {
                                humiditySection(hum)
                            }

                            if !device.state.modes.isEmpty {
                                modesSection
                            }

                            if !device.state.toggles.isEmpty {
                                togglesSection
                            }

                            if let openPct = device.state.openPercent {
                                openCloseSection(openPct)
                            }

                            if let vol = device.state.volumePercent {
                                volumeSection(vol)
                            }

                            if let isLocked = device.state.isLocked {
                                lockSection(isLocked)
                            }

                            if let isRunning = device.state.isRunning {
                                startStopSection(isRunning)
                            }
                        }
                        .saturation(controlsInactive ? 0.08 : 1.0)
                        .opacity(controlsInactive ? 0.45 : 1.0)
                        .disabled(controlsInactive)
                        .allowsHitTesting(!controlsInactive)
                        .animation(.easeInOut(duration: 0.2), value: controlsInactive)
                    }

                    if !device.hasRichControls && device.supportsOnOff {
                        basicPowerCard
                    }
                }
                .padding(14)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { syncLocalControlValues(forceTab: true) }
        .onChange(of: device.id) { _, _ in syncLocalControlValues(forceTab: true) }
        .onChange(of: device.state) { _, _ in
            if !isDraggingSlider {
                syncLocalControlValues(forceTab: false)
            }
        }
    }

    // MARK: - Header

    private var detailHeader: some View {
        HStack(spacing: 10) {
            if showBackButton, let onBack {
                Button {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12.5, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .liquidGlassSurface(in: Circle(), interactive: true)
                        .contentShape(Circle())
                }
                .buttonStyle(.liquidGlassCircle)
                .accessibilityLabel("Back to Devices")
            }

            ZStack {
                Circle()
                    .fill(accentColor.opacity(isOn && device.state.isOnline ? 0.24 : 0.08))
                    .frame(width: 36, height: 36)
                Image(systemName: isOn ? device.deviceType.sfSymbol : device.deviceType.offSymbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isOn && device.state.isOnline ? accentColor : Color.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(device.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    if isPending {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                Task { await homeManager.refreshTraits(for: [device.id], silent: false) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11.5, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .liquidGlassSurface(in: Circle(), interactive: true)
                    .contentShape(Circle())
            }
            .buttonStyle(.liquidGlassCircle)
            .accessibilityLabel("Refresh \(device.name)")
            .help("Refresh state from Google Home")

            if device.supportsOnOff {
                Toggle("Power", isOn: Binding(
                    get: { isOn },
                    set: { homeManager.setPower(deviceId: device.id, on: $0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!device.state.isOnline)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var headerSubtitle: String {
        var parts = [device.roomName]
        if let mfr = device.manufacturer {
            parts.append(mfr.capitalized)
        }
        parts.append(device.statusSummary)
        return parts.joined(separator: " · ")
    }

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.secondary)
            Text("This device is currently offline in Google Home. Turn on its power switch and refresh.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Light Controls (Brightness + White Kelvin + Google Home RGB Swatches + Custom Color Picker)

    private var lightControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Hero Light Orb + Power/Brightness summary
            if device.supportsBrightness {
                sectionCard {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        accentColor.opacity(isOn ? 1.0 : 0.25),
                                        accentColor.opacity(isOn ? 0.35 : 0.05),
                                    ],
                                    center: .center,
                                    startRadius: 2,
                                    endRadius: 22
                                )
                            )
                            .frame(width: 42, height: 42)
                            .overlay(
                                Image(systemName: isOn ? "lightbulb.fill" : "lightbulb")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(isOn ? Color.white : Color.secondary)
                            )
                            .shadow(color: isOn ? accentColor.opacity(0.45) : .clear, radius: 10)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Brightness")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text(isOn ? "\(Int(localBrightness.rounded()))%" : "Off")
                                .font(.system(size: 20, weight: .semibold).monospacedDigit())
                        }

                        Spacer()
                    }

                    Slider(
                        value: $localBrightness,
                        in: 1...100,
                        onEditingChanged: { editing in
                            isDraggingSlider = editing
                            if !editing {
                                homeManager.setBrightness(
                                    deviceId: device.id,
                                    percent: Int(localBrightness.rounded()),
                                    debounced: false
                                )
                            }
                        }
                    )
                    .tint(accentColor)
                    .disabled(!device.state.isOnline)
                    .onChange(of: localBrightness) { _, newVal in
                        if isDraggingSlider {
                            homeManager.setBrightness(
                                deviceId: device.id,
                                percent: Int(newVal.rounded()),
                                debounced: true
                            )
                        }
                    }

                    HStack(spacing: 6) {
                        ForEach([25, 50, 75, 100], id: \.self) { pct in
                            let active = isOn && abs(Int(localBrightness.rounded()) - pct) <= 4
                            Button {
                                localBrightness = Double(pct)
                                homeManager.setBrightness(deviceId: device.id, percent: pct, debounced: false)
                            } label: {
                                Text("\(pct)%")
                                    .font(.caption.monospacedDigit().weight(active ? .semibold : .regular))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 5)
                                    .background(
                                        active ? accentColor.opacity(0.24) : Color.primary.opacity(0.06),
                                        in: RoundedRectangle(cornerRadius: 7)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7)
                                            .strokeBorder(active ? accentColor : Color.clear, lineWidth: 1)
                                    )
                                    .contentShape(RoundedRectangle(cornerRadius: 7))
                            }
                            .buttonStyle(.plain)
                            .disabled(controlsInactive)
                        }
                    }
                }
            }

            if device.supportsColor {
                sectionCard {
                    if device.state.supportsColorTemp && device.state.supportsRGBColor {
                        Picker("Color Mode", selection: $colorTab) {
                            ForEach(LightColorTab.allCases) { tab in
                                Text(tab.rawValue).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    if colorTab == .white && device.state.supportsColorTemp {
                        whiteTemperatureControls
                    } else if device.state.supportsRGBColor {
                        rgbColorControls
                    } else if device.state.supportsColorTemp {
                        whiteTemperatureControls
                    }
                }
            }
        }
    }

    private var whiteTemperatureControls: some View {
        let minK = Double(device.state.colorTempMinK)
        let maxK = Double(max(device.state.colorTempMaxK, device.state.colorTempMinK + 500))
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Color Temperature", systemImage: "thermometer.sun.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(localKelvin.rounded()))K")
                    .font(.caption.monospacedDigit().weight(.semibold))
            }

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.65, blue: 0.25),
                        Color(red: 1.0, green: 0.92, blue: 0.80),
                        Color(red: 0.78, green: 0.90, blue: 1.0),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 7)
                .clipShape(Capsule())
                .padding(.horizontal, 2)

                Slider(
                    value: $localKelvin,
                    in: minK...maxK,
                    onEditingChanged: { editing in
                        isDraggingSlider = editing
                        if !editing {
                            let roundedK = Int((localKelvin / 100.0).rounded()) * 100
                            homeManager.setColorTemperature(
                                deviceId: device.id,
                                kelvin: roundedK,
                                debounced: false
                            )
                        }
                    }
                )
                .disabled(!device.state.isOnline)
                .onChange(of: localKelvin) { _, newK in
                    if isDraggingSlider {
                        let roundedK = Int((newK / 100.0).rounded()) * 100
                        homeManager.setColorTemperature(
                            deviceId: device.id,
                            kelvin: roundedK,
                            debounced: true
                        )
                    }
                }
            }

            let presets: [(String, Int)] = [
                ("Candle", max(Int(minK), 2200)),
                ("Warm", max(Int(minK), 2700)),
                ("Soft", 3500),
                ("Daylight", 5000),
                ("Cool", min(Int(maxK), 6500)),
            ]
            HStack(spacing: 6) {
                ForEach(presets, id: \.0) { label, kelvin in
                    let rgb = GoogleHomeFoyerCodec.kelvinToRGB(kelvin)
                    let active = device.state.colorTemperatureK.map { abs($0 - kelvin) < 350 } ?? false
                    Button {
                        localKelvin = Double(kelvin)
                        homeManager.setColorTemperature(deviceId: device.id, kelvin: kelvin, debounced: false)
                    } label: {
                        VStack(spacing: 3) {
                            Circle()
                                .fill(Color(red: rgb.r, green: rgb.g, blue: rgb.b))
                                .frame(width: 14, height: 14)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                            Text(label)
                                .font(.system(size: 10, weight: active ? .semibold : .regular))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            active ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(active ? Color.accentColor : Color.clear, lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(controlsInactive)
                }
            }
        }
    }

    private var rgbColorControls: some View {
        let colorSwatches = curatedColorSwatches
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Color", systemImage: "paintpalette.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                ColorPicker(
                    "Custom",
                    selection: Binding(
                        get: {
                            if let rgb = device.state.colorRGB {
                                return Self.color(fromRGBInt: rgb)
                            }
                            return accentColor
                        },
                        set: { newColor in
                            if let rgb = Self.rgbInt(from: newColor) {
                                homeManager.setColorRGB(deviceId: device.id, rgbInt: rgb, debounced: true)
                            }
                        }
                    ),
                    supportsOpacity: false
                )
                .font(.caption)
                .disabled(!device.state.isOnline)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(showAllSwatches ? colorSwatches : Array(colorSwatches.prefix(18))) { swatch in
                    let isSelected = device.state.colorRGB == swatch.rgbInt
                    Button {
                        homeManager.setColorRGB(deviceId: device.id, rgbInt: swatch.rgbInt, debounced: false)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Self.color(fromRGBInt: swatch.rgbInt))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            isSelected ? Color.primary : Color.primary.opacity(0.18),
                                            lineWidth: isSelected ? 2 : 0.75
                                        )
                                )
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(swatch.useDarkCheckmark ? Color.black : Color.white)
                            }
                        }
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(swatch.displayName.capitalized)
                    .help(swatch.displayName.capitalized)
                    .disabled(controlsInactive)
                }
            }

            if colorSwatches.count > 18 {
                Button(showAllSwatches ? "Show fewer colors" : "Show all \(colorSwatches.count) colors") {
                    showAllSwatches.toggle()
                }
                .buttonStyle(.link)
                .font(.caption2)
            }
        }
    }

    private var curatedColorSwatches: [GoogleHomeColorSwatch] {
        let nonWhite = device.state.supportedColors.filter { !$0.isWhitePreset }
        if !nonWhite.isEmpty {
            let featuredOrder = [
                "crimson", "orange red", "coral", "gold", "lime", "green",
                "turquoise", "deep sky blue", "azure", "cornflower blue", "indigo", "blue violet",
                "medium purple", "magenta", "hot pink", "pink", "aquamarine", "tomato",
            ]
            var prioritized: [GoogleHomeColorSwatch] = []
            var used = Set<String>()
            for key in featuredOrder {
                if let match = nonWhite.first(where: { $0.nameKey.lowercased() == key }) {
                    prioritized.append(match)
                    used.insert(match.nameKey)
                }
            }
            for swatch in nonWhite where !used.contains(swatch.nameKey) {
                prioritized.append(swatch)
            }
            return prioritized
        }
        return [
            GoogleHomeColorSwatch(nameKey: "crimson", displayName: "Crimson", rgbInt: 0xDC143C),
            GoogleHomeColorSwatch(nameKey: "coral", displayName: "Coral", rgbInt: 0xFF6F61),
            GoogleHomeColorSwatch(nameKey: "gold", displayName: "Gold", rgbInt: 0xFFD700, useDarkCheckmark: true),
            GoogleHomeColorSwatch(nameKey: "lime", displayName: "Lime", rgbInt: 0x32CD32),
            GoogleHomeColorSwatch(nameKey: "turquoise", displayName: "Turquoise", rgbInt: 0x24A0DD),
            GoogleHomeColorSwatch(nameKey: "blue", displayName: "Blue", rgbInt: 0x1E64FF),
            GoogleHomeColorSwatch(nameKey: "indigo", displayName: "Indigo", rgbInt: 0x6A1B9A),
            GoogleHomeColorSwatch(nameKey: "magenta", displayName: "Magenta", rgbInt: 0xE020A0),
            GoogleHomeColorSwatch(nameKey: "hot_pink", displayName: "Hot Pink", rgbInt: 0xFF69B4),
            GoogleHomeColorSwatch(nameKey: "orange_red", displayName: "Orange", rgbInt: 0xFF5722),
            GoogleHomeColorSwatch(nameKey: "aquamarine", displayName: "Aqua", rgbInt: 0x26C6DA),
            GoogleHomeColorSwatch(nameKey: "purple", displayName: "Purple", rgbInt: 0x9C27B0),
        ]
    }

    // MARK: - Air Conditioner / Thermostat Controls

    private var thermostatControls: some View {
        let unit = device.state.temperatureUnit
        return sectionCard {
            HStack {
                Label("Temperature", systemImage: "thermometer.medium")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let ambient = device.state.ambientTempC {
                    Text("Room \(Int(ambient.rounded()))°\(unit)")
                        .font(.caption.monospacedDigit().weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.07), in: Capsule())
                }
            }

            HStack(spacing: 16) {
                Spacer()
                Button {
                    let next = max(device.state.minTempC, localTempC - 1)
                    localTempC = next
                    homeManager.setThermostatSetpoint(deviceId: device.id, tempC: next, debounced: false)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 36, height: 36)
                        .liquidGlassSurface(in: Circle(), interactive: true)
                        .contentShape(Circle())
                }
                .buttonStyle(.liquidGlassCircle)
                .accessibilityLabel("Decrease temperature")
                .disabled(controlsInactive || localTempC <= device.state.minTempC)

                VStack(spacing: 2) {
                    Text("\(Int(localTempC.rounded()))°\(unit)")
                        .font(.system(size: 30, weight: .bold).monospacedDigit())
                        .foregroundStyle(isOn ? accentColor : Color.primary)
                    Text(device.state.thermostatMode.map(GoogleHomeDevice.prettyThermostatMode) ?? "Target")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 84)

                Button {
                    let next = min(device.state.maxTempC, localTempC + 1)
                    localTempC = next
                    homeManager.setThermostatSetpoint(deviceId: device.id, tempC: next, debounced: false)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 36, height: 36)
                        .liquidGlassSurface(in: Circle(), interactive: true)
                        .contentShape(Circle())
                }
                .buttonStyle(.liquidGlassCircle)
                .accessibilityLabel("Increase temperature")
                .disabled(controlsInactive || localTempC >= device.state.maxTempC)
                Spacer()
            }
            .padding(.vertical, 4)

            Slider(
                value: $localTempC,
                in: device.state.minTempC...max(device.state.maxTempC, device.state.minTempC + 1),
                step: 1,
                onEditingChanged: { editing in
                    isDraggingSlider = editing
                    if !editing {
                        homeManager.setThermostatSetpoint(deviceId: device.id, tempC: localTempC, debounced: false)
                    }
                }
            )
            .tint(accentColor)
            .disabled(!device.state.isOnline)
            .onChange(of: localTempC) { _, val in
                if isDraggingSlider {
                    homeManager.setThermostatSetpoint(deviceId: device.id, tempC: val, debounced: true)
                }
            }

            if !device.state.availableThermostatModes.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mode")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(device.state.availableThermostatModes, id: \.self) { mode in
                            let active = device.state.thermostatMode?.lowercased() == mode.lowercased()
                            Button {
                                homeManager.setThermostatMode(deviceId: device.id, mode: mode)
                            } label: {
                                VStack(spacing: 3) {
                                    Image(systemName: Self.iconForThermostatMode(mode))
                                        .font(.system(size: 13))
                                    Text(GoogleHomeDevice.prettyThermostatMode(mode))
                                        .font(.caption2.weight(active ? .semibold : .regular))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(
                                    active ? accentColor.opacity(0.22) : Color.primary.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(active ? accentColor : Color.clear, lineWidth: 1)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .disabled(controlsInactive)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Fan Speed Controls (Smart Fan & AC Fan Speed)

    private var fanSpeedControls: some View {
        sectionCard {
            HStack {
                Label("Fan Speed", systemImage: "wind")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let current = device.state.currentFanSpeed {
                    let label = device.state.availableFanSpeeds.first(where: { $0.speedName == current })?.displayLabel
                        ?? GoogleHomeDevice.prettySpeedLabel(current)
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accentColor)
                } else if let pct = device.state.currentFanSpeedPercent {
                    Text("\(pct)%")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(accentColor)
                }
            }

            let speeds = device.state.availableFanSpeeds
            if !speeds.isEmpty {
                HStack(spacing: 6) {
                    ForEach(speeds) { opt in
                        let active = device.state.currentFanSpeed == opt.speedName
                        Button {
                            homeManager.setFanSpeed(deviceId: device.id, speedName: opt.speedName)
                        } label: {
                            Text(opt.displayLabel)
                                .font(.caption.weight(active ? .semibold : .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(
                                    active ? accentColor.opacity(0.24) : Color.primary.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(active ? accentColor : Color.clear, lineWidth: 1)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .disabled(controlsInactive)
                    }
                }
            } else if let pct = device.state.currentFanSpeedPercent {
                Slider(
                    value: Binding(
                        get: { Double(pct) },
                        set: { homeManager.setFanSpeedPercent(deviceId: device.id, percent: Int($0.rounded())) }
                    ),
                    in: 0...100,
                    step: 5
                )
                .disabled(controlsInactive)
            }
        }
    }

    private func humiditySection(_ hum: Int) -> some View {
        sectionCard {
            HStack {
                Label("Target Humidity", systemImage: "humidity.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(hum)%")
                    .font(.caption.monospacedDigit().weight(.semibold))
            }
            Slider(
                value: Binding(
                    get: { Double(hum) },
                    set: { homeManager.setHumiditySetpoint(deviceId: device.id, percent: Int($0.rounded())) }
                ),
                in: Double(device.state.minHumidityPercent)...Double(max(device.state.maxHumidityPercent, device.state.minHumidityPercent + 5)),
                step: 5
            )
            .disabled(controlsInactive)
        }
    }

    // MARK: - Modes & Toggles (Powerful / Jet Stream / LED Light / Sleep Mode)

    private var modesSection: some View {
        // Hide redundant light_mode when White/Colour tabs are already rendered above
        let visibleModes = device.state.modes.filter { mode in
            !(device.supportsColor && mode.modeName.lowercased() == "light_mode")
        }
        return Group {
            if !visibleModes.isEmpty {
                sectionCard {
                    ForEach(visibleModes) { mode in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(mode.displayName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                ForEach(mode.settings) { setting in
                                    let active = mode.currentSetting == setting.settingName
                                    Button {
                                        homeManager.setMode(
                                            deviceId: device.id,
                                            modeName: mode.modeName,
                                            settingName: setting.settingName
                                        )
                                    } label: {
                                        Text(setting.displayLabel)
                                            .font(.caption.weight(active ? .semibold : .regular))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 6)
                                            .background(
                                                active ? accentColor.opacity(0.22) : Color.primary.opacity(0.06),
                                                in: RoundedRectangle(cornerRadius: 8)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .strokeBorder(active ? accentColor : Color.clear, lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!device.state.isOnline)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var togglesSection: some View {
        sectionCard {
            ForEach(device.state.toggles) { toggle in
                HStack {
                    Label(toggle.displayName, systemImage: Self.iconForToggle(toggle.toggleName))
                        .font(.caption.weight(.medium))
                    Spacer()
                    Toggle(toggle.displayName, isOn: Binding(
                        get: { toggle.isOn },
                        set: { homeManager.setToggle(deviceId: device.id, toggleName: toggle.toggleName, enabled: $0) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .disabled(!device.state.isOnline)
                }
            }
        }
    }

    private func openCloseSection(_ pct: Int) -> some View {
        sectionCard {
            HStack {
                Label("Open Position", systemImage: "blinds.horizontal.open")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(pct)%")
                    .font(.caption.monospacedDigit().weight(.semibold))
            }
            Slider(
                value: Binding(
                    get: { Double(pct) },
                    set: { homeManager.setOpenPercent(deviceId: device.id, percent: Int($0.rounded())) }
                ),
                in: 0...100,
                step: 5
            )
            .disabled(!device.state.isOnline)
        }
    }

    private func volumeSection(_ vol: Int) -> some View {
        let muted = device.state.isMuted ?? false
        return sectionCard {
            HStack {
                Label("Volume", systemImage: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(muted ? "Muted" : "\(vol)%")
                    .font(.caption.monospacedDigit().weight(.semibold))
            }
            Slider(
                value: Binding(
                    get: { Double(vol) },
                    set: { homeManager.setVolume(deviceId: device.id, percent: Int($0.rounded())) }
                ),
                in: 0...100,
                step: 5
            )
            .disabled(controlsInactive)
        }
    }

    private func startStopSection(_ isRunning: Bool) -> some View {
        sectionCard {
            HStack {
                Label(isRunning ? "Running" : "Stopped", systemImage: isRunning ? "play.circle.fill" : "stop.circle")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(isRunning ? "Stop" : "Start") {
                    homeManager.setRunning(deviceId: device.id, running: !isRunning)
                }
                .buttonStyle(.borderedProminent)
                .disabled(controlsInactive)
            }
        }
    }

    private func lockSection(_ locked: Bool) -> some View {
        sectionCard {
            HStack {
                Label(locked ? "Locked" : "Unlocked", systemImage: locked ? "lock.fill" : "lock.open.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(locked ? "Unlock" : "Lock") {
                    homeManager.setLocked(deviceId: device.id, locked: !locked)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!device.state.isOnline)
            }
        }
    }

    private var basicPowerCard: some View {
        sectionCard {
            HStack {
                Text(isOn ? "Device is On" : "Device is Off")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button(isOn ? "Turn Off" : "Turn On") {
                    homeManager.setPower(deviceId: device.id, on: !isOn)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!device.state.isOnline)
            }
        }
    }

    // MARK: - Helpers

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassSurface(in: RoundedRectangle(cornerRadius: 14), shadowRadius: 5)
    }

    private func syncLocalControlValues(forceTab: Bool) {
        if let b = device.state.brightness {
            localBrightness = Double(max(1, min(100, b)))
        }
        if let k = device.state.colorTemperatureK {
            localKelvin = Double(max(device.state.colorTempMinK, min(device.state.colorTempMaxK, k)))
        }
        if let t = device.state.targetTempC {
            localTempC = max(device.state.minTempC, min(device.state.maxTempC, t))
        }
        if forceTab {
            if device.state.colorRGB != nil && device.state.colorTemperatureK == nil {
                colorTab = .colour
            } else {
                colorTab = .white
            }
        }
    }

    private var accentColor: Color {
        GoogleHomeColorUtil.accentColor(for: device, isDark: colorScheme == .dark)
    }

    static func deviceAccentColor(for device: GoogleHomeDevice) -> Color {
        switch device.deviceType {
        case .light:
            if let rgb = device.state.colorRGB {
                return color(fromRGBInt: rgb)
            }
            if let k = device.state.colorTemperatureK {
                let c = GoogleHomeFoyerCodec.kelvinToRGB(k)
                return Color(red: c.r, green: c.g, blue: c.b)
            }
            return .orange
        case .airConditioner, .thermostat:
            switch device.state.thermostatMode?.lowercased() {
            case "heat": return .orange
            case "dry": return .purple
            case "fan-only": return .teal
            default: return .cyan
            }
        case .fan:
            return .teal
        default:
            return .accentColor
        }
    }

    static func color(fromRGBInt rgb: Int) -> Color {
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    static func rgbInt(from color: Color) -> Int? {
        guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        let r = Int((min(max(ns.redComponent, 0), 1) * 255).rounded())
        let g = Int((min(max(ns.greenComponent, 0), 1) * 255).rounded())
        let b = Int((min(max(ns.blueComponent, 0), 1) * 255).rounded())
        return (r << 16) | (g << 8) | b
    }

    private static func iconForThermostatMode(_ mode: String) -> String {
        switch mode.lowercased() {
        case "cool": return "snowflake"
        case "heat": return "flame.fill"
        case "dry": return "drop.fill"
        case "fan-only", "fan": return "wind"
        case "auto", "heatcool": return "sparkles"
        default: return "dial.medium"
        }
    }

    private static func iconForToggle(_ toggleName: String) -> String {
        switch toggleName.lowercased() {
        case "led_toggle": return "lightbulb.led.fill"
        case "sleep_toggle": return "moon.zzz.fill"
        default: return "switch.2"
        }
    }
}
