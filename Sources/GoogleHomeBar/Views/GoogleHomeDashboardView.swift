import AppKit
import GoogleHomeBarCore
import SwiftUI

struct GoogleHomeDashboardView: View {
    @Bindable var coordinator: AppCoordinator
    var isDetachedHost: Bool
    /// When provided (detached split view), selecting a device updates the parent selection instead of pushing inline.
    var externalSelection: Binding<String?>?

    @State private var inlineSelectedDeviceId: String?

    private var activeSelection: Binding<String?> {
        externalSelection ?? $inlineSelectedDeviceId
    }

    var body: some View {
        Group {
            if coordinator.webController.authState == .signedOut {
                signInPromptView
            } else if coordinator.homeManager.devices.isEmpty {
                loadingDevicesView
            } else if externalSelection == nil,
                      let devId = inlineSelectedDeviceId,
                      let device = coordinator.homeManager.device(id: devId) {
                GoogleHomeDeviceDetailView(
                    device: device,
                    homeManager: coordinator.homeManager,
                    showBackButton: true,
                    onBack: { inlineSelectedDeviceId = nil }
                )
            } else {
                deviceGridDashboard
            }
        }
        .onAppear {
            coordinator.webController.loadIfNeeded()
        }
    }

    // MARK: - Embedded Sign-In (Shown Automatically When Signed Out)

