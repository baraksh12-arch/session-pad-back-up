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

    @Published private(set) var showManualConnect = false

    private let connection = ConnectionController()
    private let log = OSLog(subsystem: "com.scharovsky.SessionPad", category: "Bridge")
    private var commandReconcileTimer: Timer?

    init() {
        connection.delegate = self
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

    func launchClip(trackIndex: Int, sceneIndex: Int) {
        let data: [String: JSONValue] = [
            "track": .int(trackIndex),
            "scene": .int(sceneIndex),
        ]
        sendCommand(
            name: "launchClip",
            data: data,
            optimistic: { self.session.setClipState(.queued, trackIndex: trackIndex, sceneIndex: sceneIndex) }
        )
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

    func setTempo(_ bpm: Double) {
        sendCommand(name: "setTempo", data: ["bpm": .double(bpm)]) {
            self.transport.bpm = bpm
        }
    }

    func connectManually(host: String, port: UInt16 = SPBridge.iosWebSocketPort) {
        connection.connectManually(host: host, port: port)
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
}
