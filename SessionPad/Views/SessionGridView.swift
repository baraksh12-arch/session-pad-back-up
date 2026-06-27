// SessionGridView.swift
// SessionPad — Landscape-first scrollable session matrix.
//
// Layout (landscape iPhone / iPad):
//
//   ┌──────────┬──────────┬──────────┬──────────┐
//   │  corner  │ Track 1  │ Track 2  │ Track 3  │  ← FIXED header row
//   ├──────────┼──────────┼──────────┼──────────┤
//   │ Scene 1  │  [clip]  │  [clip]  │  [clip]  │  ↑
//   │ Scene 2  │  [clip]  │  [clip]  │  [clip]  │  │ scrolls vertically
//   │ Scene 3  │  [clip]  │  [clip]  │  [clip]  │  ↓
//   └──────────┴──────────┴──────────┴──────────┘
//
// Tracks are paged via the top-bar bank controls; only the current bank
// is rendered and sized to fill the available width.

import SwiftUI

// MARK: - Adaptive Grid Metrics

struct GridMetrics {
    let cellWidth:        CGFloat
    let cellHeight:       CGFloat
    let sceneLabelWidth:  CGFloat
    let trackHeaderHeight: CGFloat
    let gap:              CGFloat

    static func compute(
        containerSize: CGSize,
        channelsPerPage: Int,
        visibleTrackCount: Int,
        sceneCount: Int,
        performanceMode: PerformanceMode,
        isLandscape: Bool,
        isIpad: Bool
    ) -> GridMetrics {
        let gap: CGFloat = isIpad ? 3 : 2

        // Scene label column
        let sceneLabelWidth: CGFloat = isIpad ? 88 : (isLandscape ? 76 : 72)

        // Track header row height
        let trackHeaderHeight: CGFloat = isIpad ? 72 : (isLandscape ? 62 : 68)

        // Available space for the clip grid
        let availableW = containerSize.width  - sceneLabelWidth
        let availableH = containerSize.height - trackHeaderHeight

        // Cell width: fill width for the current bank of tracks
        let columnCount = max(1, min(channelsPerPage, visibleTrackCount))
        let cellW = (availableW - gap * CGFloat(columnCount - 1)) / CGFloat(columnCount)

        // Cell height: try to fit scenes on screen without scrolling if ≤ 8 scenes
        let visibleScenes = max(1, min(sceneCount, isLandscape ? (isIpad ? 8 : 6) : 5))
        let minCellH: CGFloat = isIpad ? 64 : (isLandscape ? 52 : 56)
        let fittedCellH = (availableH - gap * CGFloat(visibleScenes - 1)) / CGFloat(visibleScenes)
        var cellH = max(minCellH, fittedCellH)

        // Performance mode: enlarge cells
        if performanceMode == .performance {
            cellH = max(cellH, isIpad ? 90 : 72)
        }

        return GridMetrics(
            cellWidth: cellW,
            cellHeight: cellH,
            sceneLabelWidth: sceneLabelWidth,
            trackHeaderHeight: trackHeaderHeight,
            gap: gap
        )
    }
}

// MARK: - SessionGridView

struct SessionGridView: View {

    @ObservedObject var viewModel: SessionViewModel

    private var session: LiveSession { viewModel.session }
    private var visibleTracks: [LiveTrack] { viewModel.visibleTracks }

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            let isIpad      = UIDevice.current.userInterfaceIdiom == .pad
            let metrics     = GridMetrics.compute(
                containerSize:     geo.size,
                channelsPerPage:   viewModel.channelsPerPage,
                visibleTrackCount: visibleTracks.count,
                sceneCount:        session.sceneCount,
                performanceMode:   viewModel.performanceMode,
                isLandscape:       isLandscape,
                isIpad:            isIpad
            )

