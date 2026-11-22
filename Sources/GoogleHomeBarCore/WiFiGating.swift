import Foundation

public enum WiFiGatingMode: String, CaseIterable, Identifiable, Sendable {
    case alwaysActive
    case anyWiFi
    case homeWiFiOnly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .alwaysActive: return "Any Internet"
        case .anyWiFi: return "Wi-Fi Only"
        case .homeWiFiOnly: return "Home Wi-Fi"
        }
    }

    public var subtitle: String {
        switch self {
        case .alwaysActive:
            return "Active on any internet connection (Wi-Fi, Ethernet, or hotspot)."
        case .anyWiFi:
            return "Active whenever connected to Wi-Fi; pauses when off Wi-Fi."
        case .homeWiFiOnly:
            return "Active only on your saved Home Wi-Fi (by SSID or home Cast devices)."
        }
    }
}

public struct WiFiStatusSnapshot: Equatable, Sendable {
    public var isOnWiFi: Bool
    public var hasNetworkConnection: Bool
    public var currentSSID: String?
    public var interfaceName: String?
    public var localIPv4Address: String?
    public var subnetPrefix: String?

    public init(
        isOnWiFi: Bool = false,
        hasNetworkConnection: Bool = false,
        currentSSID: String? = nil,
        interfaceName: String? = nil,
        localIPv4Address: String? = nil,
        subnetPrefix: String? = nil
    ) {
        self.isOnWiFi = isOnWiFi
        self.hasNetworkConnection = hasNetworkConnection
        self.currentSSID = currentSSID
        self.interfaceName = interfaceName
        self.localIPv4Address = localIPv4Address
        self.subnetPrefix = subnetPrefix
    }
}

public enum AccessEvaluation: Equatable, Sendable {
    case allowed(reason: String)
    case blockedNoWiFi
    case blockedAwayFromHome(currentNetwork: String?, expectedHome: String?)

    public var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }
}

public enum WiFiAccessEvaluator {
    public static func evaluate(
        mode: WiFiGatingMode,
        snapshot: WiFiStatusSnapshot,
        savedHomeSSIDs: [String],
        savedHomeDeviceIDs: Set<String>,
        discoveredDeviceIDs: Set<String>,
        savedHomeSubnet: String?,
        sessionOverrideActive: Bool
    ) -> AccessEvaluation {
        if sessionOverrideActive {
            return .allowed(reason: "Session override active")
        }

        switch mode {
        case .alwaysActive:
            if snapshot.hasNetworkConnection {
                return .allowed(reason: snapshot.isOnWiFi ? "On Wi-Fi" : "Connected")
            }
            return .blockedNoWiFi

        case .anyWiFi:
            guard snapshot.isOnWiFi else {
                return .blockedNoWiFi
            }
            if let ssid = snapshot.currentSSID, !ssid.isEmpty {
                return .allowed(reason: ssid)
            }
            return .allowed(reason: "On Wi-Fi")

        case .homeWiFiOnly:
            guard snapshot.isOnWiFi else {
                return .blockedNoWiFi
            }

            let normalizedSavedSSIDs = Set(
                savedHomeSSIDs
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
            )

            // 1. Direct SSID match (when Location permission provides current SSID)
            if let ssid = snapshot.currentSSID?.trimmingCharacters(in: .whitespacesAndNewlines),
               !ssid.isEmpty,
               !normalizedSavedSSIDs.isEmpty {
                if normalizedSavedSSIDs.contains(ssid.lowercased()) {
                    return .allowed(reason: ssid)
                } else {
                    return .blockedAwayFromHome(
                        currentNetwork: ssid,
                        expectedHome: savedHomeSSIDs.first
                    )
                }
            }

            // 2. Zero-permission fallback: matched known Home Cast devices discovered on this LAN
            if !savedHomeDeviceIDs.isEmpty && !savedHomeDeviceIDs.isDisjoint(with: discoveredDeviceIDs) {
                return .allowed(reason: "Home devices detected")
            }

            // 3. Fallback: saved Home LAN subnet prefix match (when SSID isn't readable)
            if normalizedSavedSSIDs.isEmpty,
               let savedSubnet = savedHomeSubnet, !savedSubnet.isEmpty,
               let currentSubnet = snapshot.subnetPrefix {
                if savedSubnet == currentSubnet {
                    return .allowed(reason: "Home Wi-Fi (\(currentSubnet).x)")
                } else {
                    return .blockedAwayFromHome(
                        currentNetwork: "\(currentSubnet).x",
                        expectedHome: "\(savedSubnet).x"
                    )
                }
            }

            // 4. If user enabled Home Wi-Fi Only but hasn't saved any home network/device yet,
            // allow on Wi-Fi so they can save their current network without getting locked out.
            if normalizedSavedSSIDs.isEmpty && savedHomeDeviceIDs.isEmpty && (savedHomeSubnet?.isEmpty ?? true) {
                return .allowed(reason: "On Wi-Fi (no home filter saved)")
            }

            return .blockedAwayFromHome(
                currentNetwork: snapshot.currentSSID ?? snapshot.subnetPrefix.map { "\($0).x" },
                expectedHome: savedHomeSSIDs.first ?? savedHomeSubnet.map { "\($0).x" }
            )
        }
    }
}
