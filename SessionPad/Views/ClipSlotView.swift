// ClipSlotView.swift
// SessionPad — Individual clip slot cell view.
//
// Displays:
//   - Clip name
//   - Clip color (background fill)
//   - State indicator (playing, recording, stopped, queued, empty)
//   - Animated state pulse for playing/recording clips
//   - Tap gesture for launch

import SwiftUI

// MARK: - Constants

private enum ClipMetrics {
    static let cornerRadius: CGFloat = 6
    static let borderWidth: CGFloat  = 1.5
    static let indicatorSize: CGFloat = 10
}

// MARK: - ClipSlotView

struct ClipSlotView: View {

    let slot: LiveClipSlot
    let cellSize: CGSize
    let onTap: () -> Void

    @State private var isPulsing = false

    var body: some View {
        ZStack {
            // Background
            backgroundLayer

            // Content
            if !slot.isEmpty {
                contentLayer
            } else {
                emptyLayer
            }

            // State indicator dot (bottom-left corner)
            stateIndicatorLayer
        }
        .frame(width: cellSize.width, height: cellSize.height)
        .clipShape(RoundedRectangle(cornerRadius: ClipMetrics.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: ClipMetrics.cornerRadius)
                .strokeBorder(borderColor, lineWidth: ClipMetrics.borderWidth)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onChange(of: slot.state) { newState in
            updatePulse(for: newState)
        }
        .onAppear {
            updatePulse(for: slot.state)
        }
    }

    // MARK: - Sub-Views

    @ViewBuilder
    private var backgroundLayer: some View {
        if slot.isEmpty {
            Color(white: 0.10)
        } else {
            slot.color
                .opacity(slot.isPlaying || slot.isRecording ? 0.85 : 0.55)
        }
    }

    @ViewBuilder
    private var contentLayer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer(minLength: 0)
            Text(slot.displayName)
                .font(.system(size: min(cellSize.width * 0.12, 11), weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 5)
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    @ViewBuilder
    private var emptyLayer: some View {
        // Subtle plus icon hint for armed tracks
        Image(systemName: "plus")
            .font(.system(size: 10, weight: .light))
            .foregroundColor(Color(white: 0.3))
    }

    @ViewBuilder
    private var stateIndicatorLayer: some View {
        VStack {
            Spacer()
            HStack {
                stateIndicator
                    .padding(5)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch slot.state {
        case .empty:
            EmptyView()

        case .stopped:
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.7))
                .frame(width: ClipMetrics.indicatorSize, height: ClipMetrics.indicatorSize)

        case .playing:
            // Animated triangle (play symbol)
            Image(systemName: "play.fill")
                .font(.system(size: ClipMetrics.indicatorSize - 2))
                .foregroundColor(.white)
                .scaleEffect(isPulsing ? 1.3 : 1.0)
                .animation(
                    isPulsing
                        ? .easeInOut(duration: 0.5).repeatForever(autoreverses: true)
                        : .default,
                    value: isPulsing
                )

        case .recording:
            // Pulsing red circle
            Circle()
                .fill(Color.red)
                .frame(width: ClipMetrics.indicatorSize, height: ClipMetrics.indicatorSize)
                .scaleEffect(isPulsing ? 1.4 : 0.8)
                .animation(
                    isPulsing
                        ? .easeInOut(duration: 0.4).repeatForever(autoreverses: true)
                        : .default,
                    value: isPulsing
                )

        case .queued:
            // Blinking triangle
            Image(systemName: "play.fill")
                .font(.system(size: ClipMetrics.indicatorSize - 2))
                .foregroundColor(.yellow)
                .opacity(isPulsing ? 1.0 : 0.2)
                .animation(
                    isPulsing
                        ? .easeInOut(duration: 0.3).repeatForever(autoreverses: true)
                        : .default,
                    value: isPulsing
                )

        case .recQueued:
            Circle()
                .fill(Color.orange)
                .frame(width: ClipMetrics.indicatorSize, height: ClipMetrics.indicatorSize)
                .opacity(isPulsing ? 1.0 : 0.2)
                .animation(
                    isPulsing
                        ? .easeInOut(duration: 0.3).repeatForever(autoreverses: true)
                        : .default,
                    value: isPulsing
                )
        }
    }

    // MARK: - Helpers

    private var borderColor: Color {
        switch slot.state {
        case .playing:    return .white.opacity(0.6)
        case .recording:  return .red.opacity(0.9)
        case .queued:     return .yellow.opacity(0.8)
        case .recQueued:  return .orange.opacity(0.8)
        case .stopped:    return .white.opacity(0.2)
        case .empty:      return .white.opacity(0.07)
        }
    }

    private func updatePulse(for state: ClipState) {
        let shouldPulse = state == .playing || state == .recording ||
                          state == .queued || state == .recQueued
        if shouldPulse != isPulsing {
            isPulsing = shouldPulse
        }
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 2) {
        ForEach([ClipState.empty, .stopped, .playing, .recording, .queued], id: \.rawValue) { state in
            let slot: LiveClipSlot = {
                var s = LiveClipSlot(trackIndex: 0, sceneIndex: 0)
                s.state = state
                s.name = state == .empty ? "" : "My Clip"
                s.colorIndex = 1
                return s
            }()
            ClipSlotView(slot: slot, cellSize: CGSize(width: 80, height: 60)) {}
        }
    }
    .padding()
    .background(Color.black)
}
