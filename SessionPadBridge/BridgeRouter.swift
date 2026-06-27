// BridgeRouter.swift
// Relays messages between Ableton Live (TCP) and iOS clients (WebSocket).

import Foundation
import os.log

enum BridgeStatus: Equatable {
    case starting
    case waitingForLive
    case liveConnected
    case liveAndIOS
}

@MainActor
final class BridgeRouter: ObservableObject {

    static let shared = BridgeRouter()

    @Published private(set) var status: BridgeStatus = .starting
    @Published private(set) var sessionName: String = "Ableton Live"
    @Published private(set) var iosClientCount: Int = 0
    @Published private(set) var liveConnected: Bool = false
    @Published private(set) var startError: String?

    private let log = OSLog(subsystem: "com.scharovsky.SessionPadBridge", category: "Router")
    private let liveLink = LiveLinkServer()
    private let iosServer = IOSWebSocketServer()

    private var isRunning = false
    private var snapshotRev = 0
    private var cachedFullStateText: String?
    private var subscribedClients: Set<UUID> = []
    private var pendingCmdClients: [String: UUID] = [:]
    private var heartbeatTimer: Timer?

    func start() {
        guard !isRunning else { return }
        liveLink.delegate = self
        iosServer.delegate = self
        do {
            try liveLink.start()
            try iosServer.start()
            isRunning = true
            startError = nil
            status = .waitingForLive
            startHeartbeatTimer()
            os_log(.info, log: log, "Bridge started: live link :%d, iOS WS :%d", Int(SPBridge.liveLinkPort), Int(SPBridge.iosWebSocketPort))
        } catch {
            startError = error.localizedDescription
            os_log(.error, log: log, "Bridge start failed: %{public}@", error.localizedDescription)
        }
    }

