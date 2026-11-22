import Foundation

public enum GoogleHomeDeviceType: String, Codable, Equatable, Sendable {
    case light
    case airConditioner
    case thermostat
    case fan
    case airPurifier
    case humidifier
    case heater
    case outlet
    case switchDevice
    case speaker
    case tv
    case camera
    case lock
    case blinds
    case vacuum
    case appliance
    case sensor
    case other

    public static func fromGoogleType(_ raw: String?) -> GoogleHomeDeviceType {
        guard let raw = raw?.uppercased() else { return .other }
        if raw.contains("LIGHT") || raw.contains("LAMP") { return .light }
        if raw.contains("AC_UNIT") || raw.contains("AIRCONDITIONER") || raw.contains("AIRCOOLER") { return .airConditioner }
        if raw.contains("THERMOSTAT") { return .thermostat }
        if raw.contains("AIRPURIFIER") || raw.contains("AIRFRESHENER") { return .airPurifier }
        if raw.contains("HUMIDIFIER") || raw.contains("DEHUMIDIFIER") { return .humidifier }
        if raw.contains("HEATER") || raw.contains("FIREPLACE") || raw.contains("RADIATOR") { return .heater }
        if raw.contains("FAN") || raw.contains("HOOD") { return .fan }
        if raw.contains("OUTLET") || raw.contains("PLUG") { return .outlet }
        if raw.contains("SWITCH") || raw.contains("SCENE") { return .switchDevice }
        if raw.contains("SPEAKER") || raw.contains("AUDIO") || raw.contains("SOUNDBAR") { return .speaker }
        if raw.contains("TV") || raw.contains("SETTOP") || raw.contains("STREAMING") || raw.contains("REMOTECONTROL") { return .tv }
        if raw.contains("CAMERA") || raw.contains("DOORBELL") { return .camera }
        if raw.contains("LOCK") || raw.contains("SECURITYSYSTEM") { return .lock }
        if raw.contains("BLINDS") || raw.contains("CURTAIN") || raw.contains("SHADE") || raw.contains("GARAGE") || raw.contains("GATE") || raw.contains("WINDOW") || raw.contains("DOOR") { return .blinds }
        if raw.contains("VACUUM") || raw.contains("MOP") { return .vacuum }
        if raw.contains("WASHER") || raw.contains("DRYER") || raw.contains("DISHWASHER") || raw.contains("COFFEE") || raw.contains("OVEN") || raw.contains("KETTLE") || raw.contains("REFRIGERATOR") || raw.contains("MICROWAVE") { return .appliance }
        if raw.contains("SENSOR") || raw.contains("SMOKE") || raw.contains("DETECTOR") { return .sensor }
        return .other
    }

    public var sfSymbol: String {
        switch self {
        case .light: return "lightbulb.fill"
        case .airConditioner: return "snowflake"
        case .thermostat: return "thermometer.medium"
        case .fan: return "fan.fill"
        case .airPurifier: return "aqi.medium"
        case .humidifier: return "humidity.fill"
        case .heater: return "flame.fill"
        case .outlet: return "powerplug.fill"
        case .switchDevice: return "lightswitch.on.fill"
        case .speaker: return "hifispeaker.fill"
        case .tv: return "tv.fill"
        case .camera: return "video.fill"
        case .lock: return "lock.fill"
        case .blinds: return "blinds.horizontal.open"
        case .vacuum: return "circle.dashed.inset.filled"
        case .appliance: return "washer.fill"
        case .sensor: return "sensor.tag.radiowaves.forward.fill"
        case .other: return "square.grid.2x2.fill"
        }
    }

    public var offSymbol: String {
        switch self {
        case .light: return "lightbulb"
        case .airConditioner: return "snowflake"
        case .thermostat: return "thermometer.medium"
        case .fan: return "fan"
        case .airPurifier: return "aqi.low"
        case .humidifier: return "humidity"
        case .heater: return "flame"
        case .outlet: return "powerplug"
        case .switchDevice: return "lightswitch.off"
        case .speaker: return "hifispeaker"
        case .tv: return "tv"
        case .camera: return "video"
        case .lock: return "lock.open"
        case .blinds: return "blinds.horizontal.closed"
        case .vacuum: return "circle.dashed"
        case .appliance: return "washer"
        case .sensor: return "sensor.tag.radiowaves.forward"
        case .other: return "square.grid.2x2"
        }
    }
}

public struct GoogleHomeColorSwatch: Identifiable, Equatable, Hashable, Sendable {
    public var id: String { nameKey }
    public let nameKey: String
    public let displayName: String
    public let rgbInt: Int
    public let useDarkCheckmark: Bool

    public init(nameKey: String, displayName: String, rgbInt: Int, useDarkCheckmark: Bool = false) {
        self.nameKey = nameKey
        self.displayName = displayName
        self.rgbInt = rgbInt
        self.useDarkCheckmark = useDarkCheckmark
    }

    public var rgbComponents: (r: Double, g: Double, b: Double) {
        let r = Double((rgbInt >> 16) & 0xFF) / 255.0
        let g = Double((rgbInt >> 8) & 0xFF) / 255.0
        let b = Double(rgbInt & 0xFF) / 255.0
        return (r, g, b)
    }

