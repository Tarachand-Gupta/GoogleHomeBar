import AppKit
import GoogleHomeBarCore
import SwiftUI

struct ModernDashboardView: View {
    @Bindable var coordinator: AppCoordinator
    var isDetachedHost: Bool
    var externalSelection: Binding<String?>?
    @Binding var inlineSelectedDeviceId: String?

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedRoomFilter: String = "__ALL__"
    @State private var searchQuery: String = ""

    private var activeSelection: Binding<String?> {
        externalSelection ?? $inlineSelectedDeviceId
    }

    var body: some View {
        let palette = ModernPalette(colorScheme: colorScheme)

        Group {
            if coordinator.webController.authState == .signedOut {
                GoogleSignInGateView(coordinator: coordinator, isDetachedHost: isDetachedHost)
            } else if coordinator.homeManager.devices.isEmpty {
                modernLoadingView(palette: palette)
            } else if externalSelection == nil {
                let expandedDevice = inlineSelectedDeviceId.flatMap { coordinator.homeManager.device(id: $0) }
                let isExpanded = expandedDevice != nil

                ZStack {
                    dashboardContent(palette: palette)
                        .scaleEffect(isExpanded ? 0.93 : 1.0)
                        .opacity(isExpanded ? 0.0 : 1.0)
                        .allowsHitTesting(!isExpanded)
                        .accessibilityHidden(isExpanded)

                    if let device = expandedDevice {
                        ModernDeviceDetailView(
                            device: device,
                            allDevices: coordinator.homeManager.devicesInSelectedStructure,
                            homeManager: coordinator.homeManager,
                            showBackButton: true,
                            onSelectDevice: { nextId in
                                withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                                    inlineSelectedDeviceId = nextId
                                }
                            },
                            onBack: {
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                    inlineSelectedDeviceId = nil
                                }
                            }
                        )
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.86, anchor: .center)
                                    .combined(with: .opacity)
                                    .combined(with: .offset(y: 14)),
                                removal: .scale(scale: 0.88, anchor: .center)
                                    .combined(with: .opacity)
                                    .combined(with: .offset(y: 10))
                            )
                        )
                        .zIndex(1)
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: inlineSelectedDeviceId != nil)
            } else {
                dashboardContent(palette: palette)
            }
        }
        .background(palette.canvas)
        .onAppear {
            if !coordinator.homeManager.isDemoMode {
                coordinator.webController.loadIfNeeded()
            }
        }
    }

    // MARK: - Main Dashboard Content

    private func dashboardContent(palette: ModernPalette) -> some View {
        let roomNames = coordinator.homeManager.roomSections.map(\.name)
        let effectiveRoom = roomNames.contains(selectedRoomFilter) ? selectedRoomFilter : "__ALL__"
        let totalInHome = coordinator.homeManager.devicesInSelectedStructure.count
        let displayedDevices = filteredDevices(roomFilter: effectiveRoom, query: searchQuery)
        let featuredAC = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (pickFeaturedClimateDevice(from: displayedDevices)
                ?? pickFeaturedClimateDevice(from: coordinator.homeManager.devicesInSelectedStructure))
            : nil

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                topHeader(palette: palette)

                if totalInHome > 6 {
                    deviceSearchField(palette: palette)
                }

                if coordinator.sessionOverrideActive {
                    sessionOverrideChip(palette: palette)
                }

                if let error = coordinator.homeManager.lastError {
                    errorChip(error, palette: palette)
                }

                if let ac = featuredAC {
                    ModernClimateHeroCard(
                        device: ac,
                        homeManager: coordinator.homeManager,
                        onOpenControls: { openDetails(for: ac) }
                    )
                }

                if roomNames.count > 1 {
                    roomFilterStrip(roomNames: roomNames, active: effectiveRoom, palette: palette)
                }

                let columns = isDetachedHost
                    ? [GridItem(.adaptive(minimum: 185, maximum: 260), spacing: 12)]
                    : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

                if displayedDevices.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 22))
                            .foregroundStyle(palette.textMuted)
                        Text("No matching devices")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(displayedDevices) { device in
                            ModernDeviceCard(
                                device: device,
                                isPending: coordinator.homeManager.pendingDeviceIds.contains(device.id),
                                isSelected: activeSelection.wrappedValue == device.id,
                                onTogglePower: { nextOn in
                                    coordinator.homeManager.setPower(deviceId: device.id, on: nextOn)
                                },
                                onOpenControls: {
                                    openDetails(for: device)
                                }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, isDetachedHost ? 20 : 76)
            .frame(maxWidth: 660)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Header

    private func topHeader(palette: ModernPalette) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                if coordinator.homeManager.structures.count > 1 {
                    Menu {
                        ForEach(coordinator.homeManager.structures) { home in
                            Button {
                                coordinator.homeManager.selectedStructureId = home.id
                                selectedRoomFilter = "__ALL__"
                            } label: {
                                HStack {
                                    Text(home.name)
                                    if coordinator.homeManager.selectedStructureId == home.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Text(coordinator.homeManager.activeStructure?.name ?? "Google Home")
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundStyle(palette.textPrimary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                } else {
                    Text(coordinator.homeManager.activeStructure?.name ?? "Google Home")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.textPrimary)
                }

                Text(greetingSubtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
            }

            Spacer(minLength: 8)

            // Ambient climate / active count pill + Liquid Glass action cluster
            LiquidGlassGroup(spacing: 8) {
                HStack(spacing: 7) {
                    climateStatusPill(palette: palette)

                    if !isDetachedHost {
                        Button {
                            toggleAppearanceQuick()
                        } label: {
                            Image(systemName: colorScheme == .dark ? "sun.max.fill" : "moon.fill")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(palette.textPrimary)
                                .frame(width: 32, height: 32)
                                .liquidGlassSurface(in: Circle(), interactive: true, shadowRadius: 5)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.liquidGlassCircle)
                        .accessibilityLabel(colorScheme == .dark ? "Switch to Light Mode" : "Switch to Dark Mode")
                        .help(colorScheme == .dark ? "Switch to Light Mode" : "Switch to Dark Mode")

                        Button {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                            coordinator.refreshAll()
                        } label: {
                            Group {
                                if coordinator.homeManager.isRefreshing {
                                    ProgressView()
                                        .controlSize(.mini)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(palette.textPrimary)
                                }
                            }
                            .frame(width: 32, height: 32)
                            .liquidGlassSurface(in: Circle(), interactive: true, shadowRadius: 5)
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
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(palette.textPrimary)
                                .frame(width: 32, height: 32)
                                .liquidGlassSurface(in: Circle(), interactive: true, shadowRadius: 5)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.liquidGlassCircle)
                        .accessibilityLabel("Open in Window")
                        .help("Open in Resizable Window")
                    }
                }
            }
        }
    }

    private func climateStatusPill(palette: ModernPalette) -> some View {
        let temps = coordinator.homeManager.devicesInSelectedStructure.compactMap(\.state.ambientTempC)
        let avgTemp: Int? = temps.isEmpty ? nil : Int((temps.reduce(0, +) / Double(temps.count)).rounded())
        let activeCount = coordinator.homeManager.activeOnCount

        return HStack(spacing: 6) {
            Image(systemName: avgTemp != nil ? "thermometer.medium" : "house.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.accent)

            VStack(alignment: .leading, spacing: 0) {
                if let avgTemp {
                    Text("\(avgTemp)°C")
                        .font(.system(size: 11.5, weight: .bold).monospacedDigit())
                        .foregroundStyle(palette.textPrimary)
                    Text("\(activeCount) on")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                } else {
                    Text("\(activeCount) on")
                        .font(.system(size: 11.5, weight: .bold).monospacedDigit())
                        .foregroundStyle(palette.textPrimary)
                    Text("\(coordinator.homeManager.devicesInSelectedStructure.count) devices")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .liquidGlassSurface(in: Capsule(), shadowRadius: 5)
    }

    // MARK: - Search & Room Filter Pills

    private func deviceSearchField(palette: ModernPalette) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.textMuted)
            TextField("Search devices or rooms…", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(palette.textPrimary)
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.textMuted)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(palette.card, in: Capsule())
        .overlay(Capsule().strokeBorder(palette.border, lineWidth: 1))
    }

    private func roomFilterStrip(roomNames: [String], active: String, palette: ModernPalette) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                roomPill(label: "All Rooms", isSelected: active == "__ALL__", palette: palette) {
                    selectedRoomFilter = "__ALL__"
                }
                ForEach(roomNames, id: \.self) { room in
                    roomPill(label: room, isSelected: active == room, palette: palette) {
                        selectedRoomFilter = room
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
        }
        .frame(height: 36)
        .horizontalEdgeFade(width: 14)
        .padding(.horizontal, -12)
    }

    private func roomPill(
        label: String,
        isSelected: Bool,
        palette: ModernPalette,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                action()
            }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.white : palette.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(palette.accentGradient)
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 0.75))
                            .shadow(color: palette.accent.opacity(0.30), radius: 6, y: 2)
                    }
                }
                .modifier(ConditionalGlassPillModifier(isGlass: !isSelected))
                .contentShape(Capsule())
        }
        .buttonStyle(.liquidGlassCapsule)
    }

    // MARK: - Auxiliary States

    private func sessionOverrideChip(palette: ModernPalette) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.open.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            Text("Session Wi-Fi override active")
                .font(.caption.weight(.medium))
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Button("Re-lock") {
                coordinator.sessionOverrideActive = false
            }
            .buttonStyle(.link)
            .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(palette.isDark ? 0.16 : 0.11), in: RoundedRectangle(cornerRadius: 12))
    }

    private func errorChip(_ message: String, palette: ModernPalette) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
            Spacer()
            Button("Retry") {
                Task { await coordinator.homeManager.refreshAll() }
            }
            .buttonStyle(.link)
            .font(.caption.weight(.semibold))
        }
        .padding(10)
        .background(Color.orange.opacity(palette.isDark ? 0.18 : 0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private func modernSignInPrompt(palette: ModernPalette) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .foregroundStyle(palette.accent)
                Text("Sign in with Google to control your Google Home devices")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(palette.accent.opacity(palette.isDark ? 0.18 : 0.10))

            Divider()

            GoogleHomeTabView(coordinator: coordinator, isDetachedHost: isDetachedHost)
        }
    }

    private func modernLoadingView(palette: ModernPalette) -> some View {
        VStack(spacing: 14) {
            Spacer()
            ZStack {
                Circle()
                    .fill(palette.card)
                    .frame(width: 64, height: 64)
                    .shadow(color: palette.cardShadow, radius: 10, y: 4)
                ProgressView()
                    .controlSize(.regular)
            }

            Text("Connecting to Google Home…")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.textPrimary)

            Text("Loading rooms, live temperatures, and device states.")
                .font(.caption)
                .foregroundStyle(palette.textSecondary)

            HStack(spacing: 10) {
                Button("Refresh") {
                    Task { await coordinator.homeManager.refreshAll() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Open Web Sign-In") {
                    coordinator.selectedTab = .web
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Helpers

    private var greetingSubtitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let greeting: String
        switch hour {
        case 5..<12: greeting = "Good Morning"
        case 12..<17: greeting = "Good Afternoon"
        case 17..<22: greeting = "Good Evening"
        default: greeting = "Good Night"
        }
        let total = coordinator.homeManager.devicesInSelectedStructure.count
        return "\(greeting) · \(total) device\(total == 1 ? "" : "s")"
    }

    private func filteredDevices(roomFilter: String, query: String) -> [GoogleHomeDevice] {
        let base: [GoogleHomeDevice]
        if roomFilter == "__ALL__" {
            base = coordinator.homeManager.roomSections.flatMap(\.devices)
        } else {
            base = coordinator.homeManager.roomSections
                .first(where: { $0.name == roomFilter })?
                .devices ?? coordinator.homeManager.roomSections.flatMap(\.devices)
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        return base.filter { dev in
            dev.name.localizedCaseInsensitiveContains(trimmed)
                || dev.roomName.localizedCaseInsensitiveContains(trimmed)
                || (dev.manufacturer?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    private func pickFeaturedClimateDevice(from list: [GoogleHomeDevice]) -> GoogleHomeDevice? {
        let climate = list.filter { $0.supportsTemperatureSetting }
        if let activeOn = climate.first(where: { $0.state.isOnline && $0.state.isOn == true }) {
            return activeOn
        }
        if let online = climate.first(where: { $0.state.isOnline }) {
            return online
        }
        return climate.first
    }

    private func toggleAppearanceQuick() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        coordinator.settings.appearanceMode = (colorScheme == .dark) ? .light : .dark
    }

    private func openDetails(for device: GoogleHomeDevice) {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            activeSelection.wrappedValue = device.id
        }
    }
}

private struct ConditionalGlassPillModifier: ViewModifier {
    let isGlass: Bool
    func body(content: Content) -> some View {
        if isGlass {
            content.liquidGlassSurface(in: Capsule(), interactive: true, shadowRadius: 4)
        } else {
            content
        }
    }
}

// MARK: - Featured Climate Hero Card (Matches Reference AC Card)

struct ModernClimateHeroCard: View {
    let device: GoogleHomeDevice
    @Bindable var homeManager: GoogleHomeManager
    let onOpenControls: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var isOn: Bool {
        device.state.isOnline && (device.state.isOn == true)
    }

    private var currentTarget: Double {
        device.state.targetTempC ?? device.state.ambientTempC ?? 24
    }

    var body: some View {
        let palette = ModernPalette(colorScheme: colorScheme)
        let unit = device.state.temperatureUnit

        ZStack {
            // Layered atmospheric gradient backdrop
            LinearGradient(
                colors: palette.heroGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Soft architectural lighting highlight
            Circle()
                .fill(Color.white.opacity(palette.isDark ? 0.06 : 0.16))
                .frame(width: 190, height: 190)
                .blur(radius: 26)
                .offset(x: -110, y: -55)

            Circle()
                .fill(palette.accent.opacity(palette.isDark ? 0.20 : 0.22))
                .frame(width: 160, height: 160)
                .blur(radius: 30)
                .offset(x: 120, y: -30)

            VStack(spacing: 10) {
                // Top title + arrow button
                HStack(spacing: 6) {
                    Image(systemName: "snowflake")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.95))

                    Text(device.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)

                    if let ambient = device.state.ambientTempC {
                        Text("· Room \(Int(ambient.rounded()))°\(unit)")
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(Color.white.opacity(0.82))
                    }

                    Spacer()

                    Button(action: onOpenControls) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(palette.isDark ? Color.white : palette.textPrimary)
                            .frame(width: 28, height: 28)
                            .liquidGlassSurface(in: Circle(), interactive: true, shadowRadius: 4)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.liquidGlassCircle)
                    .accessibilityLabel("Open \(device.name) full controls")
                }

                // Center temperature adjuster: [-]  26°  [+]
                LiquidGlassGroup(spacing: 14) {
                    HStack(spacing: 18) {
                        Button {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                            let next = max(device.state.minTempC, currentTarget - 1)
                            homeManager.setThermostatSetpoint(deviceId: device.id, tempC: next, debounced: false)
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.white)
                                .frame(width: 32, height: 32)
                                .liquidGlassSurface(in: Circle(), interactive: true, clearStyle: true)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.liquidGlassCircle)
                        .disabled(!device.state.isOnline || currentTarget <= device.state.minTempC)
                        .accessibilityLabel("Decrease \(device.name) temperature")

                        Text("\(Int(currentTarget.rounded()))°")
                            .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.white)
                            .shadow(color: Color.black.opacity(0.16), radius: 4, y: 1)
                            .frame(minWidth: 68)

                        Button {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                            let next = min(device.state.maxTempC, currentTarget + 1)
                            homeManager.setThermostatSetpoint(deviceId: device.id, tempC: next, debounced: false)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.white)
                                .frame(width: 32, height: 32)
                                .liquidGlassSurface(in: Circle(), interactive: true, clearStyle: true)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.liquidGlassCircle)
                        .disabled(!device.state.isOnline || currentTarget >= device.state.maxTempC)
                        .accessibilityLabel("Increase \(device.name) temperature")
                    }
                    .padding(.vertical, 2)
                }

                // Bottom frosted glass strip: Room + Quick Mode Circles
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(device.roomName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                        Text(isOn
                             ? (device.state.thermostatMode.map(GoogleHomeDevice.prettyThermostatMode) ?? "On")
                             : "Off")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(isOn ? palette.accent : palette.textSecondary)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        ForEach(device.state.availableThermostatModes.prefix(4), id: \.self) { mode in
                            let active = isOn && device.state.thermostatMode?.lowercased() == mode.lowercased()
                            Button {
                                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                                homeManager.setThermostatMode(deviceId: device.id, mode: mode)
                            } label: {
                                Image(systemName: Self.modeSymbol(mode))
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(active ? Color.white : palette.textSecondary)
                                    .frame(width: 28, height: 28)
                                    .background {
                                        if active {
                                            Circle().fill(palette.accentGradient)
                                        } else {
                                            Circle().fill(palette.surfaceSubtle)
                                        }
                                    }
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.liquidGlassCircle)
                            .disabled(!device.state.isOnline)
                            .accessibilityLabel("\(device.name) \(GoogleHomeDevice.prettyThermostatMode(mode)) mode")
                            .help(GoogleHomeDevice.prettyThermostatMode(mode))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13))
                .background(palette.heroStripFill, in: RoundedRectangle(cornerRadius: 13))
                .overlay(
                    RoundedRectangle(cornerRadius: 13)
                        .strokeBorder(palette.glassRimHighlight, lineWidth: 0.75)
                )
            }
            .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.white.opacity(palette.isDark ? 0.10 : 0.35), lineWidth: 1)
        )
        .shadow(color: palette.cardShadow, radius: 12, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .onTapGesture {
            onOpenControls()
        }
    }

    static func modeSymbol(_ mode: String) -> String {
        switch mode.lowercased() {
        case "cool": return "snowflake"
        case "heat": return "flame.fill"
        case "dry": return "drop.fill"
        case "fan-only", "fan": return "wind"
        case "auto", "heatcool": return "sparkles"
        default: return "dial.medium"
        }
    }
}

