import Foundation

public enum CastDeviceKind: String, Sendable, Equatable {
    case speaker
    case smartDisplay
    case tvOrChromecast
    case speakerGroup

    public var sfSymbol: String {
        switch self {
        case .speaker: return "homepodmini.fill"
        case .smartDisplay: return "display"
        case .tvOrChromecast: return "tv.fill"
        case .speakerGroup: return "hifispeaker.2.fill"
        }
    }

    public static func infer(modelName: String, capabilitiesMask: Int?) -> CastDeviceKind {
        let lower = modelName.lowercased()
        if lower.contains("group") || ((capabilitiesMask ?? 0) & 0x20) != 0 {
            return .speakerGroup
        }
        if lower.contains("hub") || lower.contains("display") || lower.contains("smart clock") {
            return .smartDisplay
        }
        if lower.contains("tv") || lower.contains("chromecast") || lower.contains("shield") || lower.contains("streamer") {
            return .tvOrChromecast
        }
        if let mask = capabilitiesMask, (mask & 0x01) != 0 {
            return .tvOrChromecast
        }
        return .speaker
    }
}

public enum CastConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case failed(String)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

public struct CastVolumeState: Equatable, Sendable {
    public var level: Double
    public var isMuted: Bool
    public var stepInterval: Double
    public var isFixedVolume: Bool

    public init(
        level: Double = 0.5,
        isMuted: Bool = false,
        stepInterval: Double = 0.05,
        isFixedVolume: Bool = false
    ) {
        self.level = min(max(level, 0.0), 1.0)
        self.isMuted = isMuted
        self.stepInterval = stepInterval > 0 ? stepInterval : 0.05
        self.isFixedVolume = isFixedVolume
    }
}

public struct CastActiveApp: Equatable, Sendable {
    public var appId: String
    public var displayName: String
    public var sessionId: String
    public var transportId: String
    public var statusText: String
    public var isIdleScreen: Bool
    public var supportsMediaNamespace: Bool

    public init(
        appId: String,
        displayName: String,
        sessionId: String,
        transportId: String,
        statusText: String,
        isIdleScreen: Bool,
        supportsMediaNamespace: Bool
    ) {
        self.appId = appId
        self.displayName = displayName
        self.sessionId = sessionId
        self.transportId = transportId
        self.statusText = statusText
        self.isIdleScreen = isIdleScreen
        self.supportsMediaNamespace = supportsMediaNamespace
    }
}

public enum CastPlayerState: String, Equatable, Sendable {
    case playing = "PLAYING"
    case paused = "PAUSED"
    case buffering = "BUFFERING"
    case idle = "IDLE"
    case unknown = "UNKNOWN"
}

public struct CastMediaState: Equatable, Sendable {
    public var mediaSessionId: Int
    public var playerState: CastPlayerState
    public var title: String?
    public var subtitle: String?
    public var artist: String?
    public var albumName: String?
    public var artworkURL: URL?
    public var currentTime: Double?
    public var duration: Double?
    public var supportedCommands: Int

    public init(
        mediaSessionId: Int,
        playerState: CastPlayerState,
        title: String? = nil,
        subtitle: String? = nil,
        artist: String? = nil,
        albumName: String? = nil,
        artworkURL: URL? = nil,
        currentTime: Double? = nil,
        duration: Double? = nil,
        supportedCommands: Int = 0
    ) {
        self.mediaSessionId = mediaSessionId
        self.playerState = playerState
        self.title = title
        self.subtitle = subtitle
        self.artist = artist
        self.albumName = albumName
        self.artworkURL = artworkURL
        self.currentTime = currentTime
        self.duration = duration
        self.supportedCommands = supportedCommands
    }

    public var canPause: Bool { (supportedCommands & 1) != 0 || playerState == .playing || playerState == .paused }
    public var canSeek: Bool { (supportedCommands & 2) != 0 && (duration ?? 0) > 0 }
    public var canSkipNext: Bool { (supportedCommands & 64) != 0 || (supportedCommands & 16) != 0 }
    public var canSkipPrevious: Bool { (supportedCommands & 128) != 0 || (supportedCommands & 32) != 0 }

    public var secondaryLine: String? {
        if let artist, !artist.isEmpty {
            if let albumName, !albumName.isEmpty {
                return "\(artist) — \(albumName)"
            }
            return artist
        }
        if let subtitle, !subtitle.isEmpty {
            return subtitle
        }
        return nil
    }
}

public struct CastReceiverStatusUpdate: Equatable, Sendable {
    public var volume: CastVolumeState?
    public var activeApp: CastActiveApp?
    public var isStandBy: Bool?
}

public enum CastPayloadParser {
    public static func parseMessageType(from jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict["type"] as? String
    }

