import Foundation

/// Ownership priority for mounting the single shared Google Home `WKWebView`.
/// Higher priority hosts always win ownership, preventing a background keep-alive host
/// from stealing or detaching the `WKWebView` during animated SwiftUI tab transitions.
public enum WebViewHostPriority: Int, Comparable, Sendable {
    case backgroundKeepAlive = 0
    case visiblePopover = 10
    case visibleDetachedWindow = 20

    public static func < (lhs: WebViewHostPriority, rhs: WebViewHostPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Pure deterministic arbitrator tracking which live host container owns the shared `WKWebView`.
public struct WebViewHostArbitrator: Sendable {
    public struct Registration: Equatable, Sendable {
        public let hostId: UUID
        public let priority: WebViewHostPriority
        public let sequence: UInt64
    }

    private var registrations: [UUID: Registration] = [:]
    private var nextSequence: UInt64 = 1

    public init() {}

    /// Registers or updates a live host and returns the host ID that should currently own the `WKWebView`.
    @discardableResult
    public mutating func register(hostId: UUID, priority: WebViewHostPriority) -> UUID? {
        if let existing = registrations[hostId] {
            if existing.priority != priority {
                registrations[hostId] = Registration(
                    hostId: hostId,
                    priority: priority,
                    sequence: bumpSequence()
                )
            }
        } else {
            registrations[hostId] = Registration(
                hostId: hostId,
                priority: priority,
                sequence: bumpSequence()
            )
        }
        return activeOwnerId
    }

    /// Removes a dismantled host and returns the next highest-priority live host ID (if any).
    @discardableResult
    public mutating func unregister(hostId: UUID) -> UUID? {
        registrations.removeValue(forKey: hostId)
        return activeOwnerId
    }

    /// Highest-priority live host; ties break in favor of the most recently registered host.
    public var activeOwnerId: UUID? {
        registrations.values.max { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }
            return lhs.sequence < rhs.sequence
        }?.hostId
    }

    public var registeredCount: Int {
        registrations.count
    }

    private mutating func bumpSequence() -> UInt64 {
        let seq = nextSequence
        nextSequence &+= 1
        return seq
    }
}
