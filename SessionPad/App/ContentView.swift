// ContentView.swift
// SessionPad — Root view.

import SwiftUI

struct ContentView: View {

    @StateObject private var bridge = AbletonBridge()
    @StateObject private var viewModel: SessionViewModel

    init() {
        let b = AbletonBridge()
        _bridge = StateObject(wrappedValue: b)
        _viewModel = StateObject(wrappedValue: SessionViewModel(bridge: b))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color(white: 0.05).ignoresSafeArea()

                VStack(spacing: 0) {
                    TransportBarView(
                        transport: viewModel.transport,
                        viewModel: viewModel,
                        connectionState: viewModel.connectionState
                    )

                    ZStack {
                        if viewModel.session.trackCount > 0 {
                            SessionGridView(viewModel: viewModel)
                                .transition(.opacity)
                        } else {
                            emptyOrConnectingView
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: viewModel.session.trackCount > 0)
                }
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(
            isPresented: Binding(
                get: { viewModel.performanceMode == .performance },
                set: { isPresented in
                    viewModel.performanceMode = isPresented ? .performance : .normal
                }
            )
        ) {
            PerformanceModeView(viewModel: viewModel)
        }
        .confirmationDialog(
            viewModel.confirmationPending?.title ?? "",
            isPresented: Binding(
                get:  { viewModel.confirmationPending != nil },
                set:  { if !$0 { viewModel.confirmationPending = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pending = viewModel.confirmationPending {
                Button("Confirm", role: .destructive) {
                    pending.action()
                    viewModel.confirmationPending = nil
                }
                Button("Cancel", role: .cancel) {
                    viewModel.confirmationPending = nil
                }
            }
        } message: {
            Text(viewModel.confirmationPending?.message ?? "")
        }
        .onAppear {
            bridge.start()
        }
        .onDisappear {
            bridge.stop()
        }
    }

    @ViewBuilder
    private var emptyOrConnectingView: some View {
        switch viewModel.connectionState {
        case .connected:
            VStack(spacing: 14) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Color(white: 0.6))
                    .scaleEffect(1.3)
                Text("Loading session…")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Color(white: 0.35))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        default:
            ConnectionStatusView(
                state: viewModel.connectionState,
                showManualConnect: viewModel.showManualConnect,
                devices: viewModel.discoveredDevices,
                showDevicePicker: viewModel.showDevicePicker,
                onRetry: {
                    bridge.stop()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        bridge.start()
                    }
                },
                onManualConnect: { host, port in
                    bridge.connectManually(host: host, port: port)
                },
                onSelectDevice: { device in
                    bridge.selectDevice(device)
                }
            )
        }
    }
}

#Preview("Landscape iPhone") {
    ContentView()
}

#Preview("iPad") {
    ContentView()
}
