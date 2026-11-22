import Foundation
import Network
import Observation
import GoogleHomeBarCore

@Observable
@MainActor
final class CastDevice: Identifiable {
    let id: String
    var name: String
    var modelName: String
    var kind: CastDeviceKind
    var txtStatusText: String
    var addressDescription: String?

    var connectionState: CastConnectionState = .disconnected
    var volume = CastVolumeState()
    var activeApp: CastActiveApp?
    var mediaState: CastMediaState?
    var isStandBy = false

    // Prevent incoming Cast volume callbacks from snapping the slider back while dragging.
    var isAdjustingVolume = false
    private var lastVolumeSendDate: Date = .distantPast
    private var pendingVolumeTask: Task<Void, Never>?

    let endpoint: NWEndpoint
    private var client: CastConnection?

    init(
        id: String,
        name: String,
        modelName: String,
        kind: CastDeviceKind,
        txtStatusText: String,
        endpoint: NWEndpoint
    ) {
        self.id = id
        self.name = name
        self.modelName = modelName
        self.kind = kind
        self.txtStatusText = txtStatusText
        self.endpoint = endpoint
    }

    var isPlayingMedia: Bool {
        mediaState?.playerState == .playing || mediaState?.playerState == .buffering
    }

    var hasActiveApp: Bool {
        if let app = activeApp, !app.isIdleScreen { return true }
        return false
    }

    var statusLine: String {
        if let media = mediaState, let title = media.title, !title.isEmpty {
            return title
        }
        if let app = activeApp, !app.isIdleScreen {
            if !app.statusText.isEmpty && app.statusText != app.displayName {
                return "\(app.displayName) · \(app.statusText)"
            }
            return app.displayName
        }
        if !txtStatusText.isEmpty {
            return txtStatusText
        }
        switch connectionState {
        case .connected: return "Idle"
        case .connecting: return "Connecting…"
        case .disconnected: return "Disconnected"
        case .failed: return "Unavailable"
        }
    }

    func connect() {
        if client != nil {
            client?.refreshStatus()
            return
        }
        let callbacks = CastConnection.Callbacks(
            onStateChange: { [weak self] state, address in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.connectionState = state
                    if let address {
                        self.addressDescription = address
                    }
                }
            },
            onReceiverStatus: { [weak self] update in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let newVol = update.volume, !self.isAdjustingVolume {
                        self.volume = newVol
                    }
                    self.activeApp = update.activeApp
                    if let standBy = update.isStandBy {
                        self.isStandBy = standBy
                    }
                }
            },
            onMediaStatus: { [weak self] media in
                Task { @MainActor [weak self] in
                    self?.mediaState = media
                }
            }
        )
        let connection = CastConnection(deviceId: id, endpoint: endpoint, callbacks: callbacks)
        self.client = connection
        connection.start()
    }

    func disconnect() {
        pendingVolumeTask?.cancel()
        pendingVolumeTask = nil
        client?.stop()
        client = nil
        connectionState = .disconnected
    }

    func refresh() {
        if client == nil {
            connect()
        } else {
            client?.refreshStatus()
        }
    }

    func setVolumeLevel(_ newLevel: Double, immediate: Bool = false) {
        let clamped = min(max(newLevel, 0.0), 1.0)
        volume.level = clamped
        if volume.isMuted && clamped > 0 {
            volume.isMuted = false
        }

        let now = Date()
        if immediate || now.timeIntervalSince(lastVolumeSendDate) >= 0.08 {
            lastVolumeSendDate = now
            pendingVolumeTask?.cancel()
            client?.setVolume(level: clamped)
        } else {
            pendingVolumeTask?.cancel()
            pendingVolumeTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled, let self else { return }
                self.lastVolumeSendDate = Date()
                self.client?.setVolume(level: clamped)
            }
        }
    }

    func toggleMute() {
        let target = !volume.isMuted
        volume.isMuted = target
        client?.setMuted(target)
    }

    func setMuted(_ muted: Bool) {
        volume.isMuted = muted
        client?.setMuted(muted)
    }

    func togglePlayPause() {
        guard let state = mediaState?.playerState else { return }
        if state == .playing || state == .buffering {
            client?.sendMediaCommand("PAUSE")
        } else {
            client?.sendMediaCommand("PLAY")
        }
    }

    func skipNext() {
        client?.skipTrack(delta: 1)
    }

    func skipPrevious() {
        client?.skipTrack(delta: -1)
    }

    func seek(to seconds: Double) {
        client?.seek(to: seconds)
    }

    func stopCasting() {
        if let sessionId = activeApp?.sessionId {
            client?.stopApplication(sessionId: sessionId)
        } else {
            client?.sendMediaCommand("STOP")
        }
    }
}