// MARK: - Modern Device Card (Click Card to Expand Controls; Dedicated On/Off Switch Toggles Power)

struct ModernDeviceCard: View {
    let device: GoogleHomeDevice
    let isPending: Bool
    let isSelected: Bool
    let onTogglePower: (Bool) -> Void
    let onOpenControls: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var isOn: Bool {
        device.state.isOnline && (device.state.isOn == true)
    }

    /// Ensures light-bulb and device accents stay luminous and high-contrast in both Light & Dark mode.
    private func cardAccent(palette: ModernPalette) -> Color {
        GoogleHomeColorUtil.accentColor(for: device, isDark: palette.isDark)
    }

    var body: some View {
        let palette = ModernPalette(colorScheme: colorScheme)
        let deviceAccent = cardAccent(palette: palette)

        // Base tactile card surface: clicking anywhere outside the On/Off switch expands full controls.
        Button(action: onOpenControls) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 13)
                            .fill(
                                isOn
                                    ? LinearGradient(
                                        colors: [
                                            deviceAccent.opacity(palette.isDark ? 0.34 : 0.22),
                                            deviceAccent.opacity(palette.isDark ? 0.16 : 0.09),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    : LinearGradient(
                                        colors: [palette.surfaceSubtle, palette.surfaceSubtle],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                            )
                            .frame(width: 42, height: 42)
                            .shadow(color: isOn ? deviceAccent.opacity(0.24) : .clear, radius: 8, y: 3)

                        Image(systemName: isOn ? device.deviceType.sfSymbol : device.deviceType.offSymbol)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(isOn ? deviceAccent : palette.textSecondary)
                    }

                    Spacer()

                    if isPending {
                        ProgressView()
                            .controlSize(.mini)
                            .padding(.top, 5)
                            .padding(.trailing, 32)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(device.state.isOnline ? palette.textPrimary : palette.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitleLine)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isOn ? palette.accent : palette.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                HStack(alignment: .center) {
                    Image(systemName: smallStatusIcon)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(isOn ? deviceAccent : palette.textMuted)
                    Spacer()
                }
                .frame(height: 26)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        isSelected ? AnyShapeStyle(palette.accent) : AnyShapeStyle(palette.glassRimHighlight),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(color: palette.cardShadow, radius: 10, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(LiquidGlassPressStyle(shape: RoundedRectangle(cornerRadius: 18), pressScale: 0.962, flashOpacity: 0.14))
        .contextMenu {
            Button("Open Full Controls") {
                onOpenControls()
            }
            if device.state.isOnline && device.supportsOnOff {
                Button(isOn ? "Turn Off" : "Turn On") {
                    onTogglePower(!isOn)
                }
            }
        }
        .accessibilityLabel("\(device.name), \(subtitleLine)")
        .accessibilityHint("Click to open full controls")
        .overlay(alignment: .topTrailing) {
            Button(action: onOpenControls) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 28, height: 28)
                    .liquidGlassSurface(in: Circle(), interactive: true)
                    .contentShape(Circle())
            }
            .buttonStyle(.liquidGlassCircle)
            .padding(12)
            .accessibilityLabel("Full controls for \(device.name)")
            .help("Open full controls")
        }
        .overlay(alignment: .bottomTrailing) {
            Group {
                if device.supportsOnOff {
                    ModernPillToggle(
                        isOn: isOn,
                        isDisabled: !device.state.isOnline,
                        accentColor: palette.accent
                    ) { nextOn in
                        onTogglePower(nextOn)
                    }
                    .accessibilityLabel("Toggle \(device.name)")
                } else {
                    Button(action: onOpenControls) {
                        Text(device.state.openPercent.map { "\($0)%" } ?? "Controls")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(palette.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .liquidGlassSurface(in: Capsule(), interactive: true)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.liquidGlassCapsule)
                }
            }
            .padding(13)
        }
        .opacity(device.state.isOnline ? 1.0 : 0.62)
    }

    private var subtitleLine: String {
        if !device.state.isOnline {
            return "\(device.roomName) · Offline"
        }
        if isOn {
            return "\(device.roomName) · \(device.statusSummary)"
        }
        return device.roomName
    }

    private var smallStatusIcon: String {
        switch device.deviceType {
        case .light: return "sun.max"
        case .airConditioner, .thermostat, .heater: return "thermometer.medium"
        case .fan, .airPurifier: return "wind"
        case .humidifier: return "drop"
        case .outlet, .switchDevice: return "bolt"
        case .speaker, .tv: return "speaker.wave.2"
        case .blinds: return "blinds.horizontal.open"
        case .vacuum, .appliance: return "play.circle"
        case .camera: return "video"
        case .lock: return "lock"
        case .sensor: return "waveform.path.ecg"
        case .other: return "power"
        }
    }
}