            VStack(spacing: 0) {
                // ── Fixed Track Header Row ─────────────────────────────────
                trackHeaderRow(metrics: metrics)

                // ── Scrollable Grid Body ───────────────────────────────────
                gridBody(metrics: metrics)
            }
        }
        .background(Color(white: 0.06))
    }

    // MARK: - Track Header Row

    @ViewBuilder
    private func trackHeaderRow(metrics: GridMetrics) -> some View {
        HStack(spacing: 0) {
            cornerCell(metrics: metrics)

            HStack(spacing: metrics.gap) {
                ForEach(visibleTracks) { track in
                    TrackHeaderView(
                        track: track,
                        width: metrics.cellWidth,
                        isSelected: viewModel.selectedTrackIndex == track.index,
                        onMute: { viewModel.toggleMute(trackIndex: track.index) },
                        onSolo: { viewModel.toggleSolo(trackIndex: track.index) },
                        onArm:  { viewModel.toggleArm(trackIndex: track.index)  },
                        onSelect: { viewModel.selectTrack(trackIndex: track.index) },
                        onPageLeft: { viewModel.pageLeft() },
                        onPageRight: { viewModel.pageRight() }
                    )
                }
            }
        }
        .frame(height: metrics.trackHeaderHeight)
        .background(Color(white: 0.09))
        .overlay(alignment: .bottom) {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.white.opacity(0.12))
        }
    }

    // MARK: - Corner Cell

    @ViewBuilder
    private func cornerCell(metrics: GridMetrics) -> some View {
        ZStack {
            Color(white: 0.09)
            Button {
                viewModel.requestSync()
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(white: 0.4))
                    Text("SYNC")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(white: 0.3))
                }
            }
            .buttonStyle(.plain)
        }
        .frame(width: metrics.sceneLabelWidth, height: metrics.trackHeaderHeight)
        .overlay(alignment: .trailing) {
            Rectangle()
                .frame(width: 1)
                .foregroundColor(Color.white.opacity(0.1))
        }
    }

    // MARK: - Grid Body (Vertical Scroll)

    @ViewBuilder
    private func gridBody(metrics: GridMetrics) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: metrics.gap) {
                ForEach(Array(session.scenes.enumerated()), id: \.element.id) { sIdx, scene in
                    HStack(spacing: metrics.gap) {
                        SceneLaunchButton(
                            scene: scene,
                            width: metrics.sceneLabelWidth,
                            height: metrics.cellHeight,
                            onTap: { viewModel.tapScene(sceneIndex: sIdx) }
                        )

                        ForEach(visibleTracks) { track in
                            let slot: LiveClipSlot = {
                                if sIdx < track.clipSlots.count {
                                    return track.clipSlots[sIdx]
                                }
                                return LiveClipSlot(trackIndex: track.index, sceneIndex: sIdx)
                            }()

                            ClipSlotView(
                                slot: slot,
                                cellSize: CGSize(width: metrics.cellWidth, height: metrics.cellHeight),
                                isArmed: track.isArmed,
                                isTrackSelected: viewModel.selectedTrackIndex == track.index,
                                progress: viewModel.clipProgress,
                                bpm: viewModel.transport.bpm,
                                isTransportPlaying: viewModel.transport.isPlaying,
                                onTap: {
                                    viewModel.tapClip(trackIndex: track.index, sceneIndex: sIdx)
                                },
                                onLongPress: {
                                    viewModel.deleteClip(trackIndex: track.index, sceneIndex: sIdx)
                                }
                            )
                            .id("\(track.id)-\(sIdx)")
                        }
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }
}

// MARK: - SceneLaunchButton

struct SceneLaunchButton: View {
    let scene: LiveScene
    let width: CGFloat
    let height: CGFloat
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(isPressed ? Color(white: 0.18) : Color(white: 0.11))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )

                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(scene.color)
                            .frame(width: 6, height: 6)
                        Spacer(minLength: 0)
                        Image(systemName: "play.fill")
                            .font(.system(size: 7))
                            .foregroundColor(Color(white: 0.35))
                    }
                    .padding(.horizontal, 7)

                    Text(scene.displayName)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(Color(white: 0.72))
                        .lineLimit(2)
                        .minimumScaleFactor(0.65)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 5)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: width, height: height)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.18, dampingFraction: 0.7), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
    }
}

// MARK: - Empty / Loading State

struct EmptySessionView: View {
    let connectionState: ConnectionState

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.quarternote.3")
                .font(.system(size: 44, weight: .thin))
                .foregroundColor(Color(white: 0.28))

            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundColor(Color(white: 0.55))

            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(Color(white: 0.32))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var title: String {
        switch connectionState {
        case .disconnected: return "Not Connected"
        case .connecting:   return "Connecting…"
        case .connected:    return "Waiting for session"
        case .error:        return "Connection Error"
        }
    }

    private var subtitle: String {
        switch connectionState {
        case .disconnected:
            return "Launch SessionPad Bridge on your Mac, enable the SessionPad control surface in Ableton Live, and join the same Wi‑Fi network."
        case .connecting:
            return "Searching for Ableton Live…"
        case .connected:
            return "Connected. Waiting for session data from Live."
        case .error(let msg):
            return msg
        }
    }
}