    private var signInPromptView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .foregroundStyle(.tint)
                Text("Sign in with Google to load your Google Home devices")
                    .font(.caption.weight(.medium))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.1))

            Divider()

            GoogleHomeTabView(coordinator: coordinator, isDetachedHost: isDetachedHost)
        }
    }

    // MARK: - Loading State

    private var loadingDevicesView: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView()
                .controlSize(.regular)
            Text("Loading your Google Home devices…")
                .font(.subheadline.weight(.medium))
            Text("Connecting to your signed-in Google account.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Refresh") {
                    Task { await coordinator.homeManager.refreshAll() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Open Sign-In") {
                    coordinator.selectedTab = .web
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(.top, 4)

            Spacer()
        }
        .padding(24)
    }

    // MARK: - Main Custom Native Device Grid

    private var deviceGridDashboard: some View {
        VStack(spacing: 0) {
            dashboardSubheader
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error = coordinator.homeManager.lastError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(error)
                                .font(.caption)
                                .lineLimit(2)
                            Spacer()
                            Button("Retry") {
                                Task { await coordinator.homeManager.refreshAll() }
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                        .foregroundStyle(.orange)
                        .padding(10)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }

                    ForEach(coordinator.homeManager.roomSections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(section.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                let onCount = section.devices.filter { $0.state.isOnline && $0.state.isOn == true }.count
                                if onCount > 0 {
                                    Text("\(onCount) on")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.tint)
                                }
                            }
                            .padding(.horizontal, 2)

                            let columns = isDetachedHost
                                ? [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 10)]
                                : [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(section.devices) { device in
                                    GoogleHomeDeviceTile(
                                        device: device,
                                        isPending: coordinator.homeManager.pendingDeviceIds.contains(device.id),
                                        isSelected: activeSelection.wrappedValue == device.id,
                                        onTapToggle: {
                                            if device.state.isOnline && device.supportsOnOff {
                                                coordinator.homeManager.togglePower(deviceId: device.id)
                                            } else {
                                                openDetails(for: device)
                                            }
                                        },
                                        onOpenControls: {
                                            openDetails(for: device)
                                        }
                                    )
                                }
                            }
                        }
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "hand.tap")
                            .font(.caption2)
                        Text("Click a tile to toggle · Hold (or click sliders) for full controls")
                            .font(.caption2)
                    }
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
                }
                .padding(12)
            }
        }
    }

    private var dashboardSubheader: some View {
        HStack(spacing: 8) {
            if coordinator.homeManager.structures.count > 1 {
                Picker("Home", selection: Binding(
                    get: { coordinator.homeManager.selectedStructureId ?? "" },
                    set: { coordinator.homeManager.selectedStructureId = $0 }
                )) {
                    ForEach(coordinator.homeManager.structures) { home in
                        Text(home.name).tag(home.id)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 140)
            } else if let homeName = coordinator.homeManager.activeStructure?.name {
                Text(homeName)
                    .font(.system(size: 12, weight: .semibold))
            }

            let total = coordinator.homeManager.devicesInSelectedStructure.count
            let active = coordinator.homeManager.activeOnCount
            Text("\(active) on · \(total) device\(total == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if coordinator.homeManager.isRefreshing {
                ProgressView()
                    .controlSize(.mini)
            } else if !isDetachedHost {
                Button {
                    Task { await coordinator.homeManager.refreshAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Refresh Google Home Devices")
                .help("Refresh devices & states")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func openDetails(for device: GoogleHomeDevice) {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        activeSelection.wrappedValue = device.id
    }
}

// MARK: - Tactile Device Tile (Click to Toggle, Click-and-Hold or Sliders Button for Full Controls)

struct GoogleHomeDeviceTile: View {
    let device: GoogleHomeDevice
    let isPending: Bool
    let isSelected: Bool
    let onTapToggle: () -> Void
    let onOpenControls: () -> Void

    @State private var isPressing = false
    @State private var holdTriggered = false
    @State private var holdTask: Task<Void, Never>?

    private var isOn: Bool {
        device.state.isOnline && (device.state.isOn == true)
    }

    private var accentColor: Color {
        GoogleHomeDeviceDetailView.deviceAccentColor(for: device)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    ZStack {
                        Circle()
                            .fill(isOn ? accentColor.opacity(0.28) : Color.primary.opacity(0.08))
                            .frame(width: 34, height: 34)
                        Image(systemName: isOn ? device.deviceType.sfSymbol : device.deviceType.offSymbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(isOn ? accentColor : Color.secondary)
                    }

                    Spacer()

                    if isPending {
                        ProgressView()
                            .controlSize(.mini)
                            .padding(.trailing, 24)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(device.state.isOnline ? .primary : .secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(device.statusSummary)
                        .font(.caption)
                        .foregroundStyle(isOn ? accentColor : Color.secondary)
                        .lineLimit(1)
                }

                if device.deviceType == .light, isOn, let brightness = device.state.brightness {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.12))
                            Capsule()
                                .fill(accentColor)
                                .frame(width: max(6, geo.size.width * CGFloat(brightness) / 100.0))
                        }
                    }
                    .frame(height: 4)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 102, alignment: .topLeading)
            .background(tileBackground, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(tileBorderColor, lineWidth: isSelected ? 1.8 : 1)
            )
            .opacity(device.state.isOnline ? 1.0 : 0.6)
            .scaleEffect(isPressing ? 0.965 : 1.0)
            .animation(.easeOut(duration: 0.14), value: isPressing)
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let movedTooFar = abs(value.translation.width) > 12 || abs(value.translation.height) > 12
                        if movedTooFar {
                            cancelHoldTimer()
                            isPressing = false
                            return
                        }
                        if !isPressing && !holdTriggered {
                            isPressing = true
                            startHoldTimer()
                        }
                    }
                    .onEnded { value in
                        let movedTooFar = abs(value.translation.width) > 12 || abs(value.translation.height) > 12
                        cancelHoldTimer()
                        let didHold = holdTriggered
                        isPressing = false
                        holdTriggered = false
                        if !didHold && !movedTooFar {
                            onTapToggle()
                        }
                    }
            )
            .contextMenu {
                Button("Open Full Controls") {
                    onOpenControls()
                }
                if device.state.isOnline && device.supportsOnOff {
                    Button(isOn ? "Turn Off" : "Turn On") {
                        onTapToggle()
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(device.name), \(device.statusSummary)")
            .accessibilityHint("Click to toggle power, or hold for full controls")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                onTapToggle()
            }

            // Dedicated quick-open Full Controls button in top-right corner
            Button {
                onOpenControls()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isOn ? accentColor : Color.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(9)
            .accessibilityLabel("Full controls for \(device.name)")
            .help("Open full controls (or press & hold tile)")
        }
    }

    private var tileBackground: some ShapeStyle {
        if isOn {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        accentColor.opacity(0.22),
                        accentColor.opacity(0.10),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
    }

    private var tileBorderColor: Color {
        if isSelected {
            return Color.accentColor
        }
        return isOn ? accentColor.opacity(0.45) : Color.primary.opacity(0.09)
    }

    private func startHoldTimer() {
        holdTask?.cancel()
        holdTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 360_000_000)
            guard !Task.isCancelled, isPressing else { return }
            holdTriggered = true
            isPressing = false
            onOpenControls()
        }
    }

    private func cancelHoldTimer() {
        holdTask?.cancel()
        holdTask = nil
    }
}
