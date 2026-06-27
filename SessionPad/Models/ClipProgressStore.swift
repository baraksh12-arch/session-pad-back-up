// ClipProgressStore.swift
// SessionPad — Per-clip loop progress samples for smooth UI interpolation.

import Foundation
import SwiftUI

struct ProgressSample: Equatable {
    let fraction: Double
    let loopBeats: Double
    let receivedAt: Date
}

@MainActor
final class ClipProgressStore: ObservableObject {

    var samples: [String: ProgressSample] = [:]

    func update(trackIndex: Int, sceneIndex: Int, fraction: Double, loopBeats: Double) {
        let key = "t\(trackIndex):s\(sceneIndex)"
        samples[key] = ProgressSample(
            fraction: fraction,
            loopBeats: loopBeats,
            receivedAt: Date()
        )
        objectWillChange.send()
    }

    func clear(trackIndex: Int, sceneIndex: Int) {
        let key = "t\(trackIndex):s\(sceneIndex)"
        guard samples.removeValue(forKey: key) != nil else { return }
        objectWillChange.send()
    }

    func clearAll() {
        guard !samples.isEmpty else { return }
        samples.removeAll()
        objectWillChange.send()
    }

    func sample(for slotID: String) -> ProgressSample? {
        samples[slotID]
    }
}

enum ClipProgressInterpolator {

    static func fraction(
        sample: ProgressSample?,
        bpm: Double,
        isTransportPlaying: Bool,
        now: Date
    ) -> Double {
        guard let sample else { return 0 }
        guard sample.loopBeats > 0 else { return sample.fraction }
        guard isTransportPlaying else { return sample.fraction }

        let rate = (bpm / 60.0) / sample.loopBeats
        let elapsed = now.timeIntervalSince(sample.receivedAt)
        let advanced = sample.fraction + elapsed * rate
        return advanced.truncatingRemainder(dividingBy: 1.0)
    }
}

struct ClipProgressFillView: View {
    let color: Color
    let cellSize: CGSize
    let fraction: Double
    var cornerRadius: CGFloat = 0
    var drainedOpacity: Double = 0.3
    var filledOpacity: Double = 0.85

    var body: some View {
        ZStack(alignment: .leading) {
            color.opacity(drainedOpacity)
            Rectangle()
                .fill(color.opacity(filledOpacity))
                .frame(width: max(0, cellSize.width * fraction))
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
