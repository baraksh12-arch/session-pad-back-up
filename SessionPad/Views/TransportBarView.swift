// TransportBarView.swift
// SessionPad — Compact transport bar optimised for landscape iPhone.
//
// Height adapts:
//   iPhone landscape: 50pt (very compact — every pixel of height is precious)
//   iPad:             58pt
//
// All controls are single-row. Tempo is displayed inline.
// A tap on the BPM readout opens a sheet for numeric entry.

import SwiftUI

struct TransportBarView: View {

    @ObservedObject var transport: TransportState
    let viewModel: SessionViewModel
    let connectionState: ConnectionState

    @State private var showTempoSheet = false
    @Environment(\.horizontalSizeClass) private var hSizeClass

    private var isCompact: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: Connection badge
            connectionBadge
                .padding(.leading, isCompact ? 10 : 16)

            divider

            // Transport: Play / Stop / Record / Metronome / Overdub
            transportButtons

            divider

            // Tempo
            tempoControl

            divider

            Spacer(minLength: 0)

            // Right: Lock + Stage mode + Stop-all
            rightControls
                .padding(.trailing, isCompact ? 10 : 16)
        }
        .frame(height: isCompact ? 50 : 58)
        .background(Color(white: 0.07))
        .overlay(alignment: .bottom) {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.white.opacity(0.10))
        }
        .sheet(isPresented: $showTempoSheet) {
            TempoInputSheet(
                currentBPM: transport.bpm,
                onConfirm: { bpm in
                    viewModel.bridge.setTempo(bpm)
                    showTempoSheet = false
                },
                onCancel: { showTempoSheet = false }
            )
            .presentationDetents([.height(220)])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Connection Badge

    @ViewBuilder
    private var connectionBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
                .shadow(color: dotColor.opacity(0.9), radius: 4)

            if !isCompact {
                Text(shortConnectionLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(white: 0.5))
                    .lineLimit(1)
                    .frame(maxWidth: 100, alignment: .leading)
            }
        }
        .frame(minWidth: isCompact ? 20 : 80, alignment: .leading)
    }

    // MARK: - Transport Buttons

    @ViewBuilder
    private var transportButtons: some View {
        HStack(spacing: isCompact ? 2 : 6) {
            TinyTransportButton(
                icon: transport.isPlaying ? "stop.fill" : "play.fill",
                label: transport.isPlaying ? "Stop" : "Play",
                isActive: transport.isPlaying,
                activeColor: transport.isPlaying ? Color(white: 0.85) : .green,
                compact: isCompact
            ) {
                if transport.isPlaying { viewModel.stopTransport() }
                else                   { viewModel.play()          }
            }

            TinyTransportButton(
                icon: "record.circle.fill",
                label: "Rec",
                isActive: transport.isRecording,
                activeColor: .red,
                compact: isCompact
            ) { viewModel.toggleRecord() }

            TinyTransportButton(
                icon: "metronome.fill",
                label: "Click",
                isActive: transport.metronomeOn,
                activeColor: .cyan,
                compact: isCompact
            ) { viewModel.toggleMetronome() }

            TinyTransportButton(
                icon: "smallcircle.circle.fill",
                label: "Dub",
                isActive: transport.overdubOn,
                activeColor: .orange,
                compact: isCompact
            ) { viewModel.toggleOverdub() }
        }
        .padding(.horizontal, isCompact ? 8 : 12)
    }

    // MARK: - Tempo Control

    @ViewBuilder
    private var tempoControl: some View {
        HStack(spacing: isCompact ? 3 : 6) {
            // Minus 1 BPM
            Button { viewModel.adjustTempo(by: -1) } label: {
                Image(systemName: "minus")
                    .font(.system(size: isCompact ? 10 : 12, weight: .semibold))
                    .foregroundColor(Color(white: 0.55))
                    .frame(width: isCompact ? 22 : 26, height: isCompact ? 28 : 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // BPM readout — tap to edit
            Button { showTempoSheet = true } label: {
                VStack(spacing: 0) {
                    Text(String(format: "%.1f", transport.bpm))
                        .font(.system(size: isCompact ? 15 : 18, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    if !isCompact {
                        Text("BPM")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(Color(white: 0.38))
                    }
                }
                .frame(minWidth: isCompact ? 52 : 60)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Plus 1 BPM
            Button { viewModel.adjustTempo(by: +1) } label: {
                Image(systemName: "plus")
                    .font(.system(size: isCompact ? 10 : 12, weight: .semibold))
                    .foregroundColor(Color(white: 0.55))
                    .frame(width: isCompact ? 22 : 26, height: isCompact ? 28 : 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, isCompact ? 6 : 10)
    }

    // MARK: - Right Controls

    @ViewBuilder
    private var rightControls: some View {
        HStack(spacing: isCompact ? 2 : 6) {
            // Stop All
            TinyTransportButton(
                icon: "stop.circle",
                label: "All",
                isActive: false,
                activeColor: .white,
                compact: isCompact
            ) { viewModel.stopAll() }

            // Lock
            TinyTransportButton(
                icon: viewModel.isLocked ? "lock.fill" : "lock.open",
                label: viewModel.isLocked ? "Locked" : "Lock",
                isActive: viewModel.isLocked,
                activeColor: .orange,
                compact: isCompact
            ) { viewModel.toggleLock() }

            // Stage Mode
            TinyTransportButton(
                icon: viewModel.performanceMode == .performance
                    ? "theatermasks.fill" : "theatermasks",
                label: "Stage",
                isActive: viewModel.performanceMode == .performance,
                activeColor: .purple,
                compact: isCompact
            ) { viewModel.togglePerformanceMode() }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(width: 1, height: isCompact ? 28 : 34)
            .padding(.horizontal, isCompact ? 6 : 8)
    }

    private var dotColor: Color {
        switch connectionState {
        case .connected:    return .green
        case .connecting:   return .yellow
        case .disconnected: return Color(white: 0.4)
        case .error:        return .orange
        }
    }

    private var shortConnectionLabel: String {
        switch connectionState {
        case .connected(let name):
            let truncated = name.count > 14 ? String(name.prefix(14)) + "…" : name
            return truncated
        case .connecting:   return "Connecting…"
        case .disconnected: return "No device"
        case .error:        return "Error"
        }
    }
}

// MARK: - TinyTransportButton

struct TinyTransportButton: View {
    let icon: String
    let label: String
    let isActive: Bool
    let activeColor: Color
    let compact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if compact {
                // iPhone landscape: icon only
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isActive ? activeColor : Color(white: 0.45))
                    .frame(width: 34, height: 34)
                    .background(isActive ? activeColor.opacity(0.12) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                // iPad: icon + label
                VStack(spacing: 2) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isActive ? activeColor : Color(white: 0.45))
                    Text(label)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(isActive ? activeColor.opacity(0.85) : Color(white: 0.32))
                }
                .frame(width: 42, height: 42)
                .background(isActive ? activeColor.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tempo Input Sheet

private struct TempoInputSheet: View {
    let currentBPM: Double
    let onConfirm: (Double) -> Void
    let onCancel: () -> Void

    @State private var text: String
    @FocusState private var focused: Bool

    init(currentBPM: Double, onConfirm: @escaping (Double) -> Void, onCancel: @escaping () -> Void) {
        self.currentBPM = currentBPM
        self.onConfirm  = onConfirm
        self.onCancel   = onCancel
        _text = State(initialValue: String(format: "%.1f", currentBPM))
    }

    var body: some View {
        VStack(spacing: 24) {
            Text("Set Tempo")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.top, 4)

            HStack {
                // Quick-select common BPMs
                ForEach([80, 100, 120, 140], id: \.self) { bpm in
                    Button("\(bpm)") {
                        text = "\(bpm).0"
                    }
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(white: 0.6))
                    .frame(width: 50, height: 30)
                    .background(Color(white: 0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .buttonStyle(.plain)
                }
            }

            TextField("BPM", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 36, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .focused($focused)
                .onAppear { focused = true }

            HStack(spacing: 24) {
                Button("Cancel") { onCancel() }
                    .foregroundColor(Color(white: 0.5))

                Button("Set Tempo") {
                    let cleaned = text.replacingOccurrences(of: ",", with: ".")
                    if let bpm = Double(cleaned) {
                        onConfirm(max(60.0, min(200.0, bpm)))
                    }
                }
                .fontWeight(.bold)
                .foregroundColor(.green)
            }
            .font(.system(size: 15))
        }
        .padding(24)
        .background(Color(white: 0.09))
        .preferredColorScheme(.dark)
    }
}
