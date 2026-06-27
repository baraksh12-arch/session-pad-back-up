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
    static let stopButtonSize: CGFloat = 10
    static let longPressDuration: Double = 0.5
}

// MARK: - ClipSlotView

struct ClipSlotView: View {

    let slot: LiveClipSlot
    let cellSize: CGSize
    var isArmed: Bool = false
    var isTrackSelected: Bool = false
    @ObservedObject var progress: ClipProgressStore
    var bpm: Double = 120
    var isTransportPlaying: Bool = false
    let onTap: () -> Void
    var onLongPress: () -> Void = {}

    init(
        slot: LiveClipSlot,
        cellSize: CGSize,
        isArmed: Bool = false,
        isTrackSelected: Bool = false,
        progress: ClipProgressStore,
        bpm: Double = 120,
        isTransportPlaying: Bool = false,
        onTap: @escaping () -> Void,
        onLongPress: @escaping () -> Void = {}
    ) {
        self.slot = slot
        self.cellSize = cellSize
        self.isArmed = isArmed
        self.isTrackSelected = isTrackSelected
        self._progress = ObservedObject(wrappedValue: progress)
        self.bpm = bpm
        self.isTransportPlaying = isTransportPlaying
        self.onTap = onTap
        self.onLongPress = onLongPress
    }

    @State private var isPulsing = false
    @State private var pressFlash = false
    @State private var deleteArming = false

    var body: some View {
        ZStack {
            // Background
            backgroundLayer

            if isTrackSelected {
                Color.white.opacity(0.06)
                    .allowsHitTesting(false)
            }

            // Content
            if !slot.isEmpty {
                contentLayer
            } else {
                emptyLayer
            }

            // State indicator dot (bottom-left corner)
            stateIndicatorLayer

            // Momentary press flash
            RoundedRectangle(cornerRadius: ClipMetrics.cornerRadius)
                .fill(Color.white.opacity(pressFlash ? 0.25 : 0))
                .allowsHitTesting(false)

            // Long-press delete arming overlay
            if deleteArming && !slot.isEmpty {
                RoundedRectangle(cornerRadius: ClipMetrics.cornerRadius)
                    .fill(Color.red.opacity(0.35))
                    .allowsHitTesting(false)
                RoundedRectangle(cornerRadius: ClipMetrics.cornerRadius)
                    .strokeBorder(Color.red.opacity(0.9), lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: cellSize.width, height: cellSize.height)
        .scaleEffect(deleteArming ? 0.94 : (pressFlash ? 0.96 : 1.0))
        .clipShape(RoundedRectangle(cornerRadius: ClipMetrics.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: ClipMetrics.cornerRadius)
                .strokeBorder(borderColor, lineWidth: ClipMetrics.borderWidth)
        )
        .contentShape(Rectangle())
        .onTapGesture { handleTap() }
        .onLongPressGesture(
            minimumDuration: ClipMetrics.longPressDuration,
            pressing: { pressing in
                guard !slot.isEmpty else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    deleteArming = pressing
                }
            },
            perform: {
                guard !slot.isEmpty else { return }
                deleteArming = false
                onLongPress()
            }
        )
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
        } else if slot.isPlaying {
            TimelineView(.animation) { context in
                let fraction = ClipProgressInterpolator.fraction(
                    sample: progress.sample(for: slot.id),
                    bpm: bpm,
                    isTransportPlaying: isTransportPlaying,
                    now: context.date
                )
                ClipProgressFillView(
                    color: slot.color,
                    cellSize: cellSize,
                    fraction: fraction
                )
            }
        } else {
            slot.color
                .opacity(slot.isRecording ? 0.85 : 0.55)
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
        if isArmed {
            Circle()
                .strokeBorder(Color.red.opacity(0.7), lineWidth: 1.5)
                .background(Circle().fill(Color.red.opacity(slot.state == .recQueued ? 0.5 : 0.15)))
                .frame(width: ClipMetrics.stopButtonSize + 2, height: ClipMetrics.stopButtonSize + 2)
        } else {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                )
                .frame(width: ClipMetrics.stopButtonSize, height: ClipMetrics.stopButtonSize)
        }
    }

    @ViewBuilder
    private var stateIndicatorLayer: some View {
        VStack {
            Spacer()
            HStack {
                if !slot.isEmpty {
                    stateIndicator
                        .padding(5)
                }
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

    private func handleTap() {
        withAnimation(.easeOut(duration: 0.08)) { pressFlash = true }
        onTap()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.easeOut(duration: 0.15)) { pressFlash = false }
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
    let progress = ClipProgressStore()
    HStack(spacing: 2) {
        ForEach([ClipState.empty, .stopped, .playing, .recording, .queued], id: \.rawValue) { state in
            let slot: LiveClipSlot = {
                var s = LiveClipSlot(trackIndex: 0, sceneIndex: 0)
                s.state = state
                s.name = state == .empty ? "" : "My Clip"
                s.colorIndex = 1
                return s
            }()
            ClipSlotView(
                slot: slot,
                cellSize: CGSize(width: 80, height: 60),
                progress: progress
            ) {}
        }
    }
    .padding()
    .background(Color.black)
}