    public var isWhitePreset: Bool {
        let lower = nameKey.lowercased()
        return lower.contains("white") || lower.contains("daylight") || lower.contains("ivory")
            || lower.contains("incandescent") || lower.contains("candlelight")
    }
}

public struct GoogleHomeFanSpeedOption: Identifiable, Equatable, Hashable, Sendable {
    public var id: String { speedName }
    public let speedName: String
    public let displayLabel: String

    public init(speedName: String, displayLabel: String) {
        self.speedName = speedName
        self.displayLabel = displayLabel
    }
}

public struct GoogleHomeModeSettingOption: Identifiable, Equatable, Hashable, Sendable {
    public var id: String { settingName }
    public let settingName: String
    public let displayLabel: String

    public init(settingName: String, displayLabel: String) {
        self.settingName = settingName
        self.displayLabel = displayLabel
    }
}

public struct GoogleHomeModeOption: Identifiable, Equatable, Hashable, Sendable {
    public var id: String { modeName }
    public let modeName: String
    public let displayName: String
    public let settings: [GoogleHomeModeSettingOption]
    public var currentSetting: String?

    public init(
        modeName: String,
        displayName: String,
        settings: [GoogleHomeModeSettingOption],
        currentSetting: String? = nil
    ) {
        self.modeName = modeName
        self.displayName = displayName
        self.settings = settings
        self.currentSetting = currentSetting
    }
}

public struct GoogleHomeToggleOption: Identifiable, Equatable, Hashable, Sendable {
    public var id: String { toggleName }
    public let toggleName: String
    public let displayName: String
    public var isOn: Bool

    public init(toggleName: String, displayName: String, isOn: Bool) {
        self.toggleName = toggleName
        self.displayName = displayName
        self.isOn = isOn
    }
}

public struct GoogleHomeTraitState: Equatable, Sendable {
    public var isOnline: Bool = true
    public var onlineDetails: String?
    public var hasDeviceNotFoundError: Bool = false

    // OnOff
    public var isOn: Bool?

    // Brightness (0...100)
    public var brightness: Int?

    // ColorSetting
    public var colorRGB: Int?
    public var colorTemperatureK: Int?
    public var colorTempMinK: Int = 2000
    public var colorTempMaxK: Int = 6500
    public var supportsRGBColor: Bool = false
    public var supportsColorTemp: Bool = false
    public var hasAuthoritativeColorCapabilities: Bool = false
    public var supportedColors: [GoogleHomeColorSwatch] = []

    // TemperatureSetting (AC / Thermostat)
    public var thermostatMode: String?
    public var availableThermostatModes: [String] = []
    public var ambientTempC: Double?
    public var targetTempC: Double?
    public var minTempC: Double = 16
    public var maxTempC: Double = 30
    public var temperatureUnit: String = "C"

    // FanSpeed (discrete steps or continuous 0-100%)
    public var currentFanSpeed: String?
    public var availableFanSpeeds: [GoogleHomeFanSpeedOption] = []
    public var currentFanSpeedPercent: Int?
    public var supportsFanSpeedPercent: Bool = false

    // HumiditySetting (Humidifier / Dehumidifier)
    public var humiditySetpointPercent: Int?
    public var humidityAmbientPercent: Int?
    public var minHumidityPercent: Int = 20
    public var maxHumidityPercent: Int = 80

    // StartStop (Vacuums, Washers, Appliances)
    public var isRunning: Bool?
    public var isPaused: Bool?
    public var isPausable: Bool = false

    // Modes & Toggles
    public var modes: [GoogleHomeModeOption] = []
    public var toggles: [GoogleHomeToggleOption] = []

    // Other common traits
    public var openPercent: Int?
    public var volumePercent: Int?
    public var isMuted: Bool?
    public var isLocked: Bool?

    public init() {}

