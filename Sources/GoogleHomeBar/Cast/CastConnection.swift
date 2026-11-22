import Foundation
import Network
import Security
import GoogleHomeBarCore

/// Manages a live CastV2 TLS socket to a single local Google Home / Nest / Chromecast device.
final class CastConnection: @unchecked Sendable {
    struct Callbacks: Sendable {
        var onStateChange: @Sendable (CastConnectionState, String?) -> Void
        var onReceiverStatus: @Sendable (CastReceiverStatusUpdate) -> Void
        var onMediaStatus: @Sendable (CastMediaState?) -> Void
    }

    private let deviceId: String
    private let endpoint: NWEndpoint
    private let callbacks: Callbacks
    private let queue: DispatchQueue
    private let senderId: String

    private var connection: NWConnection?
    private var heartbeatTimer: DispatchSourceTimer?
    private var reconnectWorkItem: DispatchWorkItem?
    private var isStopped = false
    private var requestCounter = 0
    private var reconnectAttempts = 0

    private var connectedTransportId: String?
    private var lastMediaState: CastMediaState?
    private var lastKnownHostDescription: String?

    init(deviceId: String, endpoint: NWEndpoint, callbacks: Callbacks) {
        self.deviceId = deviceId
        self.endpoint = endpoint
        self.callbacks = callbacks
        self.queue = DispatchQueue(label: "com.playground.GoogleHomeBar.cast.\(deviceId)")
        self.senderId = "sender-\(UUID().uuidString.prefix(8).lowercased())"
    }

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isStopped = false
            self.openConnection()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isStopped = true
            self.reconnectWorkItem?.cancel()
            self.reconnectWorkItem = nil
            self.sendCloseIfPossible()
            self.teardownSocket()
            self.callbacks.onStateChange(.disconnected, self.lastKnownHostDescription)
        }
    }

    func refreshStatus() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.connection?.state != .ready {
                if !self.isStopped {
                    self.openConnection()
                }
                return
            }
            self.sendReceiverGetStatus()
            if let transportId = self.connectedTransportId {
                self.sendMediaGetStatus(transportId: transportId)
            }
        }
    }

    func setVolume(level: Double) {
        let clamped = min(max(level, 0.0), 1.0)
        queue.async { [weak self] in
            guard let self else { return }
            let reqId = self.nextRequestId()
            self.sendJSON(
                destinationId: "receiver-0",
                namespace: .receiver,
                object: [
                    "type": "SET_VOLUME",
                    "volume": ["level": clamped],
                    "requestId": reqId
                ]
            )
        }
    }

    func setMuted(_ muted: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            let reqId = self.nextRequestId()
            self.sendJSON(
                destinationId: "receiver-0",
                namespace: .receiver,
                object: [
                    "type": "SET_VOLUME",
                    "volume": ["muted": muted],
                    "requestId": reqId
                ]
            )
        }
    }

    func stopApplication(sessionId: String) {
        queue.async { [weak self] in
            guard let self else { return }
            let reqId = self.nextRequestId()
            self.sendJSON(
                destinationId: "receiver-0",
                namespace: .receiver,
                object: [
                    "type": "STOP",
                    "sessionId": sessionId,
                    "requestId": reqId
                ]
            )
        }
    }

    func sendMediaCommand(_ command: String) {
        queue.async { [weak self] in
            self?.sendMediaCommandOnQueue(command)
        }
    }

    func seek(to seconds: Double) {
        let clamped = max(0, seconds)
        queue.async { [weak self] in
            self?.sendMediaCommandOnQueue("SEEK", extra: ["currentTime": clamped])
        }
    }

    func skipTrack(delta: Int) {
        queue.async { [weak self] in
            self?.sendMediaCommandOnQueue("QUEUE_UPDATE", extra: ["jump": delta])
        }
    }

    private func sendMediaCommandOnQueue(_ command: String, extra: [String: Any] = [:]) {
        guard let transportId = connectedTransportId,
              let mediaSessionId = lastMediaState?.mediaSessionId else {
            return
        }
        var body = extra
        body["type"] = command
        body["mediaSessionId"] = mediaSessionId
        body["requestId"] = nextRequestId()
        sendJSON(
            destinationId: transportId,
            namespace: .media,
            object: body
        )
    }

    // MARK: - Socket Lifecycle (queue-confined)

    private func openConnection() {
        teardownSocket()
        callbacks.onStateChange(.connecting, lastKnownHostDescription)

        let tlsOptions = NWProtocolTLS.Options()
        // Google Cast devices on LAN present device-issued self-signed TLS certificates.
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, _, verifyComplete in
                verifyComplete(true)
            },
            queue
        )

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.connectionTimeout = 8

        let parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)

        let conn = NWConnection(to: endpoint, using: parameters)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self, weak conn] state in
            guard let self, self.connection === conn else { return }
            switch state {
            case .ready:
                self.reconnectAttempts = 0
                self.lastKnownHostDescription = self.extractRemoteAddress(from: conn)
                self.callbacks.onStateChange(.connected, self.lastKnownHostDescription)
                self.sendJSON(destinationId: "receiver-0", namespace: .connection, object: ["type": "CONNECT"])
                self.sendReceiverGetStatus()
                self.startHeartbeat()
                self.receiveNextFrame(on: conn)

            case .failed(let error):
                self.teardownSocket()
                self.callbacks.onStateChange(.failed(error.localizedDescription), self.lastKnownHostDescription)
                self.scheduleReconnect()

            case .waiting(let error):
                self.callbacks.onStateChange(.connecting, self.lastKnownHostDescription)
                if case .posix(let code) = error, code == .ECONNREFUSED {
                    self.teardownSocket()
                    self.scheduleReconnect()
                }

            case .cancelled:
                break

            default:
                break
            }
        }

        conn.start(queue: queue)
    }

    private func teardownSocket() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        connectedTransportId = nil
        if let conn = connection {
            conn.stateUpdateHandler = nil
            conn.cancel()
        }
        connection = nil
    }

    private func scheduleReconnect() {
        guard !isStopped else { return }
        reconnectWorkItem?.cancel()
        reconnectAttempts += 1
        let delay = min(Double(1 << min(reconnectAttempts, 5)), 30.0)
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isStopped else { return }
            self.openConnection()
        }
        reconnectWorkItem = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func startHeartbeat() {
        heartbeatTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            self?.sendJSON(destinationId: "receiver-0", namespace: .heartbeat, object: ["type": "PING"])
        }
        timer.resume()
        heartbeatTimer = timer
    }

    private func sendCloseIfPossible() {
        if let transportId = connectedTransportId {
            sendJSON(destinationId: transportId, namespace: .connection, object: ["type": "CLOSE"])
        }
        sendJSON(destinationId: "receiver-0", namespace: .connection, object: ["type": "CLOSE"])
    }

    // MARK: - Framing & Dispatch

    private func receiveNextFrame(on conn: NWConnection?) {
        guard let conn, self.connection === conn, !isStopped else { return }
        conn.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self, weak conn] data, _, isComplete, error in
            guard let self, let conn, self.connection === conn else { return }
            if let error {
                self.teardownSocket()
                self.callbacks.onStateChange(.failed(error.localizedDescription), self.lastKnownHostDescription)
                self.scheduleReconnect()
                return
            }
            guard let header = data, header.count == 4 else {
                if isComplete {
                    self.teardownSocket()
                    self.callbacks.onStateChange(.disconnected, self.lastKnownHostDescription)
                    self.scheduleReconnect()
                }
                return
            }

            do {
                let frameLength = Int(try CastMessageCodec.decodeFrameLength(from: header))
                if frameLength == 0 {
                    self.receiveNextFrame(on: conn)
                    return
                }
                self.receiveFrameBody(length: frameLength, on: conn)
            } catch {
                self.teardownSocket()
                self.callbacks.onStateChange(.failed("Protocol framing error"), self.lastKnownHostDescription)
                self.scheduleReconnect()
            }
        }
    }

    private func receiveFrameBody(length: Int, on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self, weak conn] data, _, _, error in
            guard let self, let conn, self.connection === conn else { return }
            if let error {
                self.teardownSocket()
                self.callbacks.onStateChange(.failed(error.localizedDescription), self.lastKnownHostDescription)
                self.scheduleReconnect()
                return
            }
            if let payloadData = data, payloadData.count == length,
               let message = try? CastMessageCodec.decode(payloadData) {
                self.handleIncoming(message)
            }
            self.receiveNextFrame(on: conn)
        }
    }

    private func handleIncoming(_ message: CastMessage) {
        guard let text = message.utf8String else { return }

        switch message.namespace {
        case CastNamespace.heartbeat.rawValue:
            if CastPayloadParser.parseMessageType(from: text) == "PING" {
                sendJSON(destinationId: message.sourceId, namespace: .heartbeat, object: ["type": "PONG"])
            }

        case CastNamespace.receiver.rawValue:
            if let update = CastPayloadParser.parseReceiverStatus(from: text) {
                callbacks.onReceiverStatus(update)
                syncMediaTransport(with: update.activeApp)
            }

        case CastNamespace.media.rawValue:
            if let parsed = CastPayloadParser.parseMediaStatus(from: text, merging: lastMediaState) {
                lastMediaState = parsed
                callbacks.onMediaStatus(parsed)
            }

        case CastNamespace.connection.rawValue:
            if CastPayloadParser.parseMessageType(from: text) == "CLOSE",
               message.sourceId == connectedTransportId {
                connectedTransportId = nil
                lastMediaState = nil
                callbacks.onMediaStatus(nil)
            }

        default:
            break
        }
    }

    private func syncMediaTransport(with activeApp: CastActiveApp?) {
        guard let app = activeApp, !app.isIdleScreen, app.supportsMediaNamespace else {
            if let oldTransport = connectedTransportId {
                sendJSON(destinationId: oldTransport, namespace: .connection, object: ["type": "CLOSE"])
                connectedTransportId = nil
            }
            if lastMediaState != nil {
                lastMediaState = nil
                callbacks.onMediaStatus(nil)
            }
            return
        }

        if connectedTransportId != app.transportId {
            if let oldTransport = connectedTransportId {
                sendJSON(destinationId: oldTransport, namespace: .connection, object: ["type": "CLOSE"])
            }
            connectedTransportId = app.transportId
            sendJSON(destinationId: app.transportId, namespace: .connection, object: ["type": "CONNECT"])
            sendMediaGetStatus(transportId: app.transportId)
        }
    }

    private func sendReceiverGetStatus() {
        let reqId = nextRequestId()
        sendJSON(
            destinationId: "receiver-0",
            namespace: .receiver,
            object: ["type": "GET_STATUS", "requestId": reqId]
        )
    }

    private func sendMediaGetStatus(transportId: String) {
        let reqId = nextRequestId()
        sendJSON(
            destinationId: transportId,
            namespace: .media,
            object: ["type": "GET_STATUS", "requestId": reqId]
        )
    }

    private func sendJSON(destinationId: String, namespace: CastNamespace, object: [String: Any]) {
        guard let conn = connection, conn.state == .ready else { return }
        guard let msg = try? CastMessage.json(
            sourceId: senderId,
            destinationId: destinationId,
            namespace: namespace,
            object: object
        ) else { return }

        let framed = CastMessageCodec.encodeFramed(msg)
        conn.send(content: framed, completion: .contentProcessed { _ in })
    }

    private func nextRequestId() -> Int {
        requestCounter += 1
        return requestCounter
    }

    private func extractRemoteAddress(from conn: NWConnection?) -> String? {
        guard let remote = conn?.currentPath?.remoteEndpoint else { return nil }
        if case .hostPort(let host, let port) = remote {
            let cleanHost: String
            switch host {
            case .ipv4(let addr):
                cleanHost = "\(addr)"
            case .ipv6(let addr):
                cleanHost = "\(addr)"
            case .name(let name, _):
                cleanHost = name
            @unknown default:
                cleanHost = "\(host)"
            }
            return "\(cleanHost):\(port)"
        }
        return nil
    }
}