    public static func parseReceiverStatus(from jsonString: String) -> CastReceiverStatusUpdate? {
        guard let data = jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["type"] as? String) == "RECEIVER_STATUS",
              let status = root["status"] as? [String: Any] else {
            return nil
        }

        var volumeState: CastVolumeState?
        if let vol = status["volume"] as? [String: Any] {
            let level = (vol["level"] as? Double) ?? 0.5
            let muted = (vol["muted"] as? Bool) ?? false
            let step = (vol["stepInterval"] as? Double) ?? 0.05
            let controlType = (vol["controlType"] as? String)?.lowercased() ?? "attenuation"
            volumeState = CastVolumeState(
                level: level,
                isMuted: muted,
                stepInterval: step,
                isFixedVolume: controlType == "fixed"
            )
        }

        var activeApp: CastActiveApp?
        if let apps = status["applications"] as? [[String: Any]] {
            // Prefer non-idle applications; fall back to the first reported app.
            let chosen = apps.first(where: { ($0["isIdleScreen"] as? Bool) != true }) ?? apps.first
            if let app = chosen,
               let appId = app["appId"] as? String,
               let sessionId = app["sessionId"] as? String,
               let transportId = app["transportId"] as? String {
                let nsList = (app["namespaces"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
                activeApp = CastActiveApp(
                    appId: appId,
                    displayName: (app["displayName"] as? String) ?? "Casting",
                    sessionId: sessionId,
                    transportId: transportId,
                    statusText: (app["statusText"] as? String) ?? "",
                    isIdleScreen: (app["isIdleScreen"] as? Bool) ?? false,
                    supportsMediaNamespace: nsList.contains(CastNamespace.media.rawValue)
                )
            }
        }

        return CastReceiverStatusUpdate(
            volume: volumeState,
            activeApp: activeApp,
            isStandBy: status["isStandBy"] as? Bool
        )
    }

    /// Parses `MEDIA_STATUS` and preserves previous metadata if the incoming status omits `media`
    /// for the same `mediaSessionId` (standard CastV2 incremental update behavior).
    public static func parseMediaStatus(
        from jsonString: String,
        merging previous: CastMediaState?
    ) -> CastMediaState?? {
        guard let data = jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["type"] as? String) == "MEDIA_STATUS",
              let statusList = root["status"] as? [[String: Any]] else {
            return nil // Not a MEDIA_STATUS message
        }

        guard let first = statusList.first,
              let mediaSessionId = first["mediaSessionId"] as? Int else {
            return .some(nil) // Explicitly cleared media session
        }

        let rawState = (first["playerState"] as? String) ?? "UNKNOWN"
        let playerState = CastPlayerState(rawValue: rawState) ?? .unknown
        let currentTime = first["currentTime"] as? Double
        let supportedCommands = (first["supportedMediaCommands"] as? Int) ?? previous?.supportedCommands ?? 0

        let sameSession = previous?.mediaSessionId == mediaSessionId
        var title = sameSession ? previous?.title : nil
        var subtitle = sameSession ? previous?.subtitle : nil
        var artist = sameSession ? previous?.artist : nil
        var albumName = sameSession ? previous?.albumName : nil
        var artworkURL = sameSession ? previous?.artworkURL : nil
        var duration = sameSession ? previous?.duration : nil

        if let media = first["media"] as? [String: Any] {
            if let dur = media["duration"] as? Double {
                duration = dur
            }
            if let metadata = media["metadata"] as? [String: Any] {
                if let t = metadata["title"] as? String, !t.isEmpty { title = t }
                if let s = metadata["subtitle"] as? String, !s.isEmpty { subtitle = s }
                if let a = metadata["artist"] as? String, !a.isEmpty { artist = a }
                if let a2 = metadata["albumArtist"] as? String, !a2.isEmpty, artist == nil { artist = a2 }
                if let alb = metadata["albumName"] as? String, !alb.isEmpty { albumName = alb }
                if let images = metadata["images"] as? [[String: Any]],
                   let urlStr = images.first?["url"] as? String,
                   let parsedURL = URL(string: urlStr) {
                    artworkURL = parsedURL
                }
            }
        }

        return .some(
            CastMediaState(
                mediaSessionId: mediaSessionId,
                playerState: playerState,
                title: title,
                subtitle: subtitle,
                artist: artist,
                albumName: albumName,
                artworkURL: artworkURL,
                currentTime: currentTime,
                duration: duration,
                supportedCommands: supportedCommands
            )
        )
    }

    public static func parseTXTRecord(_ dict: [String: String]) -> (id: String, name: String, model: String, statusText: String, capabilitiesMask: Int?) {
        let id = dict["id"] ?? UUID().uuidString
        let name = dict["fn"]?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Google Cast Device"
        let model = dict["md"]?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Cast Device"
        let statusText = dict["rs"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let ca = dict["ca"].flatMap(Int.init)
        return (id, name, model, statusText, ca)
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
