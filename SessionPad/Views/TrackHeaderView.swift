// TrackHeaderView.swift
// SessionPad — Track column header view.
//
// Displays:
//   - Track color strip
//   - Track name (truncated) — tap to select, swipe to page banks
//   - Mute button (M)
//   - Solo button (S)
//   - Arm button (R)

import SwiftUI

struct TrackHeaderView: View {

    let track: LiveTrack
    let width: CGFloat
    let isSelected: Bool
    let onMute: () -> Void
    let onSolo: () -> Void
    let onArm:  () -> Void
    let onSelect: () -> Void
    let onPageLeft: () -> Void
    let onPageRight: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            trackHeadRegion

            // Control buttons — separate from tap/swipe region
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
        .background(isSelected ? Color(white: 0.20) : Color(white: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Track Head (color + name)

    @ViewBuilder
    private var trackHeadRegion: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(track.color)
                .frame(height: 4)

            Text(track.name)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    if value.translation.width <= -24 {
                        onPageRight()
                    } else if value.translation.width >= 24 {
                        onPageLeft()
                    }
                }
        )
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
            isSelected: true,
            onMute: {},
            onSolo: {},
            onArm: {},
            onSelect: {},
            onPageLeft: {},
            onPageRight: {}
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
            isSelected: false,
            onMute: {},
            onSolo: {},
            onArm: {},
            onSelect: {},
            onPageLeft: {},
            onPageRight: {}
        )
    }
    .padding()
    .background(Color.black)
}
