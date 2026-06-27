// BridgeApp.swift
// macOS menu bar companion for SessionPad.

import SwiftUI
import AppKit

@main
struct SessionPadBridgeApp: App {
    @NSApplicationDelegateAdaptor(BridgeAppDelegate.self) private var appDelegate
    @StateObject private var router = BridgeRouter.shared

    var body: some Scene {
        MenuBarExtra {
            BridgeMenuView(router: router)
        } label: {
            Image(systemName: "circle.fill")
                .foregroundStyle(statusColor)
        }
        .menuBarExtraStyle(.menu)
    }

    private var statusColor: Color {
        switch router.status {
        case .starting: return .gray
        case .waitingForLive: return .red
        case .liveConnected: return .yellow
        case .liveAndIOS: return .green
        }
    }
}

final class BridgeAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start the relay servers immediately at launch so Bonjour advertising
        // and both listeners are live without requiring the menu to be opened.
        Task { @MainActor in
            BridgeRouter.shared.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            BridgeRouter.shared.stop()
        }
    }
}

@MainActor
struct BridgeMenuView: View {
    @ObservedObject var router: BridgeRouter

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SessionPad Bridge")
                .font(.headline)
                .padding(.bottom, 4)

            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider().padding(.vertical, 8)

            LabeledContent("Ableton Live") {
                Text(router.liveConnected ? "Connected" : "Waiting…")
                    .foregroundStyle(router.liveConnected ? .green : .orange)
            }

            LabeledContent("iOS clients") {
                Text("\(router.iosClientCount)")
            }

            LabeledContent("WebSocket port") {
                Text("\(SPBridge.iosWebSocketPort)")
                    .font(.system(.body, design: .monospaced))
            }

            if let startError = router.startError {
                Text(startError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 6)

                Button("Retry") {
                    router.stop()
                    router.start()
                }
                .padding(.top, 4)
            }

            Divider().padding(.vertical, 8)

            Text("1. Keep SessionPad Bridge running\n2. Open Ableton Live with SessionPad control surface\n3. Open SessionPad on iOS (same Wi‑Fi)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().padding(.vertical, 8)

            Button("Quit") {
                router.stop()
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 280)
    }

    private var statusText: String {
        switch router.status {
        case .starting:
            return "Starting…"
        case .waitingForLive:
            return "Waiting for Ableton Live"
        case .liveConnected:
            return "Live connected — waiting for iOS"
        case .liveAndIOS:
            return "Live + iOS connected"
        }
    }
}
