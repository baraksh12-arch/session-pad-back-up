// TrackHeaderView.swift
// SessionPad — Track column header view.
//
// Displays:
//   - Track color strip
//   - Track name (truncated)
//   - Mute button (M)
//   - Solo button (S)
//   - Arm button (R)

import SwiftUI

struct TrackHeaderView: View {

    let track: LiveTrack
    let width: CGFloat
    let onMute: () -> Void
    let onSolo: () -> Void
    let onArm:  () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Color bar at top
            Rectangle()
                .fill(track.color)
                .frame(height: 4)

            // Track name
            Text(track.name)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)

            // Control buttons
            HStack(spacing: 3) {
                TrackControlButton(
                    label: "M",
                    isActive: track.isMuted,
                    activeColor: .yellow,
                    action: onMute
                )
                TrackControlButton(
                    label: "S",
                    isActive: track.isSolo,
                    activeColor: .cyan,
                    action: onSolo
                )
                TrackControlButton(
                    label: "R",
                    isActive: track.isArmed,
                    activeColor: .red,
                    action: onArm
                )
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        }
        .frame(width: width)
        .background(Color(white: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - TrackControlButton

private struct TrackControlButton: View {
    let label: String
    let isActive: Bool
    let activeColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(isActive ? .black : .white.opacity(0.5))
                .frame(maxWidth: .infinity)
                .frame(height: 16)
                .background(isActive ? activeColor : Color(white: 0.22))
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 2) {
        TrackHeaderView(
            track: {
                var t = LiveTrack(index: 0, sceneCount: 8)
                t.name = "Kick Drum"
                t.colorIndex = 1
                t.isArmed = true
                return t
            }(),
            width: 80,
            onMute: {},
            onSolo: {},
            onArm: {}
        )
        TrackHeaderView(
            track: {
                var t = LiveTrack(index: 1, sceneCount: 8)
                t.name = "Synth Lead"
                t.colorIndex = 9
                t.isMuted = true
                return t
            }(),
            width: 80,
            onMute: {},
            onSolo: {},
            onArm: {}
        )
    }
    .padding()
    .background(Color.black)
}
