//
//  DesktopRenamerApp.swift
//  DesktopRenamer
//
//  Created by Michael Qiu on 2025/7/20.
//

import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    var spaceManager: SpaceManager!
    var statusBarController: StatusBarController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize SpaceManager and StatusBarController
        spaceManager = SpaceManager()
        statusBarController = StatusBarController(spaceManager: spaceManager)

        // Automatically check for updates on launch if enabled
        if UpdateManager.isAutoCheckEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                UpdateManager.shared.checkForUpdate(from: nil, suppressUpToDateAlert: true)
            }
        }
    }
}

@main
struct DesktopRenamerApp: App {
    // Attach the AppDelegate
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
    }
}