    public mutating func merge(from incoming: GoogleHomeTraitState) {
        if incoming.onlineDetails != nil {
            isOnline = incoming.isOnline
            onlineDetails = incoming.onlineDetails
            hasDeviceNotFoundError = incoming.hasDeviceNotFoundError
        }
        if let v = incoming.isOn { isOn = v }
        if let v = incoming.brightness { brightness = v }
        if let v = incoming.colorRGB {
            colorRGB = v
            if incoming.colorTemperatureK == nil {
                colorTemperatureK = nil
            }
        }
        if let v = incoming.colorTemperatureK {
            colorTemperatureK = v
            if incoming.colorRGB == nil {
                colorRGB = nil
            }
        }
        if incoming.hasAuthoritativeColorCapabilities {
            hasAuthoritativeColorCapabilities = true
            supportsRGBColor = incoming.supportsRGBColor
            supportsColorTemp = incoming.supportsColorTemp
            if incoming.supportsColorTemp {
                colorTempMinK = incoming.colorTempMinK
                colorTempMaxK = incoming.colorTempMaxK
            }
        } else {
            if incoming.supportsRGBColor { supportsRGBColor = true }
            if incoming.supportsColorTemp {
                supportsColorTemp = true
                colorTempMinK = incoming.colorTempMinK
                colorTempMaxK = incoming.colorTempMaxK
            }
        }
        if !incoming.supportedColors.isEmpty { supportedColors = incoming.supportedColors }

        if let v = incoming.thermostatMode { thermostatMode = v }
        if !incoming.availableThermostatModes.isEmpty { availableThermostatModes = incoming.availableThermostatModes }
        if let v = incoming.ambientTempC { ambientTempC = v }
        if let v = incoming.targetTempC {
            targetTempC = v
            minTempC = incoming.minTempC
            maxTempC = incoming.maxTempC
            temperatureUnit = incoming.temperatureUnit
        }
        if let v = incoming.currentFanSpeed { currentFanSpeed = v }
        if !incoming.availableFanSpeeds.isEmpty { availableFanSpeeds = incoming.availableFanSpeeds }
        if let v = incoming.currentFanSpeedPercent { currentFanSpeedPercent = v }
        if incoming.supportsFanSpeedPercent { supportsFanSpeedPercent = true }

        if let v = incoming.humiditySetpointPercent {
            humiditySetpointPercent = v
            minHumidityPercent = incoming.minHumidityPercent
            maxHumidityPercent = incoming.maxHumidityPercent
        }
        if let v = incoming.humidityAmbientPercent { humidityAmbientPercent = v }

        if let v = incoming.isRunning { isRunning = v }
        if let v = incoming.isPaused { isPaused = v }
        if incoming.isPausable { isPausable = true }

        if !incoming.modes.isEmpty {
            modes = incoming.modes
        }
        if !incoming.toggles.isEmpty {
            toggles = incoming.toggles
        }
        if let v = incoming.openPercent { openPercent = v }
        if let v = incoming.volumePercent { volumePercent = v }
        if let v = incoming.isMuted { isMuted = v }
        if let v = incoming.isLocked { isLocked = v }
    }
}

public struct GoogleHomeRoom: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let deviceIds: [String]

    public init(id: String, name: String, deviceIds: [String]) {
        self.id = id
        self.name = name
        self.deviceIds = deviceIds
    }
}

public struct GoogleHomeStructure: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let rooms: [GoogleHomeRoom]

    public init(id: String, name: String, rooms: [GoogleHomeRoom]) {
        self.id = id
        self.name = name
        self.rooms = rooms
    }
}

