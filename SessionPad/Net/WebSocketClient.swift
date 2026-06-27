// WebSocketClient.swift
// URLSessionWebSocketTask wrapper with send/receive, ping, and reconnect hooks.

import Foundation
import Network
import os.log
import Darwin

enum WebSocketClientState: Equatable {
    case disconnected
    case connecting
    case connected
}

protocol WebSocketClientDelegate: AnyObject {
    func webSocketClient(_ client: WebSocketClient, didChangeState state: WebSocketClientState)
    func webSocketClient(_ client: WebSocketClient, didReceive text: String)
    func webSocketClient(_ client: WebSocketClient, didFail error: Error)
}

final class WebSocketClient: @unchecked Sendable {

    weak var delegate: WebSocketClientDelegate?

    private let log = OSLog(subsystem: "com.scharovsky.SessionPad", category: "WebSocket")
    private let queue = DispatchQueue(label: "com.scharovsky.SessionPad.websocket")
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var resolveConnection: NWConnection?
    private var bonjourResolver: BonjourResolver?
    private(set) var state: WebSocketClientState = .disconnected
    private var receiveLoopActive = false
    private var pingTimer: DispatchSourceTimer?

    func connect(to endpoint: NWEndpoint, completion: @escaping (Result<URL, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            self.disconnectInternal()
            self.setState(.connecting)

            // Bonjour .service endpoints: resolve host/port via NetService (mDNS only).
            // Do NOT open a raw TCP connection to the WebSocket port — the Python bridge
            // treats EOF as 400 Bad Request and iOS would fail to connect.
            if case .service(let name, let type, let domain, _) = endpoint {
                let resolver = BonjourResolver { [weak self] result in
                    guard let self else { return }
                    self.bonjourResolver = nil
                    self.queue.async {
                        switch result {
                        case .success(let url):
                            self.openWebSocket(url: url, completion: completion)
                        case .failure(let error):
                            os_log(.info, log: self.log, "NetService resolve failed (%{public}@), falling back to NWConnection", error.localizedDescription)
                            self.resolveViaNWConnection(to: endpoint, completion: completion)
                        }
                    }
                }
                self.bonjourResolver = resolver
                resolver.resolve(name: name, type: type, domain: domain)
                return
            }

            if case .hostPort(let host, let port) = endpoint {
                let hostString = self.hostString(from: host)
                guard let url = URL(string: "ws://\(hostString):\(port.rawValue)/") else {
                    DispatchQueue.main.async { completion(.failure(WebSocketError.invalidURL)) }
                    return
                }
                self.openWebSocket(url: url, completion: completion)
                return
            }

            DispatchQueue.main.async { completion(.failure(WebSocketError.invalidEndpoint)) }
        }
    }

    func connect(url: URL, completion: @escaping (Result<URL, Error>) -> Void = { _ in }) {
        queue.async { [weak self] in
            self?.disconnectInternal()
            self?.setState(.connecting)
            self?.openWebSocket(url: url, completion: completion)
        }
    }

    func disconnect() {
        queue.async { [weak self] in
            self?.disconnectInternal()
        }
    }

    func send(text: String, completion: ((Error?) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self, let task = self.task, self.state == .connected else {
                completion?(WebSocketError.notConnected)
                return
            }
            task.send(.string(text)) { error in
                completion?(error)
            }
        }
    }

