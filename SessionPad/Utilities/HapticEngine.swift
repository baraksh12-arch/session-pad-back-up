// HapticEngine.swift
// SessionPad — Centralized haptic feedback engine.
//
// Provides distinct haptic patterns for different clip states.
// Using UIImpactFeedbackGenerator for the fastest trigger-to-haptic latency.

import UIKit

final class HapticEngine {

    // MARK: - Shared Instance

    static let shared = HapticEngine()

    // MARK: - Generators (pre-warmed for minimum latency)

    private let lightImpact   = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact  = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact   = UIImpactFeedbackGenerator(style: .heavy)
    private let rigidImpact   = UIImpactFeedbackGenerator(style: .rigid)
    private let softImpact    = UIImpactFeedbackGenerator(style: .soft)
    private let selectionGen  = UISelectionFeedbackGenerator()
    private let notificationGen = UINotificationFeedbackGenerator()

    private init() {
        // Pre-warm all generators to eliminate first-use latency
        lightImpact.prepare()
        mediumImpact.prepare()
        heavyImpact.prepare()
        rigidImpact.prepare()
        softImpact.prepare()
        selectionGen.prepare()
        notificationGen.prepare()
    }

    // MARK: - Public API

    /// Fired when tapping a non-empty clip to launch it.
    func clipLaunch() {
        mediumImpact.impactOccurred(intensity: 0.8)
        mediumImpact.prepare()
    }

    /// Fired when launching a scene row.
    func sceneLaunch() {
        heavyImpact.impactOccurred(intensity: 1.0)
        heavyImpact.prepare()
    }

    /// Fired when a clip starts playing (Live confirms playback).
    func clipStartedPlaying() {
        rigidImpact.impactOccurred(intensity: 0.6)
        rigidImpact.prepare()
    }

    /// Fired when a clip starts recording.
    func clipStartedRecording() {
        notificationGen.notificationOccurred(.warning)
        notificationGen.prepare()
    }

    /// Fired when stopping a track.
    func trackStop() {
        lightImpact.impactOccurred(intensity: 0.5)
        lightImpact.prepare()
    }

    /// Fired when a clip is deleted via long-press.
    func clipDelete() {
        heavyImpact.impactOccurred(intensity: 1.0)
        notificationGen.notificationOccurred(.warning)
        heavyImpact.prepare()
        notificationGen.prepare()
    }

    /// Fired when toggling mute/solo/arm.
    func toggleControl() {
        selectionGen.selectionChanged()
        selectionGen.prepare()
    }

    /// Fired when adjusting tempo.
    func tempoTick() {
        lightImpact.impactOccurred(intensity: 0.3)
        lightImpact.prepare()
    }

    /// Fired when transport play/stop.
    func transportChange() {
        rigidImpact.impactOccurred(intensity: 0.9)
        rigidImpact.prepare()
    }

    /// Error / denied action (e.g., lock mode active).
    func error() {
        notificationGen.notificationOccurred(.error)
        notificationGen.prepare()
    }
}
