import Foundation
import Network
import CoreWLAN
import CoreLocation
import Darwin
import Observation
import GoogleHomeBarCore

@Observable
@MainActor
final class WiFiMonitor: NSObject {
    private(set) var snapshot = WiFiStatusSnapshot()
    private(set) var locationAuthStatus: CLAuthorizationStatus = .notDetermined

    private let wifiPathMonitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private let generalPathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.playground.GoogleHomeBar.wifi-monitor")
    private let locationManager = CLLocationManager()

    private var lastWiFiSatisfied = false
    private var lastGeneralSatisfied = false
    private var lastWiFiInterfaceName: String?

    var onWiFiBecameAvailable: (() -> Void)?
    var onWiFiBecameUnavailable: (() -> Void)?

    override init() {
        super.init()
        locationManager.delegate = self
        locationAuthStatus = locationManager.authorizationStatus
    }

    func start() {
        wifiPathMonitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            let interfaceName = path.availableInterfaces.first(where: { $0.type == .wifi })?.name
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasOnWiFi = self.lastWiFiSatisfied
                self.lastWiFiSatisfied = satisfied
                self.lastWiFiInterfaceName = interfaceName
                self.refreshSnapshot()

                if satisfied && !wasOnWiFi {
                    self.onWiFiBecameAvailable?()
                } else if !satisfied && wasOnWiFi {
                    self.onWiFiBecameUnavailable?()
                }
            }
        }

        generalPathMonitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lastGeneralSatisfied = satisfied
                self.refreshSnapshot()
            }
        }

        wifiPathMonitor.start(queue: monitorQueue)
        generalPathMonitor.start(queue: monitorQueue)
        refreshSnapshot()
    }

    func stop() {
        wifiPathMonitor.cancel()
        generalPathMonitor.cancel()
    }

    func requestLocationPermissionForSSID() {
        locationManager.requestWhenInUseAuthorization()
    }

    func refreshSnapshot() {
        let cwInterface = CWWiFiClient.shared().interface()
        let ssid = cwInterface?.ssid()
        let ifaceName = lastWiFiInterfaceName ?? cwInterface?.interfaceName ?? "en0"
        let ipInfo = Self.localIPv4Address(forInterface: ifaceName)
        let subnet = ipInfo.flatMap(Self.subnetPrefix(fromIPv4:))

        let powerAndAssociated = (cwInterface?.powerOn() ?? false) && (cwInterface?.wlanChannel() != nil)
        let isOnWiFi = lastWiFiSatisfied || (lastGeneralSatisfied && powerAndAssociated && ipInfo != nil)

        snapshot = WiFiStatusSnapshot(
            isOnWiFi: isOnWiFi,
            hasNetworkConnection: lastGeneralSatisfied || isOnWiFi,
            currentSSID: ssid,
            interfaceName: ifaceName,
            localIPv4Address: ipInfo,
            subnetPrefix: subnet
        )
    }

    private nonisolated static func localIPv4Address(forInterface targetName: String) -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            let interface = current.pointee
            let addrFamily = interface.ifa_addr?.pointee.sa_family
            if addrFamily == UInt8(AF_INET),
               let namePtr = interface.ifa_name,
               String(cString: namePtr) == targetName,
               let addr = interface.ifa_addr {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let res = getnameinfo(
                    addr,
                    socklen_t(addr.pointee.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
                if res == 0 {
                    let bytes = hostname.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                    return String(decoding: bytes, as: UTF8.self)
                }
            }
            ptr = interface.ifa_next
        }
        return nil
    }

    private nonisolated static func subnetPrefix(fromIPv4 ip: String) -> String? {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return nil }
        return parts.prefix(3).joined(separator: ".")
    }
}

extension WiFiMonitor: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            self?.locationAuthStatus = status
            self?.refreshSnapshot()
        }
    }
}
