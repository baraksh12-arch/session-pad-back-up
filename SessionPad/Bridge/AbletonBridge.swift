// AbletonBridge.swift
// Main state synchronization engine between ConnectionController and SwiftUI.

import Foundation
import Combine
import os.log

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected(deviceName: String)
    case error(String)
}

@MainActor
final class AbletonBridge: ObservableObject {

    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var session: LiveSession = LiveSession()
    @Published private(set) var transport: TransportState = TransportState()
    @Published private(set) var latencyEstimate: String = "–"
    let progress = ClipProgressStore()

    @Published private(set) var showManualConnect = false
    @Published private(set) var discoveredDevices: [DiscoveredService] = []
    @Published private(set) var showDevicePicker = false

    private let connection = ConnectionController()
    private let log = OSLog(subsystem: "com.scharovsky.SessionPad", category: "Bridge")
    private var commandReconcileTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init() {
        connection.delegate = self
        session.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)
        progress.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)
    }

    func start() {
        connectionState = .connecting
        connection.start()
        startCommandReconcileTimer()
    }

    func stop() {
        commandReconcileTimer?.invalidate()
        commandReconcileTimer = nil
        connection.stop()
        connectionState = .disconnected
    }

    func requestFullSync() {
        connection.requestFullSync()
    }

    // MARK: - Outgoing Commands

    func launchClip(trackIndex: Int, sceneIndex: Int, isEmpty: Bool = false, isArmed: Bool = false) {
        let data: [String: JSONValue] = [
            "track": .int(trackIndex),
            "scene": .int(sceneIndex),
        ]
        let optimistic: (() -> Void)? = {
            if isEmpty {
                if isArmed {
                    return { self.session.setClipState(.recQueued, trackIndex: trackIndex, sceneIndex: sceneIndex) }
                }
                return { self.session.stopClipsOnTrack(trackIndex: trackIndex) }
            }
            return { self.session.setClipState(.queued, trackIndex: trackIndex, sceneIndex: sceneIndex) }
        }()
        sendCommand(name: "launchClip", data: data, optimistic: optimistic)
    }

    func deleteClip(trackIndex: Int, sceneIndex: Int) {
        let data: [String: JSONValue] = [
            "track": .int(trackIndex),
            "scene": .int(sceneIndex),
        ]
        sendCommand(name: "deleteClip", data: data) {
            self.session.updateClip(
                trackIndex: trackIndex,
                sceneIndex: sceneIndex,
                state: .empty,
                colorIndex: 0,
                name: ""
            )
        }
    }

    func launchScene(sceneIndex: Int) {
        sendCommand(name: "launchScene", data: ["scene": .int(sceneIndex)])
    }

    func stopTrack(trackIndex: Int) {
        sendCommand(name: "stopTrack", data: ["track": .int(trackIndex)])
    }

    func stopAll() {
        sendCommand(name: "stopAll", data: [:])
    }

    func armTrack(trackIndex: Int, toggle: Bool = true) {
        sendCommand(name: "armTrack", data: ["track": .int(trackIndex), "toggle": .bool(toggle)])
    }

    func muteTrack(trackIndex: Int, toggle: Bool = true) {
        sendCommand(name: "muteTrack", data: ["track": .int(trackIndex), "toggle": .bool(toggle)])
    }

    func soloTrack(trackIndex: Int, toggle: Bool = true) {
        sendCommand(name: "soloTrack", data: ["track": .int(trackIndex), "toggle": .bool(toggle)])
    }

    func selectTrack(trackIndex: Int) {
        sendCommand(name: "selectTrack", data: ["track": .int(trackIndex)])
    }

    func play() {
        sendCommand(name: "transport", data: ["action": .string("play")]) {
            self.transport.isPlaying = true
        }
    }

    func stopTransportPlayback() {
        sendCommand(name: "transport", data: ["action": .string("stop")]) {
            self.transport.isPlaying = false
        }
    }

    func toggleRecord() {
        sendCommand(name: "transport", data: ["action": .string("record")])
    }

    func toggleMetronome() {
        sendCommand(name: "transport", data: ["action": .string("metronome")])
    }

    func toggleOverdub() {
        sendCommand(name: "transport", data: ["action": .string("overdub")])
    }

    func setTempo(_ bpm: Double) {
        sendCommand(name: "setTempo", data: ["bpm": .double(bpm)]) {
            self.transport.bpm = bpm
        }
    }

    func connectManually(host: String, port: UInt16 = SPBridge.iosWebSocketPort) {
        connection.connectManually(host: host, port: port)
    }

    func selectDevice(_ service: DiscoveredService) {
        connection.selectDevice(service)
    }

    // MARK: - Private

    private func sendCommand(
        name: String,
        data: [String: JSONValue],
        optimistic: (() -> Void)? = nil
    ) {
        optimistic?()
        Task {
            do {
                _ = try await connection.sendCommand(name: name, data: data)
            } catch {
                os_log(.error, log: log, "Command %{public}@ failed: %{public}@", name, error.localizedDescription)
                connection.requestFullSync()
            }
        }
    }

    private func startCommandReconcileTimer() {
        commandReconcileTimer?.invalidate()
        commandReconcileTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.connection.reconcilePendingCommands()
            }
        }
    }

    private func applyFullState(_ payload: FullStatePayload) {
        progress.clearAll()
        session.reset(trackCount: payload.tracks, sceneCount: payload.scenes)
        for track in payload.trackHeaders {
            session.updateTrack(
                trackIndex: track.track,
                isMuted: track.muted,
                isSolo: track.solo,
                isArmed: track.armed,
                colorIndex: track.color,
                name: track.name
            )
        }
        for scene in payload.scenes_meta {
            session.updateScene(sceneIndex: scene.scene, colorIndex: scene.color, name: scene.name)
        }
        for clip in payload.clips {
            session.updateClip(
                trackIndex: clip.track,
                sceneIndex: clip.scene,
                state: clip.state,
                colorIndex: clip.color,
                name: clip.name
            )
        }
        applyTransport(payload.transport)
    }

    private func applyTransport(_ delta: TransportDelta) {
        transport.isPlaying = delta.playing
        transport.isRecording = delta.recording
        transport.metronomeOn = delta.metronome
        transport.overdubOn = delta.overdub
        transport.bpm = delta.bpm
    }

    private func processMessage(_ message: WireMessage) {
        switch message.t {
        case MessageType.stateFull:
            if let payload = try? ProtocolCodec.decodePayload(FullStatePayload.self, from: message) {
                applyFullState(payload)
            }
        case MessageType.deltaClip:
            if let clip = try? ProtocolCodec.decodePayload(ClipDelta.self, from: message) {
                session.updateClip(
                    trackIndex: clip.track,
                    sceneIndex: clip.scene,
                    state: clip.state,
                    colorIndex: clip.color,
                    name: clip.name
                )
                if clip.state == .stopped || clip.state == .empty || clip.state == .recording {
                    progress.clear(trackIndex: clip.track, sceneIndex: clip.scene)
                }
            }
        case MessageType.deltaPlaypos:
            if let payload = try? ProtocolCodec.decodePayload(PlayPosDelta.self, from: message) {
                for clip in payload.clips {
                    progress.update(
                        trackIndex: clip.track,
                        sceneIndex: clip.scene,
                        fraction: clip.p,
                        loopBeats: clip.lb,
                        bpm: transport.bpm,
                        isTransportPlaying: transport.isPlaying
                    )
                }
            }
        case MessageType.deltaTrack:
            if let track = try? ProtocolCodec.decodePayload(TrackDelta.self, from: message) {
                session.updateTrack(
                    trackIndex: track.track,
                    isMuted: track.muted,
                    isSolo: track.solo,
                    isArmed: track.armed,
                    colorIndex: track.color,
                    name: track.name
                )
            }
        case MessageType.deltaScene:
            if let scene = try? ProtocolCodec.decodePayload(SceneDelta.self, from: message) {
                session.updateScene(sceneIndex: scene.scene, colorIndex: scene.color, name: scene.name)
            }
        case MessageType.deltaTransport:
            if let t = try? ProtocolCodec.decodePayload(TransportDelta.self, from: message) {
                applyTransport(t)
            }
        default:
            break
        }
    }
}

// MARK: - ConnectionControllerDelegate

extension AbletonBridge: ConnectionControllerDelegate {
    func connectionController(_ controller: ConnectionController, didUpdateState state: ConnectionState) {
        connectionState = state
        latencyEstimate = controller.latencyEstimate
        showManualConnect = controller.showManualConnect
    }

    func connectionController(_ controller: ConnectionController, didReceive message: WireMessage) {
        processMessage(message)
    }

    func connectionController(_ controller: ConnectionController, didUpdateLatencyMs latency: Double) {
        latencyEstimate = String(format: "%.0f ms", latency)
    }

    func connectionController(_ controller: ConnectionController, didUpdateDevices devices: [DiscoveredService], showPicker: Bool) {
        discoveredDevices = devices
        showDevicePicker = showPicker
    }
}
