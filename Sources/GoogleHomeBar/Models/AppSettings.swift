import Foundation
import Observation
import ServiceManagement
import GoogleHomeBarCore

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case cast
    case web
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Devices"
        case .cast: return "Cast"
        case .web: return "Web"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .cast: return "hifispeaker.2.fill"
        case .web: return "globe"
        case .settings: return "gearshape.fill"
        }
    }
}

enum PopoverSizePreset: String, CaseIterable, Identifiable {
    case compact
    case standard
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: return "Compact (420 × 560)"
        case .standard: return "Standard (480 × 640)"
        case .large: return "Large (580 × 740)"
        }
    }

    var dimensions: CGSize {
        switch self {
        case .compact: return CGSize(width: 420, height: 560)
        case .standard: return CGSize(width: 480, height: 640)
        case .large: return CGSize(width: 580, height: 740)
        }
    }
}

@Observable
@MainActor
final class AppSettings {
    private let defaults: UserDefaults

    private enum Keys {
        static let wifiMode = "networkAccessMode"
        static let homeSSIDs = "savedHomeSSIDs"
        static let homeDeviceIDs = "savedHomeDeviceIDs"
        static let homeSubnet = "savedHomeSubnet"
        static let hideWhenOffline = "hideIconWhenOffWiFi"
        static let popoverSize = "popoverSizePreset"
        static let webZoom = "webPageZoom"
        static let defaultTab = "defaultTab"
    }

    var wifiGatingMode: WiFiGatingMode {
        didSet { defaults.set(wifiGatingMode.rawValue, forKey: Keys.wifiMode) }
    }

    var savedHomeSSIDs: [String] {
        didSet { defaults.set(savedHomeSSIDs, forKey: Keys.homeSSIDs) }
    }

    var savedHomeDeviceIDs: Set<String> {
        didSet { defaults.set(Array(savedHomeDeviceIDs), forKey: Keys.homeDeviceIDs) }
    }

    var savedHomeSubnet: String? {
        didSet { defaults.set(savedHomeSubnet, forKey: Keys.homeSubnet) }
    }

    var hideIconWhenOffWiFi: Bool {
        didSet { defaults.set(hideIconWhenOffWiFi, forKey: Keys.hideWhenOffline) }
    }

    var popoverSize: PopoverSizePreset {
        didSet { defaults.set(popoverSize.rawValue, forKey: Keys.popoverSize) }
    }

    var webPageZoom: Double {
        didSet { defaults.set(webPageZoom, forKey: Keys.webZoom) }
    }

    var defaultTab: AppTab {
        didSet { defaults.set(defaultTab.rawValue, forKey: Keys.defaultTab) }
    }

    var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    var launchAtLoginError: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.wifiGatingMode = defaults.string(forKey: Keys.wifiMode)
            .flatMap(WiFiGatingMode.init(rawValue:)) ?? .alwaysActive
        self.savedHomeSSIDs = defaults.stringArray(forKey: Keys.homeSSIDs) ?? []
        self.savedHomeDeviceIDs = Set(defaults.stringArray(forKey: Keys.homeDeviceIDs) ?? [])
        self.savedHomeSubnet = defaults.string(forKey: Keys.homeSubnet)
        self.hideIconWhenOffWiFi = defaults.bool(forKey: Keys.hideWhenOffline)
        self.popoverSize = defaults.string(forKey: Keys.popoverSize)
            .flatMap(PopoverSizePreset.init(rawValue:)) ?? .standard
        let storedZoom = defaults.double(forKey: Keys.webZoom)
        self.webPageZoom = storedZoom >= 0.5 && storedZoom <= 1.5 ? storedZoom : 0.85
        let storedTab = defaults.string(forKey: Keys.defaultTab).flatMap(AppTab.init(rawValue:)) ?? .home
        self.defaultTab = storedTab == .settings ? .home : storedTab
    }

    func addHomeSSID(_ ssid: String) {
        let trimmed = ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !savedHomeSSIDs.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            savedHomeSSIDs.append(trimmed)
        }
    }

    func removeHomeSSID(_ ssid: String) {
        savedHomeSSIDs.removeAll { $0 == ssid }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginError = error.localizedDescription
        }
    }
}
