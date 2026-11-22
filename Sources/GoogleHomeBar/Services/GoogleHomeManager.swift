import Foundation
import GoogleHomeBarCore
import Observation
import os

struct GoogleHomeRoomSection: Identifiable, Equatable {
    let id: String
    let name: String
    let devices: [GoogleHomeDevice]
}

@Observable
@MainActor
final class GoogleHomeManager {
    private let logger = Logger(subsystem: "com.playground.GoogleHomeBar", category: "GoogleHomeManager")
    private let webController: GoogleHomeWebController

    var structures: [GoogleHomeStructure] = []
    var selectedStructureId: String?
    var devices: [GoogleHomeDevice] = []
    var pendingDeviceIds: Set<String> = []
    var isRefreshing = false
    var lastUpdated: Date?
    var lastError: String?

    private var cachedTraitStates: [String: GoogleHomeTraitState] = [:]
    private var debounceTasks: [String: Task<Void, Never>] = [:]
    private var pollTask: Task<Void, Never>?

    init(webController: GoogleHomeWebController) {
        self.webController = webController

        webController.onHomeGraphPayload = { [weak self] data in
            self?.handleHomeGraph(data)
        }
        webController.onTraitsPayload = { [weak self] data in
            self?.handleTraits(data)
        }
    }

    var activeStructure: GoogleHomeStructure? {
        if let id = selectedStructureId, let match = structures.first(where: { $0.id == id }) {
            return match
        }
        return structures.first
    }

    var devicesInSelectedStructure: [GoogleHomeDevice] {
        guard let sid = activeStructure?.id else { return devices }
        return devices.filter { $0.structureId == sid }
    }

