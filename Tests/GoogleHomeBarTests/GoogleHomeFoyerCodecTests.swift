import Foundation
import Testing
@testable import GoogleHomeBarCore

@Suite("Google Home Foyer JSPB Codec")
struct GoogleHomeFoyerCodecTests {
    private func vNum(_ n: Double) -> [Any] { [NSNull(), n] }
    private func vStr(_ s: String) -> [Any] { [NSNull(), NSNull(), s] }
    private func vBool(_ b: Bool) -> [Any] { [NSNull(), NSNull(), NSNull(), b ? 1 : 0] }
    private func vStruct(_ pairs: [(String, Any)]) -> [Any] {
        [NSNull(), NSNull(), NSNull(), NSNull(), [pairs.map { [$0.0, $0.1] }]]
    }
    private func vList(_ items: [Any]) -> [Any] {
        [NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), [items]]
    }

    @Test("Parses GetHomeGraph structures, rooms, devices, and skips DEVICE_GROUP")
    func parseHomeGraphSample() {
        let json = """
        ["1795324006880",[
          ["home-1","Home",[],[["user@example.com"]],null,[
            ["room-bed",null,"Bedroom ",["BEDROOM"],[[["dev-fan"]], [["dev-ac"]], [["dev-bulb"]]]]
          ],[
            [["dev-fan",["src","1"]],null,null,"Bedroom Smart Fan",null,"action.devices.types.FAN",["action.devices.traits.OnOff","action.devices.traits.FanSpeed","action.devices.traits.Toggles"],null,null,null,null,null,null,null,null,null,["SmartFanCo","Smart Fan Pro"]],
            [["dev-ac",["src","2"]],null,null,"Living Room AC",null,"action.devices.types.AC_UNIT",["action.devices.traits.OnOff","action.devices.traits.TemperatureSetting","action.devices.traits.FanSpeed"],null,null,null,null,null,null,null,null,null,["PANASONIC","CS-CU"]],
            [["dev-bulb",["src","3"]],null,null,"Desk RGBCW Bulb",null,"action.devices.types.LIGHT",["action.devices.traits.Brightness","action.devices.traits.ColorSetting","action.devices.traits.OnOff","action.devices.traits.Modes"]],
            [["group-1"],null,null,"Bedroom Lights",null,"action.devices.types.DEVICE_GROUP",["action.devices.traits.OnOff"]]
          ]]
        ]]
        """

        let (structures, devices) = GoogleHomeFoyerCodec.parseHomeGraph(jsonData: Data(json.utf8))
        #expect(structures.count == 1)
        #expect(structures[0].name == "Home")
        #expect(structures[0].rooms.count == 1)
        #expect(structures[0].rooms[0].name == "Bedroom")
        #expect(devices.count == 3)
        #expect(devices[0].deviceType == .fan)
        #expect(devices[0].roomName == "Bedroom")
        #expect(devices[1].deviceType == .airConditioner)
        #expect(devices[1].manufacturer == "PANASONIC")
        #expect(devices[2].deviceType == .light)
        #expect(devices[2].supportsColor == true)
    }

    @Test("Parses GetTraits for RGBCW Light, AC, and Smart Fan")
    func parseTraitsSample() throws {
        let bulbTraits: [[Any]] = [
            ["brightness", [["brightness", vNum(62)]]],
            [
                "color",
                [["colorTemperature", vNum(6000)]],
                [[
                    ["colorModel", vStr("rgb")],
                    ["colorTemperatureRange", vStruct([("temperatureMinK", vNum(2000)), ("temperatureMaxK", vNum(9000))])],
                    ["supportedColors", vList([
                        vStruct([
                            ("nameKey", vStr("magenta")),
                            ("displayName", vStr("magenta")),
                            ("displayHexValue", vNum(13_178_012)),
                            ("displayCheckmarkColor", vNum(2)),
                        ]),
                    ])],
                ]],
            ],
            ["deviceStatus", [["online", vBool(true)], ["onlineStateDetails", vStr("stateOnline")]]],
            ["onOff", [["onOff", vBool(true)]]],
        ]

        let acTraits: [[Any]] = [
            [
                "temperatureSetting",
                [
                    ["mode", vStr("cool")],
                    ["ambientAirTemperatureC", vNum(28)],
                    ["thermostatTemperatureSetpointC", vNum(26)],
                ],
                [[
                    ["availableThermostatModes", vList([vStr("auto"), vStr("cool"), vStr("dry"), vStr("fan-only")])],
                    ["temperatureUnit", vStr("C")],
                    ["thermostatTemperatureRange", vStruct([("minThresholdCelsius", vNum(16)), ("maxThresholdCelsius", vNum(30))])],
                ]],
            ],
            ["deviceStatus", [["online", vBool(true)], ["onlineStateDetails", vStr("stateOnline")]]],
            ["onOff", [["onOff", vBool(false)]]],
        ]

        let fanTraits: [[Any]] = [
            [
                "fanSpeed",
                [["currentFanSpeedSetting", vStr("speed_four")]],
                [[
                    ["availableFanSpeeds", vStruct([
                        ("speeds", vList([
                            vStruct([
                                ("speed_name", vStr("speed_one")),
                                ("speed_values", vList([vStruct([("lang", vStr("en")), ("speed_synonym", vList([vStr("one"), vStr("1")]))])])),
                            ]),
                            vStruct([
                                ("speed_name", vStr("speed_four")),
                                ("speed_values", vList([vStruct([("lang", vStr("en")), ("speed_synonym", vList([vStr("four"), vStr("4")]))])])),
                            ]),
                        ])),
                    ])],
                ]],
            ],
            [
                "toggles",
                [["currentToggleSettings", vStruct([("led_toggle", vBool(true)), ("sleep_toggle", vBool(false))])]],
                [[
                    ["availableToggles", vList([
                        vStruct([("name", vStr("led_toggle"))]),
                        vStruct([("name", vStr("sleep_toggle"))]),
                    ])],
                ]],
            ],
            ["deviceStatus", [["online", vBool(true)], ["onlineStateDetails", vStr("stateOnline")]]],
            ["onOff", [["onOff", vBool(true)]]],
        ]

        let root: [Any] = [[
            [["dev-bulb"], bulbTraits],
            [["dev-ac"], acTraits],
            [["dev-fan"], fanTraits],
        ]]
        let data = try JSONSerialization.data(withJSONObject: root)

        let map = GoogleHomeFoyerCodec.parseTraitsResponse(jsonData: data)
        let bulb = map["dev-bulb"]
        #expect(bulb?.isOnline == true)
        #expect(bulb?.isOn == true)
        #expect(bulb?.brightness == 62)
        #expect(bulb?.colorTemperatureK == 6000)
        #expect(bulb?.colorTempMinK == 2000)
        #expect(bulb?.colorTempMaxK == 9000)
        #expect(bulb?.supportedColors.first?.nameKey == "magenta")
        #expect(bulb?.supportedColors.first?.rgbInt == 13_178_012)

        let ac = map["dev-ac"]
        #expect(ac?.isOn == false)
        #expect(ac?.thermostatMode == "cool")
        #expect(ac?.ambientTempC == 28)
        #expect(ac?.targetTempC == 26)
        #expect(ac?.minTempC == 16)
        #expect(ac?.maxTempC == 30)
        #expect(ac?.availableThermostatModes == ["auto", "cool", "dry", "fan-only"])

        let fan = map["dev-fan"]
        #expect(fan?.currentFanSpeed == "speed_four")
        #expect(fan?.availableFanSpeeds.map(\.displayLabel) == ["1", "4"])
        #expect(fan?.toggles.first(where: { $0.toggleName == "led_toggle" })?.isOn == true)
        #expect(fan?.toggles.first(where: { $0.toggleName == "sleep_toggle" })?.isOn == false)
    }

    @Test("Builds byte-exact JSPB UpdateTraits payloads for all traits")
    func buildUpdateTraitsPayloads() {
        let onOff = GoogleHomeFoyerCodec.buildUpdateTraitsBody(deviceId: "d1", updates: [.onOff(true)])
        #expect(onOff == #"[[[["d1"],[["onOff",[["onOff",[null,null,null,1]]]]]]]]"#)

        let color = GoogleHomeFoyerCodec.buildUpdateTraitsBody(deviceId: "d1", updates: [.colorRGB(13_178_012)])
        #expect(color == #"[[[["d1"],[["color",[["colorRGB",[null,13178012]]]]]]]]"#)

        let temp = GoogleHomeFoyerCodec.buildUpdateTraitsBody(deviceId: "d1", updates: [.colorTemperature(4000)])
        #expect(temp == #"[[[["d1"],[["color",[["colorTemperature",[null,4000]]]]]]]]"#)

        let ac = GoogleHomeFoyerCodec.buildUpdateTraitsBody(deviceId: "d2", updates: [.thermostat(mode: "cool", setpointC: 24)])
        #expect(ac == #"[[[["d2"],[["temperatureSetting",[["mode",[null,null,"cool"]],["thermostatTemperatureSetpoint",[null,24]]]]]]]]"#)

        let getReq = GoogleHomeFoyerCodec.buildGetTraitsBody(deviceIds: ["d1", "d2"])
        #expect(getReq == #"[[["d1"],["d2"]]]"#)
    }

    @Test("Correctly distinguishes tunable-white-only lights and parses generic traits (volume, humidity, fan %, startStop)")
    func parseGenericAndAuthoritativeTraits() throws {
        // Tunable white bulb: HomeGraph declares ColorSetting, then GetTraits confirms colorTemperatureRange only (no RGB)
        let hgJson = """
        ["1",[
          ["h1","Home",[],[],null,[],[
            [["d-white"],null,null,"Desk Lamp",null,"action.devices.types.LIGHT",["action.devices.traits.OnOff","action.devices.traits.Brightness","action.devices.traits.ColorSetting"]],
            [["d-hum"],null,null,"Humidifier",null,"action.devices.types.HUMIDIFIER",["action.devices.traits.OnOff","action.devices.traits.HumiditySetting","action.devices.traits.FanSpeed"]],
            [["d-vac"],null,null,"Robot Vacuum",null,"action.devices.types.VACUUM",["action.devices.traits.StartStop"]],
            [["d-tv"],null,null,"Living Room TV",null,"action.devices.types.TV",["action.devices.traits.OnOff","action.devices.traits.Volume"]]
          ]]
        ]]
        """
        let (_, initialDevices) = GoogleHomeFoyerCodec.parseHomeGraph(jsonData: Data(hgJson.utf8))
        #expect(initialDevices.count == 4)
        #expect(initialDevices[1].deviceType == .humidifier)
        #expect(initialDevices[2].deviceType == .vacuum)
        #expect(initialDevices[3].deviceType == .tv)

        let traitPayload: [Any] = [[
            [["d-white"], [
                [
                    "color",
                    [["colorTemperature", vNum(3000)]],
                    [[["colorTemperatureRange", vStruct([("temperatureMinK", vNum(2700)), ("temperatureMaxK", vNum(6500))])]]],
                ],
            ]],
            [["d-hum"], [
                [
                    "humiditySetting",
                    [["humiditySetpointPercent", vNum(55)], ["humidityAmbientPercent", vNum(42)]],
                    [[["humiditySetpointRange", vStruct([("minPercent", vNum(30)), ("maxPercent", vNum(70))])]]],
                ],
                [
                    "fanSpeed",
                    [["currentFanSpeedPercent", vNum(60)]],
                    [[["supportsFanSpeedPercent", vBool(true)]]],
                ],
            ]],
            [["d-vac"], [
                [
                    "startStop",
                    [["isRunning", vBool(true)], ["isPaused", vBool(false)]],
                    [[["pausable", vBool(true)]]],
                ],
            ]],
            [["d-tv"], [
                ["volume", [["currentVolume", vNum(35)], ["isMuted", vBool(false)]]],
            ]],
        ]]

        let data = try JSONSerialization.data(withJSONObject: traitPayload)
        let parsed = GoogleHomeFoyerCodec.parseTraitsResponse(jsonData: data)

        var whiteLamp = initialDevices[0]
        whiteLamp.state.merge(from: try #require(parsed["d-white"]))
        #expect(whiteLamp.state.supportsColorTemp == true)
        #expect(whiteLamp.state.supportsRGBColor == false)

        let hum = try #require(parsed["d-hum"])
        #expect(hum.humiditySetpointPercent == 55)
        #expect(hum.humidityAmbientPercent == 42)
        #expect(hum.minHumidityPercent == 30)
        #expect(hum.maxHumidityPercent == 70)
        #expect(hum.currentFanSpeedPercent == 60)
        #expect(hum.supportsFanSpeedPercent == true)

        let vac = try #require(parsed["d-vac"])
        #expect(vac.isRunning == true)
        #expect(vac.isPaused == false)
        #expect(vac.isPausable == true)

        let tv = try #require(parsed["d-tv"])
        #expect(tv.volumePercent == 35)
        #expect(tv.isMuted == false)

        let volPayload = GoogleHomeFoyerCodec.buildUpdateTraitsBody(deviceId: "d-tv", updates: [.volume(45)])
        #expect(volPayload == #"[[[["d-tv"],[["volume",[["currentVolume",[null,45]]]]]]]]"#)

        let humPayload = GoogleHomeFoyerCodec.buildUpdateTraitsBody(deviceId: "d-hum", updates: [.humiditySetpoint(50)])
        #expect(humPayload == #"[[[["d-hum"],[["humiditySetting",[["humiditySetpointPercent",[null,50]]]]]]]]"#)

        let fanPctPayload = GoogleHomeFoyerCodec.buildUpdateTraitsBody(deviceId: "d-hum", updates: [.fanSpeedPercent(75)])
        #expect(fanPctPayload == #"[[[["d-hum"],[["fanSpeed",[["currentFanSpeedPercent",[null,75]]]]]]]]"#)

        let startPayload = GoogleHomeFoyerCodec.buildUpdateTraitsBody(deviceId: "d-vac", updates: [.startStop(start: true)])
        #expect(startPayload == #"[[[["d-vac"],[["startStop",[["isRunning",[null,null,null,1]]]]]]]]"#)
    }
}
