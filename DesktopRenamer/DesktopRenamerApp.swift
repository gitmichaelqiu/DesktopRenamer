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
    }
}

@main
struct DesktopRenamerApp: App {
    // Attach the AppDelegate
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // No visible windows needed
        WindowGroup {
            EmptyView()
                .hidden()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 0, height: 0)
    }
}
