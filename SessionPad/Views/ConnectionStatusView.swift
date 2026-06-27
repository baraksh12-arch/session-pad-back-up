// ConnectionStatusView.swift
// SessionPad — Connection status overlay.

import SwiftUI

struct ConnectionStatusView: View {
    let state: ConnectionState
    let showManualConnect: Bool
    let onRetry: () -> Void
    let onManualConnect: (String, UInt16) -> Void

    @State private var manualHost = ""
    @State private var manualPort = String(SPBridge.iosWebSocketPort)

    var body: some View {
        VStack(spacing: 32) {
            ZStack {
                Circle()
                    .fill(iconBackgroundColor)
                    .frame(width: 80, height: 80)

                Image(systemName: iconName)
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(iconColor)
            }

            VStack(spacing: 8) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)

                Text(subtitle)
                    .font(.body)
                    .foregroundColor(Color(white: 0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if case .disconnected = state {
                setupStepsView
            }

            if showManualConnect {
                manualConnectView
            }

            Button {
                onRetry()
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(width: 160, height: 44)
                    .background(Color.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.04))
    }

    @ViewBuilder
    private var setupStepsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            SetupStep(number: 1, text: "Launch SessionPad Bridge on your Mac (menu bar app)")
            SetupStep(number: 2, text: "Install the SessionPad Remote Script and select it as a Control Surface in Ableton Live")
            SetupStep(number: 3, text: "Put this device and your Mac on the same Wi‑Fi network")
            SetupStep(number: 4, text: "Open SessionPad — it will find your Mac automatically")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(Color(white: 0.09))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private var manualConnectView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Can't find your Mac?")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)

            Text("Enter your Mac's IP address from SessionPad Bridge (port \(SPBridge.iosWebSocketPort)).")
                .font(.caption)
                .foregroundColor(Color(white: 0.5))

            TextField("192.168.1.10", text: $manualHost)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            HStack {
                Text("Port")
                    .font(.caption)
                    .foregroundColor(Color(white: 0.5))
                TextField("Port", text: $manualPort)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .frame(width: 80)
            }

            Button("Connect Manually") {
                let port = UInt16(manualPort) ?? SPBridge.iosWebSocketPort
                onManualConnect(manualHost, port)
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Color.white.opacity(manualHost.isEmpty ? 0.4 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .buttonStyle(.plain)
            .disabled(manualHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(16)
        .background(Color(white: 0.09))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 24)
    }

    private var iconName: String {
        switch state {
        case .disconnected: return "wifi.slash"
        case .connecting:   return "wifi"
        case .connected:    return "checkmark.circle.fill"
        case .error:        return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch state {
        case .disconnected: return Color(white: 0.5)
        case .connecting:   return .yellow
        case .connected:    return .green
        case .error:        return .orange
        }
    }

    private var iconBackgroundColor: Color {
        iconColor.opacity(0.15)
    }

    private var title: String {
        switch state {
        case .disconnected: return "Not Connected"
        case .connecting:   return "Searching…"
        case .connected:    return "Connected"
        case .error:        return "Connection Error"
        }
    }

    private var subtitle: String {
        switch state {
        case .disconnected:
            return "Searching for SessionPad Bridge on your network.\nMake sure the bridge app is running on your Mac and Ableton Live has the SessionPad control surface enabled."
        case .connecting:
            return "Looking for SessionPad Bridge on your local network…"
        case .connected(let name):
            return "Connected to \(name)"
        case .error(let e):
            return e
        }
    }
}

private struct SetupStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(white: 0.2))
                    .frame(width: 24, height: 24)
                Text("\(number)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.8))
            }

            Text(text)
                .font(.system(size: 13))
                .foregroundColor(Color(white: 0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
