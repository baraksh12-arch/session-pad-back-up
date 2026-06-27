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
//               ←──── scrolls horizontally ────→
//
// Implementation strategy for sticky header + sticky left column:
//
//   We use a SINGLE ScrollView([.horizontal, .vertical]) for the body.
//   The track header row is a separate View OUTSIDE the ScrollView, placed
//   above it in a VStack. It listens to the horizontal scroll offset via a
//   PreferenceKey and mirrors it using an .offset() modifier, giving the
//   appearance of being part of the scrolling content while staying fixed.
//
//   Similarly the scene label column is rendered INSIDE the ScrollView but
//   sticks visually to the left edge by being placed in a ZStack overlay
//   that offsets by the current horizontal scroll value.
//
// Landscape optimization:
//   - On iPhone landscape: cells fill the full height minus the transport bar
//     and track header. Cell height = (screen height - 112) / visible_scene_count
//   - On iPad: larger default cell sizes, wider scene label column
//   - GeometryReader drives all sizing so rotation is instant

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
        trackCount: Int,
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

        // Cell width: try to fit tracks on screen without scrolling if ≤ 8 tracks
        let visibleTracks = max(1, min(trackCount, isIpad ? 10 : (isLandscape ? 8 : 5)))
        let minCellW: CGFloat = isIpad ? 80 : 68
        let fittedCellW = (availableW - gap * CGFloat(visibleTracks - 1)) / CGFloat(visibleTracks)
        var cellW = max(minCellW, fittedCellW)

        // Cell height: try to fit scenes on screen without scrolling if ≤ 8 scenes
        let visibleScenes = max(1, min(sceneCount, isLandscape ? (isIpad ? 8 : 6) : 5))
        let minCellH: CGFloat = isIpad ? 64 : (isLandscape ? 52 : 56)
        let fittedCellH = (availableH - gap * CGFloat(visibleScenes - 1)) / CGFloat(visibleScenes)
        var cellH = max(minCellH, fittedCellH)

        // Performance mode: enlarge cells
        if performanceMode == .performance {
            cellW = max(cellW, isIpad ? 110 : 90)
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

    // Horizontal scroll offset — shared between header row and body
    @State private var hOffset: CGFloat = 0

    private var session: LiveSession { viewModel.session }

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            let isIpad      = UIDevice.current.userInterfaceIdiom == .pad
            let metrics     = GridMetrics.compute(
                containerSize:    geo.size,
                trackCount:       session.trackCount,
                sceneCount:       session.sceneCount,
                performanceMode:  viewModel.performanceMode,
                isLandscape:      isLandscape,
                isIpad:           isIpad
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
            // Corner cell — sync button
            cornerCell(metrics: metrics)

            // Clipping container so header doesn't spill outside its lane
            GeometryReader { headerGeo in
                HStack(spacing: metrics.gap) {
                    ForEach(session.tracks) { track in
                        TrackHeaderView(
                            track: track,
                            width: metrics.cellWidth,
                            onMute: { viewModel.toggleMute(trackIndex: track.index) },
                            onSolo: { viewModel.toggleSolo(trackIndex: track.index) },
                            onArm:  { viewModel.toggleArm(trackIndex: track.index)  }
                        )
                    }
                    // Right padding so last cell isn't clipped
                    Spacer(minLength: 8)
                }
                // Mirror horizontal scroll offset
                .offset(x: -hOffset)
                .animation(nil, value: hOffset)  // no animation — must be instant
            }
            .clipped()
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

    // MARK: - Grid Body (2D Scrollable)

    @ViewBuilder
    private func gridBody(metrics: GridMetrics) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    // Main clip matrix (full width including scene label placeholder)
                    clipMatrix(metrics: metrics)

                    // Sticky scene label column overlaid at left edge
                    sceneColumn(metrics: metrics)
                        .offset(x: hOffset)
                        .animation(nil, value: hOffset)
                }
                // Track horizontal scroll position via background geometry reader
                .background(
                    GeometryReader { innerGeo in
                        Color.clear
                            .preference(
                                key: HScrollOffsetKey.self,
                                value: -innerGeo.frame(in: .named("sessionGrid")).origin.x
                            )
                    }
                )
            }
            .coordinateSpace(name: "sessionGrid")
            .onPreferenceChange(HScrollOffsetKey.self) { newOffset in
                // Only update if meaningfully different (debounce rounding noise)
                if abs(newOffset - hOffset) > 0.5 {
                    hOffset = newOffset
                }
            }
        }
    }

    // MARK: - Clip Matrix

    @ViewBuilder
    private func clipMatrix(metrics: GridMetrics) -> some View {
        LazyVStack(spacing: metrics.gap, pinnedViews: []) {
            ForEach(Array(session.scenes.enumerated()), id: \.element.id) { sIdx, _ in
                LazyHStack(spacing: metrics.gap) {
                    // Placeholder for scene label column width
                    Color.clear
                        .frame(width: metrics.sceneLabelWidth, height: metrics.cellHeight)

                    // Clip slots for this row
                    ForEach(session.tracks) { track in
                        let slot: LiveClipSlot = {
                            if sIdx < track.clipSlots.count {
                                return track.clipSlots[sIdx]
                            }
                            return LiveClipSlot(trackIndex: track.index, sceneIndex: sIdx)
                        }()

                        ClipSlotView(
                            slot: slot,
                            cellSize: CGSize(width: metrics.cellWidth, height: metrics.cellHeight),
                            onTap: {
                                viewModel.tapClip(trackIndex: track.index, sceneIndex: sIdx)
                            }
                        )
                        .id("\(track.id)-\(sIdx)")
                    }
                }
            }
        }
        .padding(.trailing, 8)
        .padding(.bottom, 8)
    }

    // MARK: - Scene Label Column

    @ViewBuilder
    private func sceneColumn(metrics: GridMetrics) -> some View {
        LazyVStack(spacing: metrics.gap) {
            ForEach(Array(session.scenes.enumerated()), id: \.element.id) { sIdx, scene in
                SceneLaunchButton(
                    scene: scene,
                    width: metrics.sceneLabelWidth,
                    height: metrics.cellHeight,
                    onTap: { viewModel.tapScene(sceneIndex: sIdx) }
                )
            }
            Spacer(minLength: 8)
        }
        .frame(width: metrics.sceneLabelWidth)
        .background(Color(white: 0.06))
        .overlay(alignment: .trailing) {
            Rectangle()
                .frame(width: 1)
                .foregroundColor(Color.white.opacity(0.1))
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

// MARK: - Preference Keys

private struct HScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
