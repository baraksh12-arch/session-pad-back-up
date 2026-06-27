// SessionViewModel.swift
// SessionPad — Observable view model for the session grid.
//
// Mediates between AbletonBridge (the hardware/network layer)
// and the SwiftUI view hierarchy.

import SwiftUI
import Combine

// MARK: - Performance Mode

enum PerformanceMode {
    case normal       // Standard mode
    case performance  // Stage mode — large targets, no accidentals
    case locked       // Lock mode — no launches possible
}

// MARK: - SessionViewModel

@MainActor
final class SessionViewModel: ObservableObject {

    // MARK: Published UI State

    @Published var performanceMode: PerformanceMode = .normal
    @Published var isLocked = false
    @Published var confirmationPending: ConfirmationAction? = nil
    @Published var scrollOffset: CGPoint = .zero

    // MARK: Forwarded from Bridge

    var session: LiveSession { bridge.session }
    var transport: TransportState { bridge.transport }
    var clipProgress: ClipProgressStore { bridge.progress }
    var connectionState: ConnectionState { bridge.connectionState }
    var showManualConnect: Bool { bridge.showManualConnect }
    var discoveredDevices: [DiscoveredService] { bridge.discoveredDevices }
    var showDevicePicker: Bool { bridge.showDevicePicker }

    // MARK: Private

    let bridge: AbletonBridge
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(bridge: AbletonBridge) {
        self.bridge = bridge
        setupBindings()
    }

    private func setupBindings() {
        // Bubble up changes from bridge to trigger SwiftUI redraws
        bridge.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)
    }

    // MARK: - Clip Actions

    func tapClip(trackIndex: Int, sceneIndex: Int) {
        guard !isLocked else {
            HapticEngine.shared.error()
            return
        }

        let tracks = session.tracks
        guard trackIndex < tracks.count,
              sceneIndex < tracks[trackIndex].clipSlots.count
        else { return }

        let slot = tracks[trackIndex].clipSlots[sceneIndex]
        let track = tracks[trackIndex]

        if performanceMode == .performance && !slot.isEmpty {
            // In performance mode, require confirmation for non-empty clips
            // to prevent accidental clip switches
            // Actually in performance mode we launch immediately — huge targets
            // are the safety mechanism; confirmation is for lock mode only
        }

        if slot.isEmpty && !track.isArmed {
            HapticEngine.shared.trackStop()
        } else {
            HapticEngine.shared.clipLaunch()
        }
        bridge.launchClip(
            trackIndex: trackIndex,
            sceneIndex: sceneIndex,
            isEmpty: slot.isEmpty,
            isArmed: track.isArmed
        )
    }

    func deleteClip(trackIndex: Int, sceneIndex: Int) {
        guard !isLocked else {
            HapticEngine.shared.error()
            return
        }

        let tracks = session.tracks
        guard trackIndex < tracks.count,
              sceneIndex < tracks[trackIndex].clipSlots.count
        else { return }

        guard !tracks[trackIndex].clipSlots[sceneIndex].isEmpty else { return }

        HapticEngine.shared.clipDelete()
        bridge.deleteClip(trackIndex: trackIndex, sceneIndex: sceneIndex)
    }

    func tapScene(sceneIndex: Int) {
        guard !isLocked else {
            HapticEngine.shared.error()
            return
        }
        HapticEngine.shared.sceneLaunch()
        bridge.launchScene(sceneIndex: sceneIndex)
    }

    func stopTrack(trackIndex: Int) {
        guard !isLocked else {
            HapticEngine.shared.error()
            return
        }
        HapticEngine.shared.trackStop()
        bridge.stopTrack(trackIndex: trackIndex)
    }

    func stopAll() {
        if isLocked {
            HapticEngine.shared.error()
            return
        }
        confirmationPending = ConfirmationAction(
            title: "Stop All Clips?",
            message: "This will stop all playing clips immediately.",
            action: { [weak self] in
                self?.bridge.stopAll()
                HapticEngine.shared.transportChange()
            }
        )
    }

    // MARK: - Track Controls

    func toggleMute(trackIndex: Int) {
        HapticEngine.shared.toggleControl()
        bridge.muteTrack(trackIndex: trackIndex, toggle: true)
    }

    func toggleSolo(trackIndex: Int) {
        HapticEngine.shared.toggleControl()
        bridge.soloTrack(trackIndex: trackIndex, toggle: true)
    }

    func toggleArm(trackIndex: Int) {
        HapticEngine.shared.toggleControl()
        bridge.armTrack(trackIndex: trackIndex, toggle: true)
    }

    // MARK: - Transport Controls

    func play() {
        HapticEngine.shared.transportChange()
        bridge.play()
    }

    func stopTransport() {
        HapticEngine.shared.transportChange()
        bridge.stopTransportPlayback()
    }

    func toggleRecord() {
        bridge.toggleRecord()
    }

    func toggleMetronome() {
        bridge.toggleMetronome()
    }

    func toggleOverdub() {
        bridge.toggleOverdub()
    }

    func adjustTempo(by delta: Double) {
        let newBpm = max(60, min(200, transport.bpm + delta))
        HapticEngine.shared.tempoTick()
        bridge.setTempo(newBpm)
    }

    // MARK: - Mode Control

    func togglePerformanceMode() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            performanceMode = performanceMode == .performance ? .normal : .performance
        }
    }

    func toggleLock() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isLocked.toggle()
        }
        HapticEngine.shared.toggleControl()
    }

    // MARK: - Sync

    func requestSync() {
        bridge.requestFullSync()
    }

    func selectDevice(_ service: DiscoveredService) {
        bridge.selectDevice(service)
    }
}

// MARK: - Confirmation Action

struct ConfirmationAction: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let action: () -> Void
}
