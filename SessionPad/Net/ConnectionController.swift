// ConnectionController.swift
// Single source of truth for discovery, WebSocket, handshake, resync, and reconnect.

import Foundation
import Network
import os.log

enum ConnectionPhase: Equatable {
    case idle
    case browsing
    case connecting
    case handshaking
    case synced
    case live
}

protocol ConnectionControllerDelegate: AnyObject {
    func connectionController(_ controller: ConnectionController, didUpdateState state: ConnectionState)
    func connectionController(_ controller: ConnectionController, didReceive message: WireMessage)
    func connectionController(_ controller: ConnectionController, didUpdateLatencyMs latency: Double)
    func connectionController(_ controller: ConnectionController, didUpdateDevices devices: [DiscoveredService], showPicker: Bool)
}

@MainActor
final class ConnectionController: ObservableObject {

    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var phase: ConnectionPhase = .idle
    @Published private(set) var latencyEstimate: String = "–"
    @Published private(set) var deviceName: String = "Ableton Live"
    @Published private(set) var discoveredDevices: [DiscoveredService] = []
    @Published private(set) var showDevicePicker = false

    weak var delegate: ConnectionControllerDelegate?

    private let log = OSLog(subsystem: "com.scharovsky.SessionPad", category: "Connection")
    private let discovery = SessionDiscovery()
    private let webSocket = WebSocketClient()

    private var heartbeatTimer: Timer?
    private var reconnectTimer: Timer?
    private var pendingService: DiscoveredService?
    private var lastSeq = 0
    private var snapshotRev = 0
    private var heartbeatIntervalMs = SPProtocol.heartbeatIntervalMs
    private var reconnectAttempt = 0
    private let reconnectDelays: [TimeInterval] = [0.25, 0.5, 1.0, 2.0, 4.0]
    private var isRunning = false
    private var pingSentAt: Date?
    private var latencySamples: [Double] = []
    private let maxLatencySamples = 10
    private var pendingCommands: [String: Date] = [:]
    private let commandTimeout: TimeInterval = 5.0
    private var discoveryTimeoutTimer: Timer?
    private let discoveryTimeout: TimeInterval = 15.0
    private(set) var showManualConnect = false
    private var usingManualEndpoint = false
    private var selectedService: DiscoveredService?
    private var userSelectedDevice = false
    private var awaitingSelection = false
    private var decisionTimer: Timer?
    private var decisionPending = false
    private let decisionDebounce: TimeInterval = 0.6

    init() {
        discovery.delegate = self
        webSocket.delegate = self
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        reconnectAttempt = 0
        userSelectedDevice = false
        selectedService = nil
        awaitingSelection = false
        discoveredDevices = []
        showDevicePicker = false
        cancelDecisionTimer()
        setPhase(.browsing)
        setConnectionState(.connecting)
        discovery.start()
        scheduleDiscoveryTimeout()
        notifyDevices()
    }

