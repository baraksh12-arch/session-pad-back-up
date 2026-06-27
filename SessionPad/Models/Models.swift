// Models.swift
// SessionPad — Complete data model for Live session state.
//
// All model types are value types (structs) for safe concurrent reads.
// LiveSession is a class (reference type) since it's mutated in place
// and observed via @Published in AbletonBridge.

import Foundation
import SwiftUI

// MARK: - LiveClipSlot

struct LiveClipSlot: Identifiable, Equatable {
    let id: String  // "t{trackIndex}:s{sceneIndex}"
    var trackIndex: Int
    var sceneIndex: Int
    var state: ClipState
    var colorIndex: Int
    var name: String

    init(trackIndex: Int, sceneIndex: Int) {
        self.id         = "t\(trackIndex):s\(sceneIndex)"
        self.trackIndex = trackIndex
        self.sceneIndex = sceneIndex
        self.state      = .empty
        self.colorIndex = 0
        self.name       = ""
    }

    var isEmpty: Bool { state == .empty }
    var isPlaying: Bool { state == .playing }
    var isRecording: Bool { state == .recording }
    var isStopped: Bool { state == .stopped }
    var isQueued: Bool { state == .queued || state == .recQueued }

    var color: Color { ColorMapper.color(forIndex: colorIndex) }

    var displayName: String {
        name.isEmpty ? "" : name
    }
}

// MARK: - LiveTrack

struct LiveTrack: Identifiable, Equatable {
    let id: String  // "track\(index)"
    var index: Int
    var name: String
    var colorIndex: Int
    var isMuted: Bool
    var isSolo: Bool
    var isArmed: Bool
    var clipSlots: [LiveClipSlot]

    init(index: Int, sceneCount: Int) {
        self.id         = "track\(index)"
        self.index      = index
        self.name       = "Track \(index + 1)"
        self.colorIndex = 0
        self.isMuted    = false
        self.isSolo     = false
        self.isArmed    = false
        self.clipSlots  = (0..<sceneCount).map { LiveClipSlot(trackIndex: index, sceneIndex: $0) }
    }

    var color: Color { ColorMapper.color(forIndex: colorIndex) }
}

// MARK: - LiveScene

struct LiveScene: Identifiable, Equatable {
    let id: String  // "scene\(index)"
    var index: Int
    var name: String
    var colorIndex: Int

    init(index: Int) {
        self.id         = "scene\(index)"
        self.index      = index
        self.name       = ""
        self.colorIndex = 0
    }

    var color: Color { ColorMapper.color(forIndex: colorIndex) }

    var displayName: String {
        name.isEmpty ? "Scene \(index + 1)" : name
    }
}

// MARK: - TransportState

class TransportState: ObservableObject {
    @Published var isPlaying   = false
    @Published var isRecording = false
    @Published var metronomeOn = false
    @Published var bpm: Double = 120.0
}

// MARK: - LiveSession

/// The root model object for the entire session state.
/// Mutated exclusively on the main actor via AbletonBridge.
@MainActor
final class LiveSession: ObservableObject {

    @Published private(set) var tracks: [LiveTrack] = []
    @Published private(set) var scenes: [LiveScene] = []

    var trackCount: Int { tracks.count }
    var sceneCount: Int { scenes.count }

    // MARK: - Structural Reset

    /// Called when matrixSize message is received.
    /// Rebuilds the entire grid with empty clip slots.
    func reset(trackCount: Int, sceneCount: Int) {
        scenes = (0..<sceneCount).map { LiveScene(index: $0) }
        tracks = (0..<trackCount).map { LiveTrack(index: $0, sceneCount: sceneCount) }
    }

    // MARK: - Clip Updates

    func updateClip(
        trackIndex: Int,
        sceneIndex: Int,
        state: ClipState,
        colorIndex: Int,
        name: String
    ) {
        guard trackIndex < tracks.count,
              sceneIndex < tracks[trackIndex].clipSlots.count
        else { return }

        tracks[trackIndex].clipSlots[sceneIndex].state      = state
        tracks[trackIndex].clipSlots[sceneIndex].colorIndex = colorIndex
        tracks[trackIndex].clipSlots[sceneIndex].name       = name
    }

    func setClipState(_ state: ClipState, trackIndex: Int, sceneIndex: Int) {
        guard trackIndex < tracks.count,
              sceneIndex < tracks[trackIndex].clipSlots.count
        else { return }
        tracks[trackIndex].clipSlots[sceneIndex].state = state
    }

    // MARK: - Track Updates

    func updateTrack(
        trackIndex: Int,
        isMuted: Bool,
        isSolo: Bool,
        isArmed: Bool,
        colorIndex: Int,
        name: String
    ) {
        guard trackIndex < tracks.count else {
            // Track doesn't exist yet — may arrive before matrix size
            return
        }
        tracks[trackIndex].name       = name
        tracks[trackIndex].colorIndex = colorIndex
        tracks[trackIndex].isMuted    = isMuted
        tracks[trackIndex].isSolo     = isSolo
        tracks[trackIndex].isArmed    = isArmed
    }

    // MARK: - Scene Updates

    func updateScene(sceneIndex: Int, colorIndex: Int, name: String) {
        guard sceneIndex < scenes.count else { return }
        scenes[sceneIndex].colorIndex = colorIndex
        scenes[sceneIndex].name       = name
    }
}