    func stop() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        liveLink.stop()
        iosServer.stop()
        subscribedClients.removeAll()
        cachedFullStateText = nil
        snapshotRev = 0
        liveConnected = false
        iosClientCount = 0
        isRunning = false
        status = .starting
    }

    // MARK: - iOS message handling

    private func handleIOSMessage(_ text: String, from clientId: UUID) {
        guard let message = try? ProtocolCodec.decode(text) else { return }
        let msgId = message.id

        switch message.t {
        case MessageType.hello:
            handleHello(message, clientId: clientId)
        case MessageType.subscribe:
            subscribedClients.insert(clientId)
            sendAck(ok: true, clientId: clientId, msgId: msgId)
        case MessageType.getState:
            requestFullStateFromLive(msgId: msgId)
        case MessageType.heartbeat:
            respondHeartbeat(clientId: clientId, msgId: msgId)
        case MessageType.cmd:
            if let msgId = message.id {
                pendingCmdClients[msgId] = clientId
            }
            forwardToLive(text: text)
        default:
            sendError("unknown message type: \(message.t)", clientId: clientId, msgId: msgId)
        }
    }

    private func handleHello(_ message: WireMessage, clientId: UUID) {
        guard let payload = try? ProtocolCodec.decodePayload(HelloPayload.self, from: message) else {
            sendError("invalid hello payload", clientId: clientId, msgId: message.id)
            return
        }

        let chosen = SPProtocol.supportedVersions.first { payload.protocolVersions.contains($0) }
            ?? SPProtocol.version

        subscribedClients.insert(clientId)

        do {
            let welcome = try ProtocolCodec.welcome(
                chosenVersion: chosen,
                snapshotRev: snapshotRev,
                sessionName: sessionName,
                msgId: message.id
            )
            iosServer.send(to: clientId, text: welcome)
        } catch {
            os_log(.error, log: log, "Welcome encode failed")
        }

        if let cached = cachedFullStateText {
            iosServer.send(to: clientId, text: cached)
        } else if liveConnected {
            requestFullStateFromLive(msgId: nil)
        }
    }

    private func requestFullStateFromLive(msgId: String?) {
        guard liveConnected else { return }
        do {
            var msg = WireMessage(t: MessageType.getState)
            msg.id = msgId
            let text = try ProtocolCodec.encode(msg)
            liveLink.send(text: text)
        } catch {
            os_log(.error, log: log, "getState forward failed")
        }
    }

    private func respondHeartbeat(clientId: UUID, msgId: String?) {
        do {
            var text = try ProtocolCodec.heartbeat()
            if let msgId, var msg = try? ProtocolCodec.decode(text) {
                msg.id = msgId
                text = try ProtocolCodec.encode(msg)
            }
            iosServer.send(to: clientId, text: text)
        } catch {
            os_log(.error, log: log, "Heartbeat response failed")
        }
    }

    private func sendAck(ok: Bool, clientId: UUID, msgId: String?) {
        guard let msgId else { return }
        do {
            let text = try ProtocolCodec.ack(ok: ok, msgId: msgId)
            iosServer.send(to: clientId, text: text)
        } catch {
            os_log(.error, log: log, "Ack encode failed")
        }
    }

    private func sendError(_ message: String, clientId: UUID, msgId: String?) {
        do {
            let text = try ProtocolCodec.errorMessage(message, msgId: msgId)
            iosServer.send(to: clientId, text: text)
        } catch {
            os_log(.error, log: log, "Error encode failed")
        }
    }

    private func forwardToLive(text: String) {
        guard liveConnected else {
            // Best-effort ack failure if Live is offline
            if let message = try? ProtocolCodec.decode(text), let msgId = message.id {
                for clientId in subscribedClients {
                    do {
                        let ack = try ProtocolCodec.ack(ok: false, error: "Ableton Live not connected", msgId: msgId)
                        iosServer.send(to: clientId, text: ack)
                    } catch { }
                }
            }
            return
        }
        liveLink.send(text: text)
    }

    // MARK: - Live message handling

    private func handleLiveMessage(_ text: String) {
        guard let message = try? ProtocolCodec.decode(text) else { return }

        switch message.t {
        case MessageType.stateFull:
            if let payload = try? ProtocolCodec.decodePayload(FullStatePayload.self, from: message) {
                snapshotRev = payload.rev
            }
            cachedFullStateText = text
            iosServer.broadcast(text: text)
            updateStatus()

        case MessageType.bridgeSession:
            if let name = message.payload?.objectValue?["sessionName"]?.stringValue, !name.isEmpty {
                sessionName = name
            }

        case MessageType.deltaClip, MessageType.deltaTrack, MessageType.deltaScene, MessageType.deltaTransport:
            iosServer.broadcast(text: text)

        case MessageType.ack:
            if let msgId = message.id, let clientId = pendingCmdClients.removeValue(forKey: msgId) {
                iosServer.send(to: clientId, text: text)
            } else {
                iosServer.broadcast(text: text)
            }

        case MessageType.heartbeat:
            iosServer.broadcast(text: text)

        case MessageType.error:
            iosServer.broadcast(text: text)

        default:
            break
        }
    }

    private func updateStatus() {
        if liveConnected && iosClientCount > 0 {
            status = .liveAndIOS
        } else if liveConnected {
            status = .liveConnected
        } else {
            status = .waitingForLive
        }
    }

    private func startHeartbeatTimer() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(SPProtocol.heartbeatIntervalMs) / 1000.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.broadcastHeartbeat()
            }
        }
    }

    private func broadcastHeartbeat() {
        guard liveConnected || iosClientCount > 0 else { return }
        do {
            let text = try ProtocolCodec.heartbeat()
            if iosClientCount > 0 {
                iosServer.broadcast(text: text)
            }
        } catch { }
    }
}

// MARK: - LiveLinkServerDelegate

extension BridgeRouter: LiveLinkServerDelegate {
    nonisolated func liveLinkServerDidConnect(_ server: LiveLinkServer) {
        Task { @MainActor in
            liveConnected = true
            cachedFullStateText = nil
            status = .liveConnected
            requestFullStateFromLive(msgId: nil)
        }
    }

    nonisolated func liveLinkServerDidDisconnect(_ server: LiveLinkServer) {
        Task { @MainActor in
            liveConnected = false
            cachedFullStateText = nil
            updateStatus()
        }
    }

    nonisolated func liveLinkServer(_ server: LiveLinkServer, didReceive text: String) {
        Task { @MainActor in
            handleLiveMessage(text)
        }
    }
}

// MARK: - IOSWebSocketServerDelegate

extension BridgeRouter: IOSWebSocketServerDelegate {
    nonisolated func iosWebSocketServer(_ server: IOSWebSocketServer, clientDidConnect id: UUID) {
        Task { @MainActor in
            iosClientCount = server.connectedClientCount
            updateStatus()
        }
    }

    nonisolated func iosWebSocketServer(_ server: IOSWebSocketServer, clientDidDisconnect id: UUID) {
        Task { @MainActor in
            subscribedClients.remove(id)
            iosClientCount = server.connectedClientCount
            updateStatus()
        }
    }

    nonisolated func iosWebSocketServer(_ server: IOSWebSocketServer, client id: UUID, didReceive text: String) {
        Task { @MainActor in
            handleIOSMessage(text, from: id)
        }
    }
}
