// LiveLinkServer.swift
// Localhost TCP server for the Ableton Remote Script (newline-framed JSON).

import Foundation
import Network
import os.log

protocol LiveLinkServerDelegate: AnyObject {
    func liveLinkServerDidConnect(_ server: LiveLinkServer)
    func liveLinkServerDidDisconnect(_ server: LiveLinkServer)
    func liveLinkServer(_ server: LiveLinkServer, didReceive text: String)
}

final class LiveLinkServer: @unchecked Sendable {

    weak var delegate: LiveLinkServerDelegate?

    private let log = OSLog(subsystem: "com.scharovsky.SessionPadBridge", category: "LiveLink")
    private let queue = DispatchQueue(label: "com.scharovsky.SessionPadBridge.livelink")
    private var listener: NWListener?
    private var connection: NWConnection?
    private var receiveBuffer = Data()

    private(set) var isLiveConnected = false

    func start(port: UInt16 = SPBridge.liveLinkPort) throws {
        let params = NWParameters.tcp
        params.acceptLocalOnly = true
        params.allowLocalEndpointReuse = true

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw BridgeError.invalidPort
        }

        let listener = try NWListener(using: params, on: nwPort)
        listener.newConnectionHandler = { [weak self] connection in
            self?.acceptConnection(connection)
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                os_log(.error, log: OSLog.default, "Live link listener failed: %{public}@", error.localizedDescription)
            }
        }
        listener.start(queue: queue)
        self.listener = listener
        os_log(.info, log: log, "Live link listening on localhost:%d", port)
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.connection?.cancel()
            self.connection = nil
            self.listener?.cancel()
            self.listener = nil
            self.receiveBuffer.removeAll()
            self.setConnected(false)
        }
    }

    func send(text: String) {
        queue.async { [weak self] in
            guard let self, let connection = self.connection, self.isLiveConnected else { return }
            guard let data = (text + "\n").data(using: .utf8) else { return }
            connection.send(
                content: data,
                completion: .contentProcessed { error in
                    if let error {
                        os_log(.error, log: self.log, "Live link send failed: %{public}@", error.localizedDescription)
                    }
                }
            )
        }
    }

    // MARK: - Private

    private func acceptConnection(_ newConnection: NWConnection) {
        if let existing = connection {
            existing.cancel()
        }
        connection = newConnection
        receiveBuffer.removeAll()

        newConnection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.setConnected(true)
                DispatchQueue.main.async {
                    self.delegate?.liveLinkServerDidConnect(self)
                }
                self.receiveLoop()
            case .failed, .cancelled:
                self.handleDisconnect()
            default:
                break
            }
        }
        newConnection.start(queue: queue)
    }

    private func receiveLoop() {
        guard let connection else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.receiveBuffer.append(data)
                self.processBuffer()
            }
            if isComplete || error != nil {
                self.handleDisconnect()
                return
            }
            self.receiveLoop()
        }
    }

    private func processBuffer() {
        while let newlineIndex = receiveBuffer.firstIndex(of: 0x0A) {
            let lineData = receiveBuffer[..<newlineIndex]
            receiveBuffer.removeSubrange(...newlineIndex)
            if !receiveBuffer.isEmpty, receiveBuffer.first == 0x0A {
                receiveBuffer.removeFirst()
            }
            guard let text = String(data: lineData, encoding: .utf8), !text.isEmpty else { continue }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.liveLinkServer(self, didReceive: text)
            }
        }
    }

    private func handleDisconnect() {
        let wasConnected = isLiveConnected
        connection?.cancel()
        connection = nil
        receiveBuffer.removeAll()
        setConnected(false)
        if wasConnected {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.liveLinkServerDidDisconnect(self)
            }
        }
    }

    private func setConnected(_ connected: Bool) {
        isLiveConnected = connected
    }
}

enum BridgeError: Error, LocalizedError {
    case invalidPort
    case startFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPort: return "Invalid port"
        case .startFailed(let reason): return reason
        }
    }
}