    func connectManually(host: String, port: UInt16 = SPBridge.iosWebSocketPort) {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let url = URL(string: "ws://\(trimmed):\(port)/") else {
            setConnectionState(.error("Invalid host or port"))
            return
        }
        usingManualEndpoint = true
        showManualConnect = false
        showDevicePicker = false
        userSelectedDevice = false
        selectedService = nil
        awaitingSelection = false
        cancelDecisionTimer()
        discoveryTimeoutTimer?.invalidate()
        reconnectTimer?.invalidate()
        pendingService = nil
        setPhase(.connecting)
        setConnectionState(.connecting)
        deviceName = trimmed
        webSocket.connect(url: url) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success:
                    self.setPhase(.handshaking)
                    await self.performHandshake()
                case .failure(let error):
                    os_log(.error, log: self.log, "Manual connect failed: %{public}@", error.localizedDescription)
                    self.setConnectionState(.error(error.localizedDescription))
                }
            }
        }
    }

    func selectDevice(_ service: DiscoveredService) {
        userSelectedDevice = true
        selectedService = service
        awaitingSelection = false
        showDevicePicker = false
        cancelDecisionTimer()
        discoveryTimeoutTimer?.invalidate()
        reconnectTimer?.invalidate()
        showManualConnect = false
        notifyDevices()
        connect(to: service)
    }

    func stop() {
        isRunning = false
        invalidateTimers()
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        cancelDecisionTimer()
        webSocket.disconnect()
        discovery.stop()
        discoveryTimeoutTimer?.invalidate()
        discoveryTimeoutTimer = nil
        setPhase(.idle)
        setConnectionState(.disconnected)
        pendingService = nil
        selectedService = nil
        pendingCommands.removeAll()
        showManualConnect = false
        showDevicePicker = false
        discoveredDevices = []
        userSelectedDevice = false
        awaitingSelection = false
        usingManualEndpoint = false
        notifyDevices()
    }

    func sendCommand(name: String, data: [String: JSONValue]) async throws -> String {
        let id = UUID().uuidString
        let text = try ProtocolCodec.command(name: name, data: data, id: id)
        pendingCommands[id] = Date()
        try await send(text: text)
        return id
    }

    func send(text: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            webSocket.send(text: text) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func requestFullSync() {
        Task {
            do {
                let text = try ProtocolCodec.getState()
                try await send(text: text)
            } catch {
                os_log(.error, log: log, "getState failed: %{public}@", error.localizedDescription)
            }
        }
    }

    // MARK: - Private state machine

    private func setPhase(_ newPhase: ConnectionPhase) {
        phase = newPhase
    }

    private func setConnectionState(_ state: ConnectionState) {
        connectionState = state
        delegate?.connectionController(self, didUpdateState: state)
    }

    private func connect(to service: DiscoveredService) {
        if pendingService == service {
            switch phase {
            case .connecting, .handshaking, .synced, .live:
                os_log(.info, log: log, "Skipping duplicate connect to %{public}@ (phase=%{public}@)", service.name, String(describing: phase))
                return
            default:
                break
            }
        }

        os_log(.info, log: log, "Connecting to %{public}@", service.displayHostName)
        pendingService = service
        setPhase(.connecting)
        setConnectionState(.connecting)
        if let sessionName = service.sessionName, !sessionName.isEmpty {
            deviceName = sessionName
        } else {
            deviceName = service.name
        }
        webSocket.connect(to: service.endpoint) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success:
                    os_log(.info, log: self.log, "WebSocket open succeeded for %{public}@", service.displayHostName)
                    self.setPhase(.handshaking)
                    await self.performHandshake()
                case .failure(let error):
                    os_log(.error, log: self.log, "Connect failed for %{public}@: %{public}@", service.displayHostName, error.localizedDescription)
                    self.handleDisconnect()
                }
            }
        }
    }

    private func performHandshake() async {
        do {
            let hello = try ProtocolCodec.hello(appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            try await send(text: hello)
            let subscribe = try ProtocolCodec.subscribe()
            try await send(text: subscribe)
        } catch {
            os_log(.error, log: log, "Handshake send failed: %{public}@", error.localizedDescription)
            handleDisconnect()
        }
    }

    private func handleMessage(_ message: WireMessage) {
        delegate?.connectionController(self, didReceive: message)

        switch message.t {
        case MessageType.welcome:
            handleWelcome(message)
        case MessageType.stateFull:
            handleStateFull(message)
        case MessageType.heartbeat:
            handleHeartbeat(message)
        case MessageType.ack:
            handleAck(message)
        case MessageType.error:
            handleError(message)
        case MessageType.deltaClip, MessageType.deltaTrack, MessageType.deltaScene, MessageType.deltaTransport, MessageType.deltaPlaypos:
            handleDelta(message)
        default:
            break
        }
    }

    private func handleWelcome(_ message: WireMessage) {
        if let welcome = try? ProtocolCodec.decodePayload(WelcomePayload.self, from: message) {
            heartbeatIntervalMs = welcome.heartbeatIntervalMs
            snapshotRev = welcome.snapshotRev
            if !welcome.sessionName.isEmpty {
                deviceName = welcome.sessionName
            }
        }
        setPhase(.synced)
        setConnectionState(.connected(deviceName: deviceName))
        reconnectAttempt = 0
        resetHeartbeatTimer()
    }

    private func handleStateFull(_ message: WireMessage) {
        if let payload = try? ProtocolCodec.decodePayload(FullStatePayload.self, from: message) {
            snapshotRev = payload.rev
            lastSeq = message.seq ?? lastSeq
        }
        setPhase(.live)
        setConnectionState(.connected(deviceName: deviceName))
        resetHeartbeatTimer()
    }

    private func handleDelta(_ message: WireMessage) {
        if let seq = message.seq {
            if seq > lastSeq + 1 && lastSeq > 0 {
                requestFullSync()
            }
            lastSeq = max(lastSeq, seq)
        }
        setPhase(.live)
        setConnectionState(.connected(deviceName: deviceName))
        resetHeartbeatTimer()
    }

    private func handleHeartbeat(_ message: WireMessage) {
        if let sent = pingSentAt {
            let rtt = Date().timeIntervalSince(sent) * 1000.0
            pingSentAt = nil
            latencySamples.append(rtt)
            if latencySamples.count > maxLatencySamples {
                latencySamples.removeFirst()
            }
            let avg = latencySamples.reduce(0, +) / Double(latencySamples.count)
            latencyEstimate = String(format: "%.0f ms", avg)
            delegate?.connectionController(self, didUpdateLatencyMs: avg)
        }
        resetHeartbeatTimer()
    }

    private func handleAck(_ message: WireMessage) {
        if let id = message.id {
            pendingCommands.removeValue(forKey: id)
        }
        resetHeartbeatTimer()
    }

    private func handleError(_ message: WireMessage) {
        let text = message.payload?.objectValue?["message"]?.stringValue ?? "Protocol error"
        setConnectionState(.error(text))
    }

    private func handleDisconnect() {
        invalidateTimers()
        webSocket.disconnect()
        lastSeq = 0
        latencySamples.removeAll()
        latencyEstimate = "–"
        pingSentAt = nil
        if isRunning {
            cancelDecisionTimer()
            setPhase(.browsing)
            setConnectionState(.connecting)
            if usingManualEndpoint {
                scheduleReconnectIfNeeded(immediate: false)
            } else {
                scheduleDiscoveryTimeout()
                scheduleReconnectIfNeeded(immediate: false)
            }
        } else {
            setPhase(.idle)
            setConnectionState(.disconnected)
        }
    }

    private func resetHeartbeatTimer() {
        heartbeatTimer?.invalidate()
        let timeout = max(TimeInterval(heartbeatIntervalMs) / 1000.0 * 3.0, 6.0)
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleDisconnect()
            }
        }
        sendHeartbeatPing()
    }

    private func sendHeartbeatPing() {
        Task {
            do {
                pingSentAt = Date()
                let text = try ProtocolCodec.heartbeat()
                try await send(text: text)
            } catch {
                os_log(.error, log: log, "Heartbeat send failed")
            }
        }
    }

    private func invalidateTimers() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func scheduleDiscoveryTimeout() {
        discoveryTimeoutTimer?.invalidate()
        guard isRunning, !usingManualEndpoint else { return }
        discoveryTimeoutTimer = Timer.scheduledTimer(withTimeInterval: discoveryTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning, !self.usingManualEndpoint else { return }
                if case .connected = self.connectionState { return }
                self.showManualConnect = true
            }
        }
    }

    private func scheduleReconnectIfNeeded(immediate: Bool) {
        reconnectTimer?.invalidate()
        guard isRunning else { return }

        if usingManualEndpoint {
            return
        }

        if userSelectedDevice, let service = selectedService ?? pendingService {
            let delay = immediate ? 0.0 : reconnectDelays[min(reconnectAttempt, reconnectDelays.count - 1)]
            reconnectAttempt += 1
            reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isRunning else { return }
                    self.connect(to: service)
                }
            }
            return
        }

        refreshDiscoveredDevices()
        if discoveredDevices.count >= 2 {
            awaitingSelection = true
            showDevicePicker = true
            notifyDevices()
            setPhase(.browsing)
            setConnectionState(.connecting)
            return
        }

        if discoveredDevices.count == 1 {
            evaluateAutoConnectOrPicker()
            return
        }

        setPhase(.browsing)
        setConnectionState(.connecting)
    }

    private func refreshDiscoveredDevices() {
        discoveredDevices = discovery.snapshot()
    }

    private func notifyDevices() {
        delegate?.connectionController(self, didUpdateDevices: discoveredDevices, showPicker: showDevicePicker)
    }

    private func cancelDecisionTimer() {
        decisionTimer?.invalidate()
        decisionTimer = nil
        decisionPending = false
    }

    private func scheduleDecisionTimerIfNeeded() {
        guard !decisionPending else { return }

        decisionPending = true
        os_log(.info, log: log, "Decision timer scheduled (%.1fs debounce)", decisionDebounce)

        decisionTimer?.invalidate()
        decisionTimer = Timer.scheduledTimer(withTimeInterval: decisionDebounce, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.fireDecisionTimer()
            }
        }
    }

    private func fireDecisionTimer() {
        decisionPending = false
        decisionTimer = nil

        guard isRunning, !usingManualEndpoint else { return }
        if case .connected = connectionState { return }
        if userSelectedDevice { return }

        let devices = discovery.snapshot()
        discoveredDevices = devices
        let count = devices.count

        os_log(.info, log: log, "Decision timer fired: %d device(s) visible", count)

        if count >= 2 {
            awaitingSelection = true
            showDevicePicker = true
            notifyDevices()
            setPhase(.browsing)
            setConnectionState(.connecting)
            return
        }

        if count == 1, let only = devices.first {
            showDevicePicker = false
            awaitingSelection = false
            notifyDevices()
            connect(to: only)
            return
        }

        showDevicePicker = false
        awaitingSelection = false
        notifyDevices()
        setPhase(.browsing)
        setConnectionState(.connecting)
    }

    private func evaluateAutoConnectOrPicker() {
        guard isRunning, !usingManualEndpoint else { return }
        if case .connected = connectionState { return }

        if pendingService != nil, phase == .connecting || phase == .handshaking {
            os_log(.info, log: log, "Skipping evaluate — connect in progress to %{public}@", pendingService?.name ?? "?")
            return
        }

        if userSelectedDevice, let service = selectedService {
            cancelDecisionTimer()
            showDevicePicker = false
            awaitingSelection = false
            notifyDevices()
            connect(to: service)
            return
        }

        refreshDiscoveredDevices()
        let count = discoveredDevices.count

        if count == 0 {
            showDevicePicker = false
            awaitingSelection = false
            notifyDevices()
            setPhase(.browsing)
            setConnectionState(.connecting)
            return
        }

        if count >= 2 {
            cancelDecisionTimer()
            awaitingSelection = true
            showDevicePicker = true
            notifyDevices()
            setPhase(.browsing)
            setConnectionState(.connecting)
            return
        }

        showDevicePicker = false
        awaitingSelection = false
        notifyDevices()
        scheduleDecisionTimerIfNeeded()
    }

    func reconcilePendingCommands() {
        let now = Date()
        for (id, sent) in pendingCommands {
            if now.timeIntervalSince(sent) > commandTimeout {
                pendingCommands.removeValue(forKey: id)
                requestFullSync()
                break
            }
        }
    }
}

