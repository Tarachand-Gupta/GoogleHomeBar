import AppKit
import SwiftUI
import GoogleHomeBarCore

struct CastDevicesView: View {
    @Bindable var coordinator: AppCoordinator
    var bottomInsetForDock: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private var isModern: Bool {
        coordinator.settings.uiStyle == .modern
    }

    var body: some View {
        let palette = ModernPalette(colorScheme: colorScheme)

        VStack(spacing: 0) {
            if isModern {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cast & Media")
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundStyle(palette.textPrimary)
                        Text("Local speakers, Nest Hubs, and TVs on your Wi-Fi")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(palette.textSecondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 6)
            }

            if !coordinator.castManager.devices.isEmpty {
                quickActionsBar
                Divider()
            }

            if coordinator.castManager.devices.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(coordinator.castManager.devices) { device in
                            CastDeviceCardView(device: device, useModernSurface: isModern)
                        }
                    }
                    .padding(.horizontal, isModern ? 16 : 12)
                    .padding(.top, 12)
                    .padding(.bottom, bottomInsetForDock ? 78 : 14)
                }
            }
        }
        .background(isModern ? palette.canvas : Color.clear)
        .onAppear {
            coordinator.castManager.startBrowsing()
        }
    }

    private var quickActionsBar: some View {
        let controllable = coordinator.castManager.devices
            .filter { $0.connectionState.isConnected && !$0.volume.isFixedVolume }
        let allMuted = !controllable.isEmpty && controllable.allSatisfy { $0.volume.isMuted }
        let anyActive = coordinator.castManager.devices.contains { $0.hasActiveApp || $0.isPlayingMedia }

        return HStack(spacing: 6) {
            Button {
                coordinator.castManager.muteAll(!allMuted)
            } label: {
                Label(allMuted ? "Unmute All" : "Mute All", systemImage: allMuted ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                coordinator.castManager.adjustAllVolumes(by: -0.1)
            } label: {
                Image(systemName: "speaker.minus.fill")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Lower All Volumes by 10%")

            Button {
                coordinator.castManager.adjustAllVolumes(by: 0.1)
            } label: {
                Image(systemName: "speaker.plus.fill")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Raise All Volumes by 10%")

            if anyActive {
                Button {
                    coordinator.castManager.stopAllPlayback()
                } label: {
                    Label("Stop All", systemImage: "stop.fill")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
            }

            Spacer()

            Button {
                coordinator.castManager.rescan()
            } label: {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Rescan Wi-Fi")
            .help("Rescan Local Wi-Fi for Cast Devices")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.025))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            if coordinator.castManager.isBrowsing {
                ProgressView()
                    .controlSize(.small)
                Text("Scanning Wi-Fi for Google Home & Cast devices…")
                    .font(.headline)
            } else {
                Image(systemName: "hifispeaker.2")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                Text("No Local Cast Devices Found")
                    .font(.headline)
            }

            if let error = coordinator.castManager.browserError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            } else {
                Text("Nest speakers, Nest Hubs, Chromecasts, and Google TVs on the same Wi-Fi appear here automatically for instant local volume and media control.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            Text("If macOS asked for Local Network access, make sure GoogleHomeBar is allowed in System Settings → Privacy & Security → Local Network.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Button("Rescan Wi-Fi") {
                coordinator.castManager.rescan()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Spacer()
        }
        .padding(24)
    }
}

struct CastDeviceCardView: View {
    @Bindable var device: CastDevice
    var useModernSurface: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = ModernPalette(colorScheme: colorScheme)
        let radius: CGFloat = useModernSurface ? 16 : 10

        VStack(alignment: .leading, spacing: 10) {
            topRow

            if let media = device.mediaState {
                nowPlayingRow(media)
            } else if let app = device.activeApp, !app.isIdleScreen {
                activeAppBanner(app)
            }

            volumeRow
        }
        .padding(13)
        .modifier(
            AdaptiveCastCardSurface(
                useModernSurface: useModernSurface,
                radius: radius,
                isPlaying: device.isPlayingMedia,
                palette: palette
            )
        )
        .contextMenu {
            Button("Refresh Status") {
                device.refresh()
            }
            if !device.volume.isFixedVolume {
                Button(device.volume.isMuted ? "Unmute" : "Mute") {
                    device.toggleMute()
                }
            }
            if device.hasActiveApp || device.isPlayingMedia {
                Button("Stop Casting") {
                    device.stopCasting()
                }
            }
            if let addr = device.addressDescription {
                Divider()
                Button("Copy Local Address (\(addr))") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(addr, forType: .string)
                }
            }
        }
    }

    private var topRow: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(device.isPlayingMedia ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.07))
                    .frame(width: 34, height: 34)
                Image(systemName: device.kind.sfSymbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(device.isPlayingMedia ? Color.accentColor : Color.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(device.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    connectionBadge
                }

                Text(device.modelName + (device.mediaState == nil ? " · \(device.statusLine)" : ""))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if device.hasActiveApp || device.isPlayingMedia {
                Button {
                    device.stopCasting()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Stop Casting")
            }
        }
    }

    private var connectionBadge: some View {
        let color: Color = {
            switch device.connectionState {
            case .connected: return .green
            case .connecting: return .orange
            case .disconnected: return .gray
            case .failed: return .red
            }
        }()

        return Circle()
            .fill(color)
            .frame(width: 6.5, height: 6.5)
            .help(device.addressDescription ?? "\(device.connectionState)")
    }

    private func nowPlayingRow(_ media: CastMediaState) -> some View {
        HStack(spacing: 10) {
            if let artworkURL = media.artworkURL {
                AsyncImage(url: artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        artworkFallback
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                artworkFallback
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(media.title ?? device.activeApp?.displayName ?? "Now Playing")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                if let secondary = media.secondaryLine {
                    Text(secondary)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let appName = device.activeApp?.displayName {
                    Text(appName)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                if media.canSkipPrevious {
                    Button {
                        device.skipPrevious()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .help("Previous Track")
                }

                Button {
                    device.togglePlayPause()
                } label: {
                    Image(systemName: media.playerState == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 13))
                        .frame(width: 26, height: 26)
                        .background(Color.accentColor.opacity(0.15), in: Circle())
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help(media.playerState == .playing ? "Pause" : "Play")

                if media.canSkipNext {
                    Button {
                        device.skipNext()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .help("Next Track")
                }
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private func activeAppBanner(_ app: CastActiveApp) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "tv.and.mediabox")
                .font(.system(size: 11))
                .foregroundStyle(.tint)
            Text(app.displayName)
                .font(.system(size: 11.5, weight: .medium))
            if !app.statusText.isEmpty && app.statusText != app.displayName {
                Text("· \(app.statusText)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
    }

    private var artworkFallback: some View {
        ZStack {
            Color.primary.opacity(0.08)
            Image(systemName: "music.note")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    private var volumeRow: some View {
        HStack(spacing: 8) {
            if device.volume.isFixedVolume {
                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Fixed volume output")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                Button {
                    device.toggleMute()
                } label: {
                    Image(systemName: volumeSymbol)
                        .font(.system(size: 12.5))
                        .frame(width: 20)
                        .foregroundStyle(device.volume.isMuted ? .red : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(!device.connectionState.isConnected)
                .accessibilityLabel(device.volume.isMuted ? "Unmute" : "Mute")
                .help(device.volume.isMuted ? "Unmute" : "Mute")

                Slider(
                    value: Binding(
                        get: { device.volume.level },
                        set: { newVal in
                            device.setVolumeLevel(newVal, immediate: false)
                        }
                    ),
                    in: 0...1,
                    onEditingChanged: { editing in
                        device.isAdjustingVolume = editing
                        if !editing {
                            device.setVolumeLevel(device.volume.level, immediate: true)
                        }
                    }
                )
                .controlSize(.small)
                .disabled(!device.connectionState.isConnected)

                Text("\(Int((device.volume.level * 100).rounded()))%")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
        }
    }

    private var volumeSymbol: String {
        if device.volume.isMuted || device.volume.level <= 0.001 {
            return "speaker.slash.fill"
        } else if device.volume.level < 0.35 {
            return "speaker.wave.1.fill"
        } else if device.volume.level < 0.7 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }
}

private struct AdaptiveCastCardSurface: ViewModifier {
    let useModernSurface: Bool
    let radius: CGFloat
    let isPlaying: Bool
    let palette: ModernPalette

    func body(content: Content) -> some View {
        if useModernSurface {
            content
                .background(palette.card, in: RoundedRectangle(cornerRadius: radius))
                .overlay(
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(
                            isPlaying ? AnyShapeStyle(palette.accent.opacity(0.45)) : AnyShapeStyle(palette.glassRimHighlight),
                            lineWidth: 1
                        )
                )
                .shadow(color: palette.cardShadow, radius: 8, y: 3)
        } else {
            content
                .liquidGlassSurface(
                    in: RoundedRectangle(cornerRadius: 14),
                    tint: isPlaying ? Color.accentColor.opacity(0.22) : nil,
                    shadowRadius: 5
                )
        }
    }
}
