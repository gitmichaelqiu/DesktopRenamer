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
    var body: some Scene {
        MenuBarExtra {
            StatusBarView()
        } label: {
            Text(verbatim: "")
        }
        .menuBarExtraStyle(.window)
    }
}