    func sendPing() {
        queue.async { [weak self] in
            self?.task?.sendPing { error in
                if let error {
                    os_log(.error, log: OSLog.default, "WebSocket ping failed: %{public}@", error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Private

    private func hostString(from host: NWEndpoint.Host) -> String {
        switch host {
        case .ipv4(let addr):
            return "\(addr)"
        case .ipv6(let addr):
            return "[\(addr)]"
        case .name(let name, _):
            return name
        @unknown default:
            return "127.0.0.1"
        }
    }

    /// Fallback: resolve Bonjour via NWConnection (TCP probe). Works with the Mac Swift bridge.
    private func resolveViaNWConnection(to endpoint: NWEndpoint, completion: @escaping (Result<URL, Error>) -> Void) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        resolveConnection = connection
        connection.stateUpdateHandler = { [weak self] connState in
            guard let self else { return }
            switch connState {
            case .ready:
                guard let path = connection.currentPath,
                      case .hostPort(let host, let port) = path.remoteEndpoint else {
                    connection.cancel()
                    self.resolveConnection = nil
                    DispatchQueue.main.async { completion(.failure(WebSocketError.invalidEndpoint)) }
                    return
                }
                let hostString = self.hostString(from: host)
                connection.cancel()
                self.resolveConnection = nil
                guard let url = URL(string: "ws://\(hostString):\(port.rawValue)/") else {
                    DispatchQueue.main.async { completion(.failure(WebSocketError.invalidURL)) }
                    return
                }
                self.openWebSocket(url: url, completion: completion)
            case .failed(let error):
                connection.cancel()
                self.resolveConnection = nil
                DispatchQueue.main.async { completion(.failure(error)) }
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func openWebSocket(url: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = true
        let session = URLSession(configuration: config)
        self.session = session
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        setState(.connected)
        startReceiveLoop()
        startPingTimer()
        os_log(.info, log: log, "WebSocket connected to %{public}@", url.absoluteString)
        DispatchQueue.main.async {
            completion(.success(url))
        }
    }

    private func disconnectInternal() {
        stopPingTimer()
        receiveLoopActive = false
        resolveConnection?.cancel()
        resolveConnection = nil
        bonjourResolver?.cancel()
        bonjourResolver = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        setState(.disconnected)
    }

    private func setState(_ newState: WebSocketClientState) {
        guard state != newState else { return }
        state = newState
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.webSocketClient(self, didChangeState: newState)
        }
    }

    private func startReceiveLoop() {
        receiveLoopActive = true
        receiveNext()
    }

    private func receiveNext() {
        guard receiveLoopActive, let task else { return }
        task.receive { [weak self] result in
            guard let self, self.receiveLoopActive else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    DispatchQueue.main.async {
                        self.delegate?.webSocketClient(self, didReceive: text)
                    }
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        DispatchQueue.main.async {
                            self.delegate?.webSocketClient(self, didReceive: text)
                        }
                    }
                @unknown default:
                    break
                }
                self.receiveNext()
            case .failure(let error):
                self.receiveLoopActive = false
                self.setState(.disconnected)
                DispatchQueue.main.async {
                    self.delegate?.webSocketClient(self, didFail: error)
                }
            }
        }
    }

    private func startPingTimer() {
        stopPingTimer()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 15, repeating: 15)
        timer.setEventHandler { [weak self] in
            self?.sendPing()
        }
        timer.resume()
        pingTimer = timer
    }

    private func stopPingTimer() {
        pingTimer?.cancel()
        pingTimer = nil
    }
}

enum WebSocketError: Error, LocalizedError {
    case notConnected
    case invalidURL
    case invalidEndpoint
    case bonjourResolveFailed

    var errorDescription: String? {
        switch self {
        case .notConnected: return "WebSocket not connected"
        case .invalidURL: return "Invalid WebSocket URL"
        case .invalidEndpoint: return "Invalid network endpoint"
        case .bonjourResolveFailed: return "Bonjour service resolution failed"
        }
    }
}

// MARK: - BonjourResolver

/// Resolves a Bonjour service to host/port via mDNS without opening TCP to the target port.
private final class BonjourResolver: NSObject, NetServiceDelegate {
    private var netService: NetService?
    private let completion: (Result<URL, Error>) -> Void
    private var finished = false

    init(completion: @escaping (Result<URL, Error>) -> Void) {
        self.completion = completion
    }

    func resolve(name: String, type: String, domain: String) {
        var serviceDomain = domain.isEmpty ? "local." : domain
        if !serviceDomain.hasSuffix(".") {
            serviceDomain += "."
        }
        var serviceType = type
        if !serviceType.hasSuffix(".") {
            serviceType += "."
        }

        // NetService must be created, scheduled, and resolved on a thread with a
        // live run loop. resolve() is called from the WebSocket background queue,
        // so hop to the main run loop or the delegate callbacks never fire.
        let startOnMain = { [weak self] in
            guard let self else { return }
            let service = NetService(domain: serviceDomain, type: serviceType, name: name)
            service.delegate = self
            self.netService = service
            service.schedule(in: .main, forMode: .common)
            service.resolve(withTimeout: 5)
        }
        if Thread.isMainThread {
            startOnMain()
        } else {
            DispatchQueue.main.async(execute: startOnMain)
        }
    }

    func cancel() {
        guard let service = netService else { return }
        netService = nil
        let stopOnMain = {
            service.stop()
            service.remove(from: .main, forMode: .common)
            service.delegate = nil
        }
        if Thread.isMainThread {
            stopOnMain()
        } else {
            DispatchQueue.main.async(execute: stopOnMain)
        }
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard sender.port > 0 else {
            finish(.failure(WebSocketError.bonjourResolveFailed))
            return
        }

        let host = Self.ipv4Host(from: sender.addresses) ?? Self.normalizedHostName(sender.hostName)
        guard let host,
              let url = URL(string: "ws://\(host):\(sender.port)/") else {
            finish(.failure(WebSocketError.invalidURL))
            return
        }
        finish(.success(url))
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        _ = sender
        _ = errorDict
        finish(.failure(WebSocketError.bonjourResolveFailed))
    }

    private func finish(_ result: Result<URL, Error>) {
        guard !finished else { return }
        finished = true
        cancel()
        completion(result)
    }

    private static func normalizedHostName(_ hostName: String?) -> String? {
        guard var host = hostName, !host.isEmpty else { return nil }
        if host.hasSuffix(".") {
            host.removeLast()
        }
        return host
    }

    private static func ipv4Host(from addresses: [Data]?) -> String? {
        guard let addresses else { return nil }
        for data in addresses {
            let host: String? = data.withUnsafeBytes { pointer in
                guard let base = pointer.baseAddress else { return nil }
                let family = base.assumingMemoryBound(to: sockaddr.self).pointee.sa_family
                guard family == sa_family_t(AF_INET) else { return nil }
                var addr = base.assumingMemoryBound(to: sockaddr_in.self).pointee
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                guard inet_ntop(AF_INET, &addr.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
                    return nil
                }
                return String(cString: buffer)
            }
            if let host { return host }
        }
        return nil
    }
}