    var roomSections: [GoogleHomeRoomSection] {
        let visible = devicesInSelectedStructure
        guard !visible.isEmpty else { return [] }

        var grouped: [String: [GoogleHomeDevice]] = [:]
        var order: [String] = []

        // Preserve Google Home's room ordering first
        if let structRooms = activeStructure?.rooms {
            for r in structRooms {
                if visible.contains(where: { $0.roomName == r.name }) {
                    order.append(r.name)
                }
            }
        }
        for dev in visible {
            grouped[dev.roomName, default: []].append(dev)
            if !order.contains(dev.roomName) {
                order.append(dev.roomName)
            }
        }

        return order.compactMap { roomName in
            guard let list = grouped[roomName], !list.isEmpty else { return nil }
            let sorted = list.sorted { lhs, rhs in
                if lhs.state.isOnline != rhs.state.isOnline { return lhs.state.isOnline }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return GoogleHomeRoomSection(id: roomName, name: roomName, devices: sorted)
        }
    }

    var activeOnCount: Int {
        devicesInSelectedStructure.filter { $0.state.isOnline && $0.state.isOn == true }.count
    }

    func device(id: String) -> GoogleHomeDevice? {
        devices.first(where: { $0.id == id })
    }

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if Task.isCancelled { break }
                guard let self, self.webController.authState == .signedIn, !self.devices.isEmpty else { continue }
                await self.refreshTraits(silent: true)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func resetForSignOut() {
        stopPolling()
        structures = []
        selectedStructureId = nil
        devices = []
        cachedTraitStates = [:]
        pendingDeviceIds = []
        lastError = nil
        lastUpdated = nil
    }

    // MARK: - Refresh HomeGraph & Traits

    func refreshAll() async {
        lastError = nil
        isRefreshing = true
        defer { isRefreshing = false }

        let hg = await webController.refreshHomeGraphRPC()
        if hg.ok, let data = hg.body.data(using: .utf8) {
            handleHomeGraph(data)
            await refreshTraits(silent: false)
        } else if hg.status == 401 || hg.status == 403 {
            webController.reload()
        } else if devices.isEmpty {
            webController.reload()
        } else {
            await refreshTraits(silent: false)
        }
    }

    func refreshTraits(for deviceIds: [String]? = nil, silent: Bool = false) async {
        let targets = deviceIds ?? devices.map(\.id)
        guard !targets.isEmpty else { return }

        if !silent { isRefreshing = true }
        defer { if !silent { isRefreshing = false } }

        let reqBody = GoogleHomeFoyerCodec.buildGetTraitsBody(deviceIds: targets)
        let res = await webController.callFoyerRPC(
            path: "google.internal.home.foyer.v1.HomeControlService/GetTraits",
            bodyJSON: reqBody
        )
        if res.ok, let data = res.body.data(using: .utf8) {
            handleTraits(data)
            lastError = nil
        } else if !silent, let err = res.error {
            lastError = err
        }
    }

    // MARK: - Live Device Commands (HomeControlService/UpdateTraits)

    func togglePower(deviceId: String) {
        guard let dev = device(id: deviceId) else { return }
        let targetOn = !(dev.state.isOn ?? false)
        setPower(deviceId: deviceId, on: targetOn)
    }

    func setPower(deviceId: String, on: Bool) {
        mutateDevice(id: deviceId) { $0.state.isOn = on }
        sendUpdate(deviceId: deviceId, updates: [.onOff(on)], debounceKey: nil)
    }

    func setBrightness(deviceId: String, percent: Int, debounced: Bool = true) {
        let clamped = min(max(percent, 1), 100)
        mutateDevice(id: deviceId) {
            $0.state.isOn = true
            $0.state.brightness = clamped
        }
        sendUpdate(
            deviceId: deviceId,
            updates: [.brightness(clamped)],
            debounceKey: debounced ? "\(deviceId).brightness" : nil
        )
    }

    func setColorRGB(deviceId: String, rgbInt: Int, debounced: Bool = false) {
        mutateDevice(id: deviceId) {
            $0.state.isOn = true
            $0.state.colorRGB = rgbInt
            $0.state.colorTemperatureK = nil
        }
        sendUpdate(
            deviceId: deviceId,
            updates: [.colorRGB(rgbInt)],
            debounceKey: debounced ? "\(deviceId).color" : nil
        )
    }

    func setColorTemperature(deviceId: String, kelvin: Int, debounced: Bool = true) {
        mutateDevice(id: deviceId) {
            $0.state.isOn = true
            $0.state.colorTemperatureK = kelvin
            $0.state.colorRGB = nil
        }
        sendUpdate(
            deviceId: deviceId,
            updates: [.colorTemperature(kelvin)],
            debounceKey: debounced ? "\(deviceId).color" : nil
        )
    }

    func setThermostatMode(deviceId: String, mode: String) {
        mutateDevice(id: deviceId) {
            $0.state.isOn = (mode.lowercased() != "off")
            $0.state.thermostatMode = mode
        }
        var updates: [GoogleHomeTraitUpdate] = [.thermostat(mode: mode, setpointC: nil)]
        if mode.lowercased() != "off" && device(id: deviceId)?.state.isOn != true {
            updates.insert(.onOff(true), at: 0)
        }
        sendUpdate(deviceId: deviceId, updates: updates, debounceKey: nil)
    }

    func setThermostatSetpoint(deviceId: String, tempC: Double, debounced: Bool = true) {
        let rounded = tempC.rounded()
        let curMode = device(id: deviceId)?.state.thermostatMode
        mutateDevice(id: deviceId) {
            $0.state.isOn = true
            $0.state.targetTempC = rounded
        }
        sendUpdate(
            deviceId: deviceId,
            updates: [.thermostat(mode: curMode, setpointC: rounded)],
            debounceKey: debounced ? "\(deviceId).temp" : nil
        )
    }

    func setFanSpeed(deviceId: String, speedName: String) {
        mutateDevice(id: deviceId) {
            $0.state.isOn = true
            $0.state.currentFanSpeed = speedName
        }
        sendUpdate(deviceId: deviceId, updates: [.fanSpeed(speedName)], debounceKey: nil)
    }

    func setMode(deviceId: String, modeName: String, settingName: String) {
        mutateDevice(id: deviceId) { dev in
            if let idx = dev.state.modes.firstIndex(where: { $0.modeName == modeName }) {
                dev.state.modes[idx].currentSetting = settingName
            }
        }
        sendUpdate(deviceId: deviceId, updates: [.mode(name: modeName, setting: settingName)], debounceKey: nil)
    }

    func setToggle(deviceId: String, toggleName: String, enabled: Bool) {
        mutateDevice(id: deviceId) { dev in
            if let idx = dev.state.toggles.firstIndex(where: { $0.toggleName == toggleName }) {
                dev.state.toggles[idx].isOn = enabled
            }
        }
        sendUpdate(deviceId: deviceId, updates: [.toggle(name: toggleName, enabled: enabled)], debounceKey: nil)
    }

    func setOpenPercent(deviceId: String, percent: Int, debounced: Bool = true) {
        let clamped = min(max(percent, 0), 100)
        mutateDevice(id: deviceId) { $0.state.openPercent = clamped }
        sendUpdate(
            deviceId: deviceId,
            updates: [.openPercent(clamped)],
            debounceKey: debounced ? "\(deviceId).open" : nil
        )
    }

    func setLocked(deviceId: String, locked: Bool) {
        mutateDevice(id: deviceId) { $0.state.isLocked = locked }
        sendUpdate(deviceId: deviceId, updates: [.lock(locked)], debounceKey: nil)
    }

    // MARK: - Internal Dispatch & Merging

    private func sendUpdate(
        deviceId: String,
        updates: [GoogleHomeTraitUpdate],
        debounceKey: String?
    ) {
        let taskKey = debounceKey ?? "\(deviceId).immediate.\(UUID().uuidString)"
        if let debounceKey {
            debounceTasks[debounceKey]?.cancel()
        }
        let delayNs: UInt64 = debounceKey != nil ? 180_000_000 : 0

        let task = Task { @MainActor [weak self] in
            if delayNs > 0 {
                try? await Task.sleep(nanoseconds: delayNs)
                if Task.isCancelled { return }
            }
            guard let self else { return }
            await self.executeUpdate(deviceId: deviceId, updates: updates)
            if let debounceKey {
                self.debounceTasks.removeValue(forKey: debounceKey)
            }
        }
        if let debounceKey {
            debounceTasks[debounceKey] = task
        } else {
            _ = taskKey
        }
    }

    private func executeUpdate(deviceId: String, updates: [GoogleHomeTraitUpdate]) async {
        pendingDeviceIds.insert(deviceId)
        lastError = nil

        let body = GoogleHomeFoyerCodec.buildUpdateTraitsBody(deviceId: deviceId, updates: updates)
        let res = await webController.callFoyerRPC(
            path: "google.internal.home.foyer.v1.HomeControlService/UpdateTraits",
            bodyJSON: body
        )

        if res.ok {
            if let data = res.body.data(using: .utf8) {
                handleTraits(data)
            }
            // Schedule a quick verification poll so confirmed device state reflects any clamping/side-effects
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                await self?.refreshTraits(for: [deviceId], silent: true)
                self?.pendingDeviceIds.remove(deviceId)
            }
        } else {
            pendingDeviceIds.remove(deviceId)
            lastError = res.error ?? "Command failed (HTTP \(res.status))."
            logger.error("UpdateTraits failed for \(deviceId, privacy: .public): status=\(res.status) err=\(res.error ?? "", privacy: .public)")
            // Roll back optimistic state by pulling true state from Google Home
            await refreshTraits(for: [deviceId], silent: true)
        }
    }