public struct GoogleHomeDevice: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let structureId: String
    public let roomId: String?
    public let roomName: String
    public let deviceType: GoogleHomeDeviceType
    public let manufacturer: String?
    public let model: String?
    public let declaredTraits: [String]
    public var state: GoogleHomeTraitState

    public init(
        id: String,
        name: String,
        structureId: String,
        roomId: String?,
        roomName: String,
        deviceType: GoogleHomeDeviceType,
        manufacturer: String?,
        model: String?,
        declaredTraits: [String],
        state: GoogleHomeTraitState = GoogleHomeTraitState()
    ) {
        self.id = id
        self.name = name
        self.structureId = structureId
        self.roomId = roomId
        self.roomName = roomName
        self.deviceType = deviceType
        self.manufacturer = manufacturer
        self.model = model
        self.declaredTraits = declaredTraits
        self.state = state
    }

    public var supportsOnOff: Bool {
        state.isOn != nil || declaredTraits.contains("action.devices.traits.OnOff")
    }

    public var supportsBrightness: Bool {
        state.brightness != nil || declaredTraits.contains("action.devices.traits.Brightness")
    }

    public var supportsColor: Bool {
        state.supportsRGBColor || state.supportsColorTemp || declaredTraits.contains("action.devices.traits.ColorSetting")
    }

    public var supportsTemperatureSetting: Bool {
        state.targetTempC != nil || !state.availableThermostatModes.isEmpty
            || declaredTraits.contains("action.devices.traits.TemperatureSetting")
    }

    public var supportsFanSpeed: Bool {
        !state.availableFanSpeeds.isEmpty
            || state.supportsFanSpeedPercent
            || state.currentFanSpeedPercent != nil
            || declaredTraits.contains("action.devices.traits.FanSpeed")
    }

    public var supportsHumiditySetting: Bool {
        state.humiditySetpointPercent != nil
            || declaredTraits.contains("action.devices.traits.HumiditySetting")
    }

    public var supportsOpenClose: Bool {
        state.openPercent != nil
            || declaredTraits.contains("action.devices.traits.OpenClose")
    }

    public var supportsVolume: Bool {
        state.volumePercent != nil
            || declaredTraits.contains("action.devices.traits.Volume")
    }

    public var supportsLockUnlock: Bool {
        state.isLocked != nil
            || declaredTraits.contains("action.devices.traits.LockUnlock")
    }

    public var supportsStartStop: Bool {
        state.isRunning != nil
            || declaredTraits.contains("action.devices.traits.StartStop")
    }

    public var hasRichControls: Bool {
        supportsBrightness || supportsColor || supportsTemperatureSetting || supportsFanSpeed
            || supportsHumiditySetting || supportsOpenClose || supportsVolume
            || supportsLockUnlock || supportsStartStop
            || !state.modes.isEmpty || !state.toggles.isEmpty
    }

    public var statusSummary: String {
        if !state.isOnline {
            return "Offline"
        }
        if let isLocked = state.isLocked, state.isOn == nil {
            return isLocked ? "Locked" : "Unlocked"
        }
        if let openPct = state.openPercent, state.isOn == nil {
            if openPct == 0 { return "Closed" }
            if openPct >= 100 { return "Open" }
            return "Open · \(openPct)%"
        }
        if let isRunning = state.isRunning, state.isOn == nil {
            if state.isPaused == true { return "Paused" }
            return isRunning ? "Running" : "Idle"
        }
        guard let isOn = state.isOn else {
            if let vol = state.volumePercent {
                return state.isMuted == true ? "Muted" : "Vol \(vol)%"
            }
            if let hum = state.humidityAmbientPercent {
                return "Humidity \(hum)%"
            }
            return "Online"
        }
        if !isOn {
            if let ambient = state.ambientTempC {
                return "Off · Room \(Int(ambient.rounded()))°\(state.temperatureUnit)"
            }
            return "Off"
        }

        var parts: [String] = []
        if supportsTemperatureSetting {
            if let mode = state.thermostatMode {
                parts.append(Self.prettyThermostatMode(mode))
            }
            if let target = state.targetTempC {
                parts.append("\(Int(target.rounded()))°\(state.temperatureUnit)")
            }
            if let ambient = state.ambientTempC {
                parts.append("Room \(Int(ambient.rounded()))°")
            }
            return parts.isEmpty ? "On" : parts.joined(separator: " · ")
        }

        if deviceType == .light || supportsBrightness || supportsColor {
            if let b = state.brightness {
                parts.append("\(b)%")
            }
            if let k = state.colorTemperatureK {
                parts.append("\(k)K")
            } else if let rgb = state.colorRGB {
                if let match = state.supportedColors.first(where: { $0.rgbInt == rgb }) {
                    parts.append(match.displayName.capitalized)
                } else {
                    parts.append("Color")
                }
            }
            return parts.isEmpty ? "On" : "On · " + parts.joined(separator: " · ")
        }

        if let speed = state.currentFanSpeed {
            let label = state.availableFanSpeeds.first(where: { $0.speedName == speed })?.displayLabel
                ?? Self.prettySpeedLabel(speed)
            return "On · Speed \(label)"
        }

        if let speedPct = state.currentFanSpeedPercent {
            return "On · \(speedPct)%"
        }

        if let hum = state.humiditySetpointPercent {
            return "On · Target \(hum)%"
        }

        return "On"
    }

    public static func prettyThermostatMode(_ raw: String) -> String {
        switch raw.lowercased() {
        case "cool": return "Cool"
        case "heat": return "Heat"
        case "dry": return "Dry"
        case "fan-only", "fan": return "Fan"
        case "auto", "heatcool": return "Auto"
        case "eco": return "Eco"
        case "off": return "Off"
        default: return raw.capitalized
        }
    }

    public static func prettySpeedLabel(_ raw: String) -> String {
        let lower = raw.lowercased()
        switch lower {
        case "speed_one", "one": return "1"
        case "speed_two", "two": return "2"
        case "speed_three", "three": return "3"
        case "speed_four", "four": return "4"
        case "speed_five", "five": return "5"
        case "speed_six", "six": return "6"
        default:
            return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

public enum GoogleHomeTraitUpdate: Equatable, Sendable {
    case onOff(Bool)
    case brightness(Int)
    case colorRGB(Int)
    case colorTemperature(Int)
    case thermostat(mode: String?, setpointC: Double?)
    case fanSpeed(String)
    case fanSpeedPercent(Int)
    case humiditySetpoint(Int)
    case startStop(start: Bool)
    case pauseUnpause(pause: Bool)
    case mode(name: String, setting: String)
    case toggle(name: String, enabled: Bool)
    case openPercent(Int)
    case volume(Int)
    case mute(Bool)
    case lock(Bool)
}

/// Pure-Swift JSPB parser & serializer for Google Home Foyer (`googlehomefoyer-pa.clients6.google.com`).
public enum GoogleHomeFoyerCodec {

    // MARK: - Parse GetHomeGraph

    public static func parseHomeGraph(jsonData: Data) -> (structures: [GoogleHomeStructure], devices: [GoogleHomeDevice]) {
        guard let root = try? JSONSerialization.jsonObject(with: jsonData) as? [Any],
              root.count >= 2,
              let rawStructures = root[1] as? [Any] else {
            return ([], [])
        }

        var structures: [GoogleHomeStructure] = []
        var allDevices: [GoogleHomeDevice] = []

        for rawStruct in rawStructures {
            guard let sArr = rawStruct as? [Any],
                  sArr.count >= 2,
                  let structureId = sArr[0] as? String,
                  let rawName = sArr[1] as? String else {
                continue
            }
            let structureName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)

            var rooms: [GoogleHomeRoom] = []
            var deviceToRoom: [String: (id: String, name: String)] = [:]

            if sArr.count > 5, let rawRooms = sArr[5] as? [Any] {
                for rawRoom in rawRooms {
                    guard let rArr = rawRoom as? [Any],
                          rArr.count >= 3,
                          let roomId = rArr[0] as? String,
                          let rawRoomName = rArr[2] as? String else {
                        continue
                    }
                    let roomName = rawRoomName.trimmingCharacters(in: .whitespacesAndNewlines)
                    var roomDeviceIds: [String] = []
                    if rArr.count > 4, let rawRefs = rArr[4] as? [Any] {
                        for ref in rawRefs {
                            if let refArr = ref as? [Any],
                               let idWrap = refArr.first as? [Any],
                               let devId = idWrap.first as? String {
                                roomDeviceIds.append(devId)
                                deviceToRoom[devId] = (roomId, roomName)
                            }
                        }
                    }
                    rooms.append(GoogleHomeRoom(id: roomId, name: roomName, deviceIds: roomDeviceIds))
                }
            }

            structures.append(GoogleHomeStructure(id: structureId, name: structureName, rooms: rooms))

            if sArr.count > 6, let rawDevices = sArr[6] as? [Any] {
                for rawDev in rawDevices {
                    guard let dArr = rawDev as? [Any],
                          dArr.count >= 6,
                          let idWrap = dArr[0] as? [Any],
                          let deviceId = idWrap.first as? String,
                          let rawDevName = dArr[3] as? String else {
                        continue
                    }
                    let rawType = dArr[5] as? String
                    // Skip synthetic light/device groups that Google Home reports as DEVICE_GROUP
                    if let rawType, rawType.uppercased().contains("DEVICE_GROUP") {
                        continue
                    }

                    let traits = (dArr.count > 6 ? (dArr[6] as? [String]) : nil) ?? []
                    let hw = (dArr.count > 16 ? (dArr[16] as? [String]) : nil) ?? []
                    let manufacturer = hw.first.flatMap { $0.isEmpty ? nil : $0 }
                    let model = hw.count > 1 ? (hw[1].isEmpty ? nil : hw[1]) : nil

                    let roomInfo = deviceToRoom[deviceId]
                    var initialState = GoogleHomeTraitState()
                    if traits.contains("action.devices.traits.ColorSetting") {
                        initialState.supportsRGBColor = true
                        initialState.supportsColorTemp = true
                    }

                    // Parse any static attributes embedded in dArr[19] (e.g., availableFanSpeeds)
                    if dArr.count > 19, let rawAttrs = dArr[19] as? [Any] {
                        let attrMap = unwrapKVList(rawAttrs)
                        applyStaticAttributes(attrMap, to: &initialState)
                    }

                    allDevices.append(GoogleHomeDevice(
                        id: deviceId,
                        name: rawDevName.trimmingCharacters(in: .whitespacesAndNewlines),
                        structureId: structureId,
                        roomId: roomInfo?.id,
                        roomName: roomInfo?.name ?? "Other Devices",
                        deviceType: GoogleHomeDeviceType.fromGoogleType(rawType),
                        manufacturer: manufacturer,
                        model: model,
                        declaredTraits: traits,
                        state: initialState
                    ))
                }
            }
        }

        return (structures, allDevices)
    }

    // MARK: - Parse GetTraits / UpdateTraits Response

    public static func parseTraitsResponse(jsonData: Data) -> [String: GoogleHomeTraitState] {
        guard let root = try? JSONSerialization.jsonObject(with: jsonData) as? [Any],
              let deviceEntries = root.first as? [Any] else {
            return [:]
        }

        var result: [String: GoogleHomeTraitState] = [:]

        for entry in deviceEntries {
            guard let eArr = entry as? [Any],
                  eArr.count >= 2,
                  let idWrap = eArr[0] as? [Any],
                  let deviceId = idWrap.first as? String,
                  let traitList = eArr[1] as? [Any] else {
                continue
            }

            var traitState = GoogleHomeTraitState()

            for rawTrait in traitList {
                guard let tArr = rawTrait as? [Any],
                      let traitName = tArr.first as? String else {
                    continue
                }
                let stateMap = tArr.count > 1 ? unwrapKVList(tArr[1]) : [:]
                let attrMap = tArr.count > 2 ? unwrapKVList(tArr[2]) : [:]

                switch traitName {
                case "deviceStatus":
                    if let online = stateMap["online"] as? Bool {
                        traitState.isOnline = online
                    }
                    if let details = stateMap["onlineStateDetails"] as? String {
                        traitState.onlineDetails = details
                    }
                    if let err = stateMap["error"] as? String, err == "deviceNotFound" {
                        traitState.hasDeviceNotFoundError = true
                        traitState.isOnline = false
                    }

                case "onOff":
                    if let on = stateMap["onOff"] as? Bool {
                        traitState.isOn = on
                    }

                case "brightness":
                    if let b = toInt(stateMap["brightness"]) {
                        traitState.brightness = b
                    }

                case "color":
                    if !attrMap.isEmpty {
                        traitState.hasAuthoritativeColorCapabilities = true
                    }
                    if let rgb = toInt(stateMap["colorRGB"]) {
                        traitState.colorRGB = rgb
                        traitState.supportsRGBColor = true
                    }
                    if let tempK = toInt(stateMap["colorTemperature"]) {
                        traitState.colorTemperatureK = tempK
                        traitState.supportsColorTemp = true
                    }
                    if let model = attrMap["colorModel"] as? String, model.lowercased() == "rgb" || model.lowercased() == "hsv" {
                        traitState.supportsRGBColor = true
                    }
                    if let range = attrMap["colorTemperatureRange"] as? [String: Any] {
                        traitState.supportsColorTemp = true
                        if let minK = toInt(range["temperatureMinK"]) { traitState.colorTempMinK = minK }
                        if let maxK = toInt(range["temperatureMaxK"]) { traitState.colorTempMaxK = maxK }
                    }
                    if let rawColors = attrMap["supportedColors"] as? [[String: Any]] {
                        let swatches: [GoogleHomeColorSwatch] = rawColors.compactMap { dict in
                            guard let key = dict["nameKey"] as? String,
                                  let hex = toInt(dict["displayHexValue"]) else {
                                return nil
                            }
                            let disp = (dict["displayName"] as? String) ?? key
                            let check = toInt(dict["displayCheckmarkColor"]) == 1
                            return GoogleHomeColorSwatch(
                                nameKey: key,
                                displayName: disp,
                                rgbInt: hex,
                                useDarkCheckmark: check
                            )
                        }
                        if !swatches.isEmpty {
                            traitState.supportedColors = swatches
                            if swatches.contains(where: { !$0.isWhitePreset }) {
                                traitState.supportsRGBColor = true
                            }
                        }
                    }

                case "temperatureSetting":
                    if let mode = stateMap["mode"] as? String {
                        traitState.thermostatMode = mode
                    }
                    if let amb = toDouble(stateMap["ambientAirTemperatureC"]) {
                        traitState.ambientTempC = amb
                    }
                    if let sp = toDouble(stateMap["thermostatTemperatureSetpointC"])
                        ?? toDouble(stateMap["thermostatTemperatureSetpoint"]) {
                        traitState.targetTempC = sp
                    }
                    if let modes = (attrMap["availableThermostatModes"] as? [String])
                        ?? (attrMap["availableModes"] as? [String]) {
                        traitState.availableThermostatModes = modes
                    }
                    if let unit = attrMap["temperatureUnit"] as? String {
                        traitState.temperatureUnit = unit
                    }
                    if let range = attrMap["thermostatTemperatureRange"] as? [String: Any] {
                        if let minC = toDouble(range["minThresholdCelsius"]) { traitState.minTempC = minC }
                        if let maxC = toDouble(range["maxThresholdCelsius"]) { traitState.maxTempC = maxC }
                    }

                case "fanSpeed":
                    if let cur = stateMap["currentFanSpeedSetting"] as? String {
                        traitState.currentFanSpeed = cur
                    }
                    if let pct = toInt(stateMap["currentFanSpeedPercent"]) {
                        traitState.currentFanSpeedPercent = pct
                        traitState.supportsFanSpeedPercent = true
                    }
                    if let supportsPct = attrMap["supportsFanSpeedPercent"] as? Bool, supportsPct {
                        traitState.supportsFanSpeedPercent = true
                    }
                    if let avail = attrMap["availableFanSpeeds"] as? [String: Any] {
                        traitState.availableFanSpeeds = parseFanSpeeds(avail)
                    }

                case "humiditySetting":
                    if let sp = toInt(stateMap["humiditySetpointPercent"]) {
                        traitState.humiditySetpointPercent = sp
                    }
                    if let amb = toInt(stateMap["humidityAmbientPercent"]) {
                        traitState.humidityAmbientPercent = amb
                    }
                    if let range = attrMap["humiditySetpointRange"] as? [String: Any] {
                        if let minP = toInt(range["minPercent"]) { traitState.minHumidityPercent = minP }
                        if let maxP = toInt(range["maxPercent"]) { traitState.maxHumidityPercent = maxP }
                    }

                case "startStop":
                    if let running = stateMap["isRunning"] as? Bool {
                        traitState.isRunning = running
                    }
                    if let paused = stateMap["isPaused"] as? Bool {
                        traitState.isPaused = paused
                    }
                    if let pausable = attrMap["pausable"] as? Bool {
                        traitState.isPausable = pausable
                    }

                case "modes":
                    let currentMap = stateMap["currentModeSetting"] as? [String: Any] ?? [:]
                    if let availModes = attrMap["availableModes"] as? [[String: Any]] {
                        traitState.modes = parseModes(availModes, current: currentMap)
                    }

                case "toggles":
                    let currentMap = stateMap["currentToggleSettings"] as? [String: Any] ?? [:]
                    if let availToggles = attrMap["availableToggles"] as? [[String: Any]] {
                        traitState.toggles = parseToggles(availToggles, current: currentMap)
                    } else if !currentMap.isEmpty {
                        traitState.toggles = currentMap.keys.sorted().map { k in
                            GoogleHomeToggleOption(
                                toggleName: k,
                                displayName: prettyToggleName(k),
                                isOn: (currentMap[k] as? Bool) ?? false
                            )
                        }
                    }

                case "openClose":
                    if let pct = toInt(stateMap["openPercent"]) {
                        traitState.openPercent = pct
                    }

                case "volume":
                    if let vol = toInt(stateMap["currentVolume"]) {
                        traitState.volumePercent = vol
                    }
                    if let muted = stateMap["isMuted"] as? Bool {
                        traitState.isMuted = muted
                    }

                case "lockUnlock":
                    if let locked = stateMap["isLocked"] as? Bool {
                        traitState.isLocked = locked
                    }

                default:
                    break
                }
            }

            result[deviceId] = traitState
        }

        return result
    }

    // MARK: - Build GetTraits / UpdateTraits JSPB Bodies

    public static func buildGetTraitsBody(deviceIds: [String]) -> String {
        let wrapped = deviceIds.map { [$0] }
        let root: [Any] = [wrapped]
        guard let data = try? JSONSerialization.data(withJSONObject: root),
              let str = String(data: data, encoding: .utf8) else {
            return "[[]]"
        }
        return str
    }

    public static func buildUpdateTraitsBody(deviceId: String, updates: [GoogleHomeTraitUpdate]) -> String {
        let traitPayloads: [[Any]] = updates.map { update in
            switch update {
            case .onOff(let on):
                return ["onOff", [["onOff", jspbBool(on)]]]

            case .brightness(let level):
                let clamped = min(max(level, 1), 100)
                return ["brightness", [["brightness", jspbNumber(clamped)]]]

            case .colorRGB(let rgbInt):
                return ["color", [["colorRGB", jspbNumber(rgbInt & 0xFF_FFFF)]]]

            case .colorTemperature(let kelvin):
                return ["color", [["colorTemperature", jspbNumber(kelvin)]]]

            case .thermostat(let mode, let setpointC):
                var kvs: [[Any]] = []
                if let mode {
                    kvs.append(["mode", jspbString(mode)])
                }
                if let setpointC {
                    kvs.append(["thermostatTemperatureSetpoint", jspbNumber(setpointC)])
                }
                return ["temperatureSetting", kvs]

            case .fanSpeed(let speedName):
                return ["fanSpeed", [["currentFanSpeedSetting", jspbString(speedName)]]]

            case .fanSpeedPercent(let pct):
                let clamped = min(max(pct, 0), 100)
                return ["fanSpeed", [["currentFanSpeedPercent", jspbNumber(clamped)]]]

            case .humiditySetpoint(let pct):
                let clamped = min(max(pct, 0), 100)
                return ["humiditySetting", [["humiditySetpointPercent", jspbNumber(clamped)]]]

            case .startStop(let start):
                return ["startStop", [["isRunning", jspbBool(start)]]]

            case .pauseUnpause(let pause):
                return ["startStop", [["isPaused", jspbBool(pause)]]]

            case .mode(let name, let setting):
                let structVal = jspbStruct([[name, jspbString(setting)]])
                return ["modes", [["currentModeSetting", structVal]]]

            case .toggle(let name, let enabled):
                let structVal = jspbStruct([[name, jspbBool(enabled)]])
                return ["toggles", [["currentToggleSettings", structVal]]]

            case .openPercent(let pct):
                let clamped = min(max(pct, 0), 100)
                return ["openClose", [
                    ["isOpen", jspbBool(clamped > 0)],
                    ["openPercent", jspbNumber(clamped)],
                ]]

            case .volume(let vol):
                let clamped = min(max(vol, 0), 100)
                return ["volume", [["currentVolume", jspbNumber(clamped)]]]

            case .mute(let muted):
                return ["volume", [["isMuted", jspbBool(muted)]]]

            case .lock(let locked):
                return ["lockUnlock", [["isLocked", jspbBool(locked)]]]
            }
        }

        let root: [Any] = [[[[deviceId], traitPayloads]]]
        guard let data = try? JSONSerialization.data(withJSONObject: root),
              let str = String(data: data, encoding: .utf8) else {
            return "[[]]"
        }
        return str
    }

    // MARK: - JSPB Struct.Value Helpers

    private static func jspbNumber(_ value: Int) -> [Any] { [NSNull(), value] }
    private static func jspbNumber(_ value: Double) -> [Any] { [NSNull(), value] }
    private static func jspbString(_ value: String) -> [Any] { [NSNull(), NSNull(), value] }
    private static func jspbBool(_ value: Bool) -> [Any] { [NSNull(), NSNull(), NSNull(), value ? 1 : 0] }
    private static func jspbStruct(_ entries: [[Any]]) -> [Any] {
        [NSNull(), NSNull(), NSNull(), NSNull(), [entries]]
    }

    private static func unwrapValue(_ raw: Any) -> Any? {
        guard let arr = raw as? [Any] else { return raw }
        if arr.count >= 2 && !(arr[1] is NSNull) {
            return arr[1]
        }
        if arr.count >= 3 && !(arr[2] is NSNull) {
            return arr[2]
        }
        if arr.count >= 4 && !(arr[3] is NSNull) {
            if let b = arr[3] as? Bool { return b }
            if let n = toInt(arr[3]) { return n != 0 }
        }
        if arr.count >= 5 && !(arr[4] is NSNull) {
            return unwrapKVList(arr[4])
        }
        if arr.count >= 6 && !(arr[5] is NSNull) {
            var items = arr[5] as? [Any] ?? []
            if items.count == 1, let nested = items[0] as? [Any] {
                items = nested
            }
            return items.compactMap { unwrapValue($0) }
        }
        return nil
    }

    private static func unwrapKVList(_ raw: Any) -> [String: Any] {
        guard var list = raw as? [Any] else { return [:] }
        if list.count == 1, let nested = list[0] as? [Any],
           let firstInner = nested.first as? [Any], firstInner.count == 2, firstInner[0] is String {
            list = nested
        }
        var out: [String: Any] = [:]
        for item in list {
            if let pair = item as? [Any], pair.count == 2, let key = pair[0] as? String {
                if let val = unwrapValue(pair[1]) {
                    out[key] = val
                }
            }
        }
        return out
    }

    private static func applyStaticAttributes(_ attrs: [String: Any], to state: inout GoogleHomeTraitState) {
        if let avail = attrs["availableFanSpeeds"] as? [String: Any] {
            state.availableFanSpeeds = parseFanSpeeds(avail)
        }
        if let availModes = attrs["availableModes"] as? [[String: Any]] {
            state.modes = parseModes(availModes, current: [:])
        }
        if let availToggles = attrs["availableToggles"] as? [[String: Any]] {
            state.toggles = parseToggles(availToggles, current: [:])
        }
    }

    private static func parseFanSpeeds(_ dict: [String: Any]) -> [GoogleHomeFanSpeedOption] {
        guard let speeds = dict["speeds"] as? [[String: Any]] else { return [] }
        return speeds.compactMap { entry in
            guard let name = entry["speed_name"] as? String else { return nil }
            var label = GoogleHomeDevice.prettySpeedLabel(name)
            if let values = entry["speed_values"] as? [[String: Any]],
               let en = values.first(where: { ($0["lang"] as? String)?.lowercased() == "en" }) ?? values.first,
               let syns = en["speed_synonym"] as? [String] {
                // Prefer short numeric or clean English synonym (e.g. "1".."6", "Quiet", "Low", "Medium", "High", "Auto")
                if let digit = syns.first(where: { $0.count <= 2 && $0.allSatisfy(\.isNumber) }) {
                    label = digit
                } else if let firstSyn = syns.first, !firstSyn.isEmpty, label.count > 12 {
                    label = firstSyn.capitalized
                }
            }
            return GoogleHomeFanSpeedOption(speedName: name, displayLabel: label)
        }
    }

    private static func parseModes(_ list: [[String: Any]], current: [String: Any]) -> [GoogleHomeModeOption] {
        list.compactMap { entry in
            guard let name = entry["name"] as? String else { return nil }
            let disp = extractEnglishSynonym(from: entry["name_values"]) ?? name.replacingOccurrences(of: "_", with: " ").capitalized
            let rawSettings = (entry["settings"] as? [[String: Any]]) ?? []
            let settings: [GoogleHomeModeSettingOption] = rawSettings.compactMap { s in
                guard let sName = s["setting_name"] as? String else { return nil }
                let sLabel = extractEnglishSynonym(from: s["setting_values"]) ?? sName.capitalized
                return GoogleHomeModeSettingOption(settingName: sName, displayLabel: sLabel)
            }
            return GoogleHomeModeOption(
                modeName: name,
                displayName: disp,
                settings: settings,
                currentSetting: current[name] as? String
            )
        }
    }

    private static func parseToggles(_ list: [[String: Any]], current: [String: Any]) -> [GoogleHomeToggleOption] {
        list.compactMap { entry in
            guard let name = entry["name"] as? String else { return nil }
            let disp = prettyToggleName(name, synonyms: entry["name_values"])
            return GoogleHomeToggleOption(
                toggleName: name,
                displayName: disp,
                isOn: (current[name] as? Bool) ?? false
            )
        }
    }

    private static func extractEnglishSynonym(from raw: Any?) -> String? {
        guard let values = raw as? [[String: Any]],
              let en = values.first(where: { ($0["lang"] as? String)?.lowercased() == "en" }) ?? values.first else {
            return nil
        }
        for key in ["name_synonym", "setting_synonym", "speed_synonym"] {
            if let syns = en[key] as? [String], let first = syns.first, !first.isEmpty {
                return first.capitalized
            }
        }
        return nil
    }

    private static func prettyToggleName(_ raw: String, synonyms: Any? = nil) -> String {
        switch raw.lowercased() {
        case "led_toggle": return "LED Light"
        case "sleep_toggle": return "Sleep Mode"
        default:
            if let syn = extractEnglishSynonym(from: synonyms) {
                return syn
            }
            return raw.replacingOccurrences(of: "_toggle", with: "")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }

    private static func toInt(_ raw: Any?) -> Int? {
        if let i = raw as? Int { return i }
        if let d = raw as? Double { return Int(d.rounded()) }
        if let n = raw as? NSNumber { return n.intValue }
        return nil
    }

    private static func toDouble(_ raw: Any?) -> Double? {
        if let d = raw as? Double { return d }
        if let i = raw as? Int { return Double(i) }
        if let n = raw as? NSNumber { return n.doubleValue }
        return nil
    }

    public static func kelvinToRGB(_ kelvin: Int) -> (r: Double, g: Double, b: Double) {
        let temp = Double(min(max(kelvin, 1800), 9500)) / 100.0
        let r: Double
        let g: Double
        let b: Double

        if temp <= 66 {
            r = 255
            g = 99.4708025861 * log(temp) - 161.1195681661
            b = temp <= 19 ? 0 : (138.5177312231 * log(temp - 10) - 305.0447927307)
        } else {
            r = 329.698727446 * pow(temp - 60, -0.1332047592)
            g = 288.1221695283 * pow(temp - 60, -0.0755148492)
            b = 255
        }
        return (
            min(max(r / 255.0, 0), 1),
            min(max(g / 255.0, 0), 1),
            min(max(b / 255.0, 0), 1)
        )
    }
}