// MARK: - SessionDiscoveryDelegate

extension ConnectionController: SessionDiscoveryDelegate {
    nonisolated func discovery(_ discovery: SessionDiscovery, didFind service: DiscoveredService) {
        Task { @MainActor [weak self] in
            guard let self, self.isRunning else { return }
            self.refreshDiscoveredDevices()
            os_log(.info, log: self.log, "didFind %{public}@ — %d device(s) visible", service.displayHostName, self.discoveredDevices.count)
            if case .connected = self.connectionState { return }
            if self.usingManualEndpoint { return }
            if self.phase == .browsing || self.phase == .connecting {
                self.discoveryTimeoutTimer?.invalidate()
                self.showManualConnect = false
                self.evaluateAutoConnectOrPicker()
            }
        }
    }

    nonisolated func discovery(_ discovery: SessionDiscovery, didLose service: DiscoveredService) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.refreshDiscoveredDevices()
            os_log(.info, log: self.log, "didLose %{public}@ — %d device(s) visible", service.displayHostName, self.discoveredDevices.count)

            if self.pendingService == service {
                os_log(.info, log: self.log, "Lost active target %{public}@ — disconnecting", service.displayHostName)
                self.handleDisconnect()
                return
            }

            if case .connected = self.connectionState { return }
            guard self.isRunning else { return }
            if self.usingManualEndpoint { return }
            if self.phase == .browsing || self.phase == .connecting {
                self.evaluateAutoConnectOrPicker()
            }
        }
    }

    nonisolated func discoveryStateChanged(_ discovery: SessionDiscovery, isSearching: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.isRunning else { return }
            if isSearching && self.phase == .idle {
                self.setPhase(.browsing)
            }
        }
    }
}

// MARK: - WebSocketClientDelegate

extension ConnectionController: WebSocketClientDelegate {
    nonisolated func webSocketClient(_ client: WebSocketClient, didChangeState state: WebSocketClientState) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if state == .disconnected && self.isRunning && self.phase != .browsing {
                self.handleDisconnect()
            }
        }
    }

    nonisolated func webSocketClient(_ client: WebSocketClient, didReceive text: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let message = try? ProtocolCodec.decode(text) else { return }
            self.handleMessage(message)
        }
    }

    nonisolated func webSocketClient(_ client: WebSocketClient, didFail error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            os_log(.error, log: self.log, "WebSocket error: %{public}@", error.localizedDescription)
            self.handleDisconnect()
        }
    }
}