    private func handleHomeGraph(_ data: Data) {
        let parsed = GoogleHomeFoyerCodec.parseHomeGraph(jsonData: data)
        guard !parsed.structures.isEmpty else { return }

        structures = parsed.structures
        var mergedDevices = parsed.devices
        for i in mergedDevices.indices {
            if let cached = cachedTraitStates[mergedDevices[i].id] {
                mergedDevices[i].state.merge(from: cached)
            }
        }
        devices = mergedDevices

        // Auto-select the first structure that actually owns devices
        if selectedStructureId == nil || !structures.contains(where: { $0.id == selectedStructureId }) {
            if let populated = structures.first(where: { s in mergedDevices.contains(where: { $0.structureId == s.id }) }) {
                selectedStructureId = populated.id
            } else {
                selectedStructureId = structures.first?.id
            }
        }
        lastUpdated = Date()
        logger.notice("Loaded HomeGraph: \(self.structures.count, privacy: .public) homes, \(self.devices.count, privacy: .public) devices, selected=\(self.selectedStructureId ?? "nil", privacy: .public)")
        startPolling()
    }

    private func handleTraits(_ data: Data) {
        let updates = GoogleHomeFoyerCodec.parseTraitsResponse(jsonData: data)
        guard !updates.isEmpty else { return }

        for (devId, incoming) in updates {
            var current = cachedTraitStates[devId] ?? GoogleHomeTraitState()
            current.merge(from: incoming)
            cachedTraitStates[devId] = current

            if let idx = devices.firstIndex(where: { $0.id == devId }) {
                devices[idx].state.merge(from: incoming)
            }
        }
        lastUpdated = Date()
    }

    private func mutateDevice(id: String, _ transform: (inout GoogleHomeDevice) -> Void) {
        guard let idx = devices.firstIndex(where: { $0.id == id }) else { return }
        var copy = devices[idx]
        transform(&copy)
        devices[idx] = copy
    }
}
