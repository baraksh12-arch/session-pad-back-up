// PerformanceModeView.swift
// SessionPad — Stage performance mode: maximum cell size, minimal chrome,
// debounce protection against accidental double-taps.

import SwiftUI

struct PerformanceModeView: View {

    @ObservedObject var viewModel: SessionViewModel
    @Environment(\.dismiss) private var dismiss

    // Debounce map: prevents double-launching the same clip within 300ms
    @State private var lastTapTime: [String: Date] = [:]
    private let debounceInterval: TimeInterval = 0.3

    private var session: LiveSession { viewModel.session }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Minimal header bar
                performanceHeader

                // Full-screen grid
                performanceGrid
            }

            // Lock overlay
            if viewModel.isLocked {
                lockOverlay
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }

    // MARK: - Performance Header

    @ViewBuilder
    private var performanceHeader: some View {
        HStack {
            // Exit performance mode
            Button {
                viewModel.togglePerformanceMode()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(white: 0.6))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)

            Spacer()

            // Transport — compact
            HStack(spacing: 20) {
                PerformanceTransportButton(
                    icon: viewModel.transport.isPlaying ? "stop.fill" : "play.fill",
                    color: viewModel.transport.isPlaying ? .white : .green,
                    action: {
                        if viewModel.transport.isPlaying {
                            viewModel.stopTransport()
                        } else {
                            viewModel.play()
                        }
                    }
                )

                Text(String(format: "%.1f", viewModel.transport.bpm))
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)

                PerformanceTransportButton(
                    icon: "record.circle.fill",
                    color: viewModel.transport.isRecording ? .red : Color(white: 0.4),
                    action: { viewModel.toggleRecord() }
                )
            }

            Spacer()

            // Lock toggle
            Button {
                viewModel.toggleLock()
            } label: {
                Image(systemName: viewModel.isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(viewModel.isLocked ? .orange : Color(white: 0.5))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(Color(white: 0.05))
    }

    // MARK: - Performance Grid

    @ViewBuilder
    private var performanceGrid: some View {
        GeometryReader { geo in
            let trackCount = max(1, session.trackCount)
            let sceneCount = max(1, session.sceneCount)

            // Fill the screen with the grid
            let availableW = geo.size.width - 64  // Leave 64pt for scene labels
            let cellW = availableW / CGFloat(min(trackCount, 8))
            let cellH = (geo.size.height) / CGFloat(min(sceneCount, 8))
            let cellSize = CGSize(width: max(cellW, 60), height: max(cellH, 60))

            ScrollView([.horizontal, .vertical]) {
                HStack(spacing: 3) {
                    // Scene launch column
                    VStack(spacing: 3) {
                        ForEach(Array(session.scenes.enumerated()), id: \.element.id) { sIdx, scene in
                            Button {
                                guard !viewModel.isLocked else { return }
                                viewModel.tapScene(sceneIndex: sIdx)
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(white: 0.12))
                                    VStack(spacing: 4) {
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(Color(white: 0.5))
                                        Text(scene.displayName)
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundColor(Color(white: 0.5))
                                            .lineLimit(2)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .frame(width: 60, height: cellSize.height)
                        }
                    }

                    // Clip grid
                    VStack(spacing: 3) {
                        ForEach(Array(session.scenes.enumerated()), id: \.element.id) { sIdx, _ in
                            HStack(spacing: 3) {
                                ForEach(session.tracks) { track in
                                    let slot = sIdx < track.clipSlots.count
                                        ? track.clipSlots[sIdx]
                                        : LiveClipSlot(trackIndex: track.index, sceneIndex: sIdx)

                                    PerformanceClipCell(
                                        slot: slot,
                                        cellSize: cellSize,
                                        isLocked: viewModel.isLocked,
                                        onTap: {
                                            fireClip(trackIndex: track.index, sceneIndex: sIdx, slotID: slot.id)
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(8)
            }
        }
    }

    // MARK: - Lock Overlay

    @ViewBuilder
    private var lockOverlay: some View {
        Color.black.opacity(0.01)  // Invisible but absorbs taps in most buttons
            .ignoresSafeArea()
            .overlay(
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "lock.fill")
                                .foregroundColor(.orange)
                            Text("LOCKED")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(Capsule())
                        .padding()
                    }
                }
            )
    }

    // MARK: - Debounced Clip Fire

    private func fireClip(trackIndex: Int, sceneIndex: Int, slotID: String) {
        guard !viewModel.isLocked else {
            HapticEngine.shared.error()
            return
        }
        let now = Date()
        if let last = lastTapTime[slotID], now.timeIntervalSince(last) < debounceInterval {
            return  // Debounce — ignore rapid repeat tap
        }
        lastTapTime[slotID] = now
        viewModel.tapClip(trackIndex: trackIndex, sceneIndex: sceneIndex)
    }
}

// MARK: - PerformanceClipCell

private struct PerformanceClipCell: View {
    let slot: LiveClipSlot
    let cellSize: CGSize
    let isLocked: Bool
    let onTap: () -> Void

    @State private var isPulsing = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(cellBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(borderColor, lineWidth: 2)
                )

            if !slot.isEmpty {
                VStack(spacing: 6) {
                    stateIcon
                        .font(.system(size: 16))
                    if cellSize.height > 70 {
                        Text(slot.displayName)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.7)
                    }
                }
                .padding(8)
            }
        }
        .frame(width: cellSize.width, height: cellSize.height)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .scaleEffect(isPulsing ? 1.03 : 1.0)
        .animation(
            slot.isPlaying ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
            value: isPulsing
        )
        .onChange(of: slot.state) { _ in isPulsing = slot.isPlaying }
        .onAppear { isPulsing = slot.isPlaying }
    }

    private var cellBackground: Color {
        if slot.isEmpty { return Color(white: 0.08) }
        switch slot.state {
        case .playing:   return slot.color.opacity(0.75)
        case .recording: return Color.red.opacity(0.6)
        case .queued:    return slot.color.opacity(0.45)
        default:         return slot.color.opacity(0.35)
        }
    }

    private var borderColor: Color {
        switch slot.state {
        case .playing:   return .white.opacity(0.5)
        case .recording: return .red
        case .queued:    return .yellow.opacity(0.8)
        default:         return .white.opacity(0.06)
        }
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch slot.state {
        case .empty:      Image(systemName: "plus").foregroundColor(Color(white: 0.2))
        case .stopped:    Image(systemName: "stop.fill").foregroundColor(.white.opacity(0.6))
        case .playing:    Image(systemName: "play.fill").foregroundColor(.white)
        case .recording:  Image(systemName: "record.circle.fill").foregroundColor(.red)
        case .queued:     Image(systemName: "play.fill").foregroundColor(.yellow)
        case .recQueued:  Image(systemName: "record.circle").foregroundColor(.orange)
        }
    }
}

// MARK: - Transport Button (Performance)

private struct PerformanceTransportButton: View {
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }
}


