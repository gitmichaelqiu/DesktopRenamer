//
//  DesktopRenamerApp.swift
//  DesktopRenamer
//
//  Created by Michael Qiu on 2025/7/20.
//

import SwiftUI
import Combine

@main
struct DesktopRenamerApp: App {
    @StateObject private var spaceManager = SpaceManager()
    @State private var statusBarController: StatusBarController?
    
    var body: some Scene {
        WindowGroup {
            EmptyView()
                .hidden()
                .onAppear {
                    statusBarController = StatusBarController(spaceManager: spaceManager)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 0, height: 0)
    }
}