@Observable
@MainActor
final class CastManager {
    private(set) var devices: [CastDevice] = []
    private(set) var isBrowsing = false
    private(set) var browserError: String?

    private var browser: NWBrowser?
    private let browserQueue = DispatchQueue(label: "com.playground.GoogleHomeBar.cast-browser")
    private var devicesById: [String: CastDevice] = [:]

    var discoveredDeviceIDs: Set<String> {
        Set(devicesById.keys)
    }

    var activePlaybackCount: Int {
        devices.filter { $0.isPlayingMedia }.count
    }

    func startBrowsing() {
        guard browser == nil else { return }
        browserError = nil

        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(
            type: "_googlecast._tcp",
            domain: "local."
        )
        let params = NWParameters()
        params.includePeerToPeer = true

        let newBrowser = NWBrowser(for: descriptor, using: params)
        newBrowser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    self.isBrowsing = true
                    self.browserError = nil
                case .failed(let err):
                    self.isBrowsing = false
                    self.browserError = err.localizedDescription
                case .waiting(let err):
                    self.browserError = "Waiting for local network permission (\(err.localizedDescription))"
                case .cancelled:
                    self.isBrowsing = false
                default:
                    break
                }
            }
        }

        newBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            let parsedEntries = results.map { result -> (NWEndpoint, [String: String]) in
                var dict: [String: String] = [:]
                if case .bonjour(let txtRecord) = result.metadata {
                    for key in ["id", "fn", "md", "rs", "ca", "st"] {
                        if let entry = txtRecord.getEntry(for: key),
                           case .string(let val) = entry {
                            dict[key] = val
                        }
                    }
                }
                return (result.endpoint, dict)
            }

            Task { @MainActor [weak self] in
                self?.reconcileDiscovered(parsedEntries)
            }
        }

        browser = newBrowser
        newBrowser.start(queue: browserQueue)
    }

    func stopBrowsing(disconnectDevices: Bool = false) {
        browser?.cancel()
        browser = nil
        isBrowsing = false

        if disconnectDevices {
            for device in devicesById.values {
                device.disconnect()
            }
            devicesById.removeAll()
            devices = []
        }
    }

    func rescan() {
        stopBrowsing(disconnectDevices: false)
        startBrowsing()
        for device in devices {
            device.refresh()
        }
    }

    func muteAll(_ muted: Bool) {
        for device in devices where device.connectionState.isConnected && !device.volume.isFixedVolume {
            device.setMuted(muted)
        }
    }

    func stopAllPlayback() {
        for device in devices where device.hasActiveApp || device.isPlayingMedia {
            device.stopCasting()
        }
    }

    func adjustAllVolumes(by delta: Double) {
        for device in devices where device.connectionState.isConnected && !device.volume.isFixedVolume {
            device.setVolumeLevel(device.volume.level + delta, immediate: true)
        }
    }

    private func reconcileDiscovered(_ entries: [(NWEndpoint, [String: String])]) {
        var seenIds = Set<String>()

        for (endpoint, txt) in entries {
            let parsed = CastPayloadParser.parseTXTRecord(txt)
            // Fall back to endpoint debug description if TXT record has no id yet.
            let stableId = txt["id"] ?? "\(endpoint)"
            seenIds.insert(stableId)

            let kind = CastDeviceKind.infer(modelName: parsed.model, capabilitiesMask: parsed.capabilitiesMask)

            if let existing = devicesById[stableId] {
                existing.name = parsed.name
                existing.modelName = parsed.model
                existing.kind = kind
                existing.txtStatusText = parsed.statusText
                if existing.connectionState == .disconnected {
                    existing.connect()
                }
            } else {
                let device = CastDevice(
                    id: stableId,
                    name: parsed.name,
                    modelName: parsed.model,
                    kind: kind,
                    txtStatusText: parsed.statusText,
                    endpoint: endpoint
                )
                devicesById[stableId] = device
                device.connect()
            }
        }

        // Remove devices no longer advertised on mDNS.
        let removedIds = Set(devicesById.keys).subtracting(seenIds)
        for id in removedIds {
            devicesById[id]?.disconnect()
            devicesById.removeValue(forKey: id)
        }

        devices = devicesById.values.sorted { lhs, rhs in
            if lhs.isPlayingMedia != rhs.isPlayingMedia {
                return lhs.isPlayingMedia && !rhs.isPlayingMedia
            }
            if lhs.kind == .speakerGroup, rhs.kind != .speakerGroup {
                return false
            }
            if lhs.kind != .speakerGroup, rhs.kind == .speakerGroup {
                return true
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
