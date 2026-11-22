import Foundation
import Testing
@testable import GoogleHomeBarCore

@Suite("CastV2 Protobuf & Framing")
struct CastMessageCodecTests {
    @Test("Round-trips UTF-8 CastMessage with 4-byte length prefix")
    func roundTripUTF8Framed() throws {
        let payload = #"{"type":"SET_VOLUME","volume":{"level":0.65},"requestId":42}"#
        let msg = CastMessage(
            protocolVersion: 0,
            sourceId: "sender-1234",
            destinationId: "receiver-0",
            namespace: CastNamespace.receiver.rawValue,
            payload: .utf8(payload)
        )

        let framed = CastMessageCodec.encodeFramed(msg)
        #expect(framed.count > 4)

        let declaredLength = try CastMessageCodec.decodeFrameLength(from: Data(framed.prefix(4)))
        #expect(Int(declaredLength) == framed.count - 4)

        let decoded = try CastMessageCodec.decode(Data(framed.dropFirst(4)))
        #expect(decoded == msg)
        #expect(decoded.utf8String == payload)
    }

    @Test("Round-trips binary payload and multi-byte varint lengths")
    func roundTripBinaryLargePayload() throws {
        let bytes = Data((0..<400).map { UInt8($0 & 0xFF) })
        let msg = CastMessage(
            sourceId: "sender-bin",
            destinationId: "receiver-0",
            namespace: "urn:x-cast:com.google.cast.tp.deviceauth",
            payload: .binary(bytes)
        )

        let encoded = CastMessageCodec.encode(msg)
        let decoded = try CastMessageCodec.decode(encoded)
        #expect(decoded == msg)
    }

    @Test("Skips unknown protobuf fields cleanly")
    func skipsUnknownFields() throws {
        let base = CastMessage(
            sourceId: "s",
            destinationId: "d",
            namespace: CastNamespace.heartbeat.rawValue,
            payload: .utf8(#"{"type":"PONG"}"#)
        )
        var raw = CastMessageCodec.encode(base)
        // Append unknown field 15 (wire type 0 varint = 150) and field 16 (wire type 5 fixed32)
        raw.append(contentsOf: [0x78, 0x96, 0x01])
        raw.append(contentsOf: [0x85, 0x01, 0x01, 0x02, 0x03, 0x04])

        let decoded = try CastMessageCodec.decode(raw)
        #expect(decoded == base)
    }

    @Test("Rejects frames larger than safety cap")
    func rejectsOversizedFrame() {
        let hugeHeader = Data([0x05, 0x00, 0x00, 0x00]) // 83 MB
        #expect(throws: CastCodecError.frameTooLarge(0x0500_0000)) {
            _ = try CastMessageCodec.decodeFrameLength(from: hugeHeader)
        }
    }
}

@Suite("CastV2 Payload Parsing")
struct CastPayloadParserTests {
    @Test("Parses RECEIVER_STATUS with active media app and volume")
    func parseReceiverStatus() {
        let json = """
        {
          "type": "RECEIVER_STATUS",
          "requestId": 1,
          "status": {
            "isStandBy": false,
            "volume": {
              "controlType": "attenuation",
              "level": 0.42,
              "muted": true,
              "stepInterval": 0.05
            },
            "applications": [
              {
                "appId": "CC32E753",
                "displayName": "Spotify",
                "isIdleScreen": false,
                "namespaces": [
                  {"name": "urn:x-cast:com.google.cast.media"}
                ],
                "sessionId": "sess-1",
                "statusText": "Spotify",
                "transportId": "trans-1"
              }
            ]
          }
        }
        """

        let update = CastPayloadParser.parseReceiverStatus(from: json)
        #expect(update != nil)
        #expect(update?.volume?.level == 0.42)
        #expect(update?.volume?.isMuted == true)
        #expect(update?.volume?.isFixedVolume == false)
        #expect(update?.activeApp?.displayName == "Spotify")
        #expect(update?.activeApp?.transportId == "trans-1")
        #expect(update?.activeApp?.supportsMediaNamespace == true)
    }

