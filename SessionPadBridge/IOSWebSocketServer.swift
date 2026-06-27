// IOSWebSocketServer.swift
// WebSocket server for iOS clients with Bonjour advertisement.

import Foundation
import Network
import os.log

protocol IOSWebSocketServerDelegate: AnyObject {
    func iosWebSocketServer(_ server: IOSWebSocketServer, clientDidConnect id: UUID)
    func iosWebSocketServer(_ server: IOSWebSocketServer, clientDidDisconnect id: UUID)
    func iosWebSocketServer(_ server: IOSWebSocketServer, client id: UUID, didReceive text: String)
}

final class IOSWebSocketServer: @unchecked Sendable {

    weak var delegate: IOSWebSocketServerDelegate?

    private let log = OSLog(subsystem: "com.scharovsky.SessionPadBridge", category: "WebSocket")
    private let queue = DispatchQueue(label: "com.scharovsky.SessionPadBridge.websocket")
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]

    private(set) var connectedClientCount = 0
    private(set) var advertisedPort: UInt16 = SPBridge.iosWebSocketPort

    func start(port: UInt16 = SPBridge.iosWebSocketPort, sessionName: String = "Ableton Live") throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.includePeerToPeer = true

        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw BridgeError.invalidPort
        }

        let listener = try NWListener(using: params, on: nwPort)
        let hostName = Host.current().localizedName ?? "Mac"
        let instanceName = "SessionPad (\(hostName))"
        var txt = NWTXTRecord()
        txt["v"] = String(SPProtocol.version)
        txt["name"] = String(sessionName.prefix(63))
        txt["caps"] = SPProtocol.defaultCapabilities.joined(separator: ",")

        listener.service = NWListener.Service(
            name: instanceName,
            type: SPProtocol.serviceType,
            domain: nil,
            txtRecord: txt
        )

        listener.newConnectionHandler = { [weak self] connection in
            self?.acceptConnection(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                os_log(.info, log: OSLog.default, "iOS WebSocket server ready on port %d", port)
            }
            if case .failed(let error) = state {
                os_log(.error, log: OSLog.default, "WebSocket listener failed: %{public}@", error.localizedDescription)
                _ = self
            }
        }

        listener.start(queue: queue)
        self.listener = listener
        advertisedPort = port
    }

    func updateSessionName(_ name: String) {
        // Bonjour TXT is set at start; session name also flows via welcome payload.
        _ = name
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            for (_, connection) in self.connections {
                connection.cancel()
            }
            self.connections.removeAll()
            self.connectedClientCount = 0
            self.listener?.cancel()
            self.listener = nil
        }
    }

    func send(to clientId: UUID, text: String) {
        queue.async { [weak self] in
            guard let self, let connection = self.connections[clientId] else { return }
            self.sendText(text, on: connection)
        }
    }

    func broadcast(text: String) {
        queue.async { [weak self] in
            guard let self else { return }
            for connection in self.connections.values {
                self.sendText(text, on: connection)
            }
        }
    }

    // MARK: - Private

    private func acceptConnection(_ connection: NWConnection) {
        let clientId = UUID()
        connections[clientId] = connection
        connectedClientCount = connections.count

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                DispatchQueue.main.async {
                    self.delegate?.iosWebSocketServer(self, clientDidConnect: clientId)
                }
                self.receiveLoop(clientId: clientId, connection: connection)
            case .failed, .cancelled:
                self.removeClient(clientId)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receiveLoop(clientId: UUID, connection: NWConnection) {
        connection.receiveMessage { [weak self] content, context, _, error in
            guard let self else { return }
            if error != nil {
                self.removeClient(clientId)
                return
            }

            if let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata,
               metadata.opcode == .text,
               let content,
               let text = String(data: content, encoding: .utf8) {
                DispatchQueue.main.async {
                    self.delegate?.iosWebSocketServer(self, client: clientId, didReceive: text)
                }
            }

            if self.connections[clientId] != nil {
                self.receiveLoop(clientId: clientId, connection: connection)
            }
        }
    }

    private func sendText(_ text: String, on connection: NWConnection) {
        guard let data = text.data(using: .utf8) else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "ws-text", metadata: [metadata])
        connection.send(
            content: data,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { error in
                if let error {
                    os_log(.error, log: self.log, "WebSocket send failed: %{public}@", error.localizedDescription)
                }
            }
        )
    }

    private func removeClient(_ clientId: UUID) {
        queue.async { [weak self] in
            guard let self else { return }
            self.connections[clientId]?.cancel()
            self.connections.removeValue(forKey: clientId)
            self.connectedClientCount = self.connections.count
            DispatchQueue.main.async {
                self.delegate?.iosWebSocketServer(self, clientDidDisconnect: clientId)
            }
        }
    }
}
