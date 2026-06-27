// AppDelegate.swift
// SessionPad — UIApplicationDelegate.
//
// Responsibilities:
//   1. Lock iPhone to landscape
//   2. iPad: allow all orientations
//   3. Keep screen on during live performance

import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.isIdleTimerDisabled = true
        return true
    }

    // MARK: - Orientation Lock
    //
    // On iPhone: landscape only (left + right).
    // On iPad: all orientations (the wider screen works fine in portrait too,
    //          and many iPad stands are portrait).
    //
    // This method is called by UIKit whenever a new view controller is presented.
    // Returning the correct mask here overrides any per-ViewController setting.

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return .all
        }
        // iPhone — landscape only
        return .landscape
    }
}
