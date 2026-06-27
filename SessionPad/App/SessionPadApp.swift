// SessionPadApp.swift
// SessionPad — Application entry point.

import SwiftUI

@main
struct SessionPadApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .ignoresSafeArea(.keyboard) // MIDI app — keyboard should never appear in main view
        }
    }
}