    @Test("Preserves metadata across incremental MEDIA_STATUS updates")
    func mediaStatusIncrementalMerge() {
        let initialJSON = """
        {
          "type": "MEDIA_STATUS",
          "status": [
            {
              "mediaSessionId": 7,
              "playerState": "PLAYING",
              "currentTime": 12.5,
              "supportedMediaCommands": 195,
              "media": {
                "duration": 210.0,
                "metadata": {
                  "title": "Time",
                  "artist": "Pink Floyd",
                  "albumName": "Dark Side of the Moon",
                  "images": [{"url": "https://example.com/art.jpg"}]
                }
              }
            }
          ]
        }
        """

        let first = CastPayloadParser.parseMediaStatus(from: initialJSON, merging: nil) ?? nil
        #expect(first?.title == "Time")
        #expect(first?.artist == "Pink Floyd")
        #expect(first?.playerState == .playing)
        #expect(first?.canSkipNext == true)

        // Incremental pause update omits `media` object.
        let pausedJSON = """
        {
          "type": "MEDIA_STATUS",
          "status": [
            {
              "mediaSessionId": 7,
              "playerState": "PAUSED",
              "currentTime": 33.0
            }
          ]
        }
        """
        let merged = CastPayloadParser.parseMediaStatus(from: pausedJSON, merging: first) ?? nil
        #expect(merged?.playerState == .paused)
        #expect(merged?.currentTime == 33.0)
        #expect(merged?.title == "Time")
        #expect(merged?.artist == "Pink Floyd")
        #expect(merged?.artworkURL?.absoluteString == "https://example.com/art.jpg")
    }

    @Test("Infers Cast device kinds from model and capability bitmask")
    func deviceKindInference() {
        #expect(CastDeviceKind.infer(modelName: "Google Cast Group", capabilitiesMask: 36) == .speakerGroup)
        #expect(CastDeviceKind.infer(modelName: "Google Nest Hub", capabilitiesMask: 4101) == .smartDisplay)
        #expect(CastDeviceKind.infer(modelName: "Chromecast", capabilitiesMask: 4101) == .tvOrChromecast)
        #expect(CastDeviceKind.infer(modelName: "Nest Mini", capabilitiesMask: 196612) == .speaker)
    }
}

@Suite("Wi-Fi Gating Evaluation")
struct WiFiAccessEvaluatorTests {
    @Test("Blocks when Wi-Fi is off in Any Wi-Fi mode")
    func anyWiFiBlocksOffline() {
        let result = WiFiAccessEvaluator.evaluate(
            mode: .anyWiFi,
            snapshot: WiFiStatusSnapshot(isOnWiFi: false, hasNetworkConnection: false),
            savedHomeSSIDs: [],
            savedHomeDeviceIDs: [],
            discoveredDeviceIDs: [],
            savedHomeSubnet: nil,
            sessionOverrideActive: false
        )
        #expect(result == .blockedNoWiFi)
    }

    @Test("Allows matching Home SSID case-insensitively and blocks different SSID")
    func homeSSIDMatching() {
        let allowed = WiFiAccessEvaluator.evaluate(
            mode: .homeWiFiOnly,
            snapshot: WiFiStatusSnapshot(isOnWiFi: true, hasNetworkConnection: true, currentSSID: "my-home-5g"),
            savedHomeSSIDs: ["My-Home-5G"],
            savedHomeDeviceIDs: [],
            discoveredDeviceIDs: [],
            savedHomeSubnet: nil,
            sessionOverrideActive: false
        )
        #expect(allowed.isAllowed == true)

        let blocked = WiFiAccessEvaluator.evaluate(
            mode: .homeWiFiOnly,
            snapshot: WiFiStatusSnapshot(isOnWiFi: true, hasNetworkConnection: true, currentSSID: "CafeWiFi"),
            savedHomeSSIDs: ["My-Home-5G"],
            savedHomeDeviceIDs: [],
            discoveredDeviceIDs: [],
            savedHomeSubnet: nil,
            sessionOverrideActive: false
        )
        #expect(blocked == .blockedAwayFromHome(currentNetwork: "CafeWiFi", expectedHome: "My-Home-5G"))
    }

    @Test("Allows Home Wi-Fi via discovered Cast devices even without SSID/Location permission")
    func homeDeviceFallbackWithoutSSID() {
        let result = WiFiAccessEvaluator.evaluate(
            mode: .homeWiFiOnly,
            snapshot: WiFiStatusSnapshot(isOnWiFi: true, hasNetworkConnection: true, currentSSID: nil, subnetPrefix: "192.168.1"),
            savedHomeSSIDs: [],
            savedHomeDeviceIDs: ["nest-mini-1"],
            discoveredDeviceIDs: ["nest-mini-1", "tv-2"],
            savedHomeSubnet: "192.168.1",
            sessionOverrideActive: false
        )
        #expect(result == .allowed(reason: "Home devices detected"))
    }

    @Test("Session override bypasses Away block")
    func sessionOverrideAllows() {
        let result = WiFiAccessEvaluator.evaluate(
            mode: .homeWiFiOnly,
            snapshot: WiFiStatusSnapshot(isOnWiFi: true, hasNetworkConnection: true, currentSSID: "HotelWiFi"),
            savedHomeSSIDs: ["Home"],
            savedHomeDeviceIDs: [],
            discoveredDeviceIDs: [],
            savedHomeSubnet: nil,
            sessionOverrideActive: true
        )
        #expect(result.isAllowed == true)
    }
}
