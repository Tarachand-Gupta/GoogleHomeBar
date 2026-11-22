import Foundation
import GoogleHomeBarCore
import Observation

enum DetachedWindowMode: String, CaseIterable, Identifiable {
    case devices = "Devices"
    case cast = "Cast"
    case web = "Google Home Web"
    case settings = "Settings"

    var id: String { rawValue }
}

@Observable
@MainActor
final class AppCoordinator {
    let settings: AppSettings
    let wifiMonitor: WiFiMonitor
    let castManager: CastManager
    let webController: GoogleHomeWebController
    let homeManager: GoogleHomeManager
    private let detachedWindowController = DetachedWindowController()

    var selectedTab: AppTab
    var detachedWindowMode: DetachedWindowMode = .devices
    var sessionOverrideActive = false
    var isDetachedWindowOpen = false

    init(
        settings: AppSettings = AppSettings(),
        wifiMonitor: WiFiMonitor = WiFiMonitor(),
        castManager: CastManager = CastManager(),
        isDemoMode: Bool = false
    ) {
        self.settings = settings
        self.wifiMonitor = wifiMonitor
        self.castManager = castManager
        let webCtrl = GoogleHomeWebController(initialZoom: settings.webPageZoom)
        self.webController = webCtrl
        self.homeManager = GoogleHomeManager(webController: webCtrl)
        self.selectedTab = settings.defaultTab

        if isDemoMode {
            homeManager.loadDemoHome()
            return
        }

        wifiMonitor.onWiFiBecameAvailable = { [weak self] in
            self?.handleNetworkChanged()
        }
        wifiMonitor.onWiFiBecameUnavailable = { [weak self] in
            self?.handleNetworkUnavailable()
        }

        wifiMonitor.start()
        if wifiMonitor.snapshot.hasNetworkConnection || settings.wifiGatingMode == .alwaysActive {
            webCtrl.loadIfNeeded()
        }
        if wifiMonitor.snapshot.isOnWiFi {
            castManager.startBrowsing()
        }
    }

    var accessEvaluation: AccessEvaluation {
        if homeManager.isDemoMode {
            return .allowed(reason: "Demo Mode")
        }
        return WiFiAccessEvaluator.evaluate(
            mode: settings.wifiGatingMode,
            snapshot: wifiMonitor.snapshot,
            savedHomeSSIDs: settings.savedHomeSSIDs,
            savedHomeDeviceIDs: settings.savedHomeDeviceIDs,
            discoveredDeviceIDs: castManager.discoveredDeviceIDs,
            savedHomeSubnet: settings.savedHomeSubnet,
            sessionOverrideActive: sessionOverrideActive
        )
    }

    var shouldShowMenuBarIcon: Bool {
        if !settings.hideIconWhenOffWiFi {
            return true
        }
        return accessEvaluation.isAllowed
    }

    var menuBarSymbolName: String {
        switch accessEvaluation {
        case .allowed:
            return homeManager.activeOnCount > 0 ? "house.fill" : "house"
        case .blockedNoWiFi:
            return "wifi.slash"
        case .blockedAwayFromHome:
            return "house"
        }
    }

    var menuBarTitle: String {
        switch accessEvaluation {
        case .allowed(let reason):
            let total = homeManager.devicesInSelectedStructure.count
            if total > 0 {
                return "Google Home — \(homeManager.activeOnCount) on · \(total) devices"
            }
            return "Google Home — \(reason)"
        case .blockedNoWiFi:
            return "Google Home — Offline"
        case .blockedAwayFromHome:
            return "Google Home — Away from Home Wi-Fi"
        }
    }

    func openDetachedWindow() {
        detachedWindowController.show(coordinator: self)
    }

    func closeDetachedWindow() {
        detachedWindowController.close()
    }

    func refreshAll() {
        wifiMonitor.refreshSnapshot()
        if accessEvaluation.isAllowed {
            if wifiMonitor.snapshot.isOnWiFi {
                castManager.rescan()
            }
            Task {
                await homeManager.refreshAll()
            }
        }
    }

    func signOut() {
        homeManager.resetForSignOut()
        webController.clearSessionAndSignOut()
        selectedTab = .home
        detachedWindowMode = .devices
    }

    func startSignIn() {
        selectedTab = .home
        detachedWindowMode = .devices
        webController.beginInteractiveSignIn()
    }

    func saveCurrentAsHomeNetwork() {
        wifiMonitor.refreshSnapshot()
        if let ssid = wifiMonitor.snapshot.currentSSID, !ssid.isEmpty {
            settings.addHomeSSID(ssid)
        }
        if let subnet = wifiMonitor.snapshot.subnetPrefix, !subnet.isEmpty {
            settings.savedHomeSubnet = subnet
        }
        let detected = castManager.discoveredDeviceIDs
        if !detected.isEmpty {
            settings.savedHomeDeviceIDs.formUnion(detected)
        }
        sessionOverrideActive = false
    }

    func clearSavedHomeNetwork() {
        settings.savedHomeSSIDs = []
        settings.savedHomeSubnet = nil
        settings.savedHomeDeviceIDs = []
    }

    private func handleNetworkChanged() {
        if wifiMonitor.snapshot.isOnWiFi {
            castManager.startBrowsing()
        }
        if !webController.hasLoadedInitially {
            webController.loadIfNeeded()
        } else {
            Task { await homeManager.refreshAll() }
        }
    }

    private func handleNetworkUnavailable() {
        if !wifiMonitor.snapshot.isOnWiFi {
            castManager.stopBrowsing(disconnectDevices: true)
        }
    }
}
