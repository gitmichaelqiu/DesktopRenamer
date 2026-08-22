import AppKit
import Foundation
import SwiftUI

@MainActor
extension LauncherViewModel {

    func executeBatchMove() {
        guard !stagedMoves.isEmpty else { return }
        batchExecutionTask?.cancel()
        isExecutingBatchMove = true
        incrementCommandFrequency(LauncherCommandType.batchMoveWindows.rawValue)
        
        let actions = Array(stagedMoves.values)
        let originalSpaceUUID = AppDelegate.shared.spaceManager?.currentSpaceUUID
        DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeBatchMove: Starting batch move. Actions count=\(actions.count), originalSpaceUUID=\(originalSpaceUUID ?? "nil")")
        
        batchExecutionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isExecutingBatchMove = false
                self.stagedMoves.removeAll()
                self.batchExecutionTask = nil
                LauncherWindowController.shared.shouldRestoreFocus = false
            }

            do {
            // 1. Filter space-move actions
            let spaceMoveActions = actions.filter {
                switch $0.actionType {
                case .move, .restoreTo: return true
                default: return false
                }
            }
            
            // 2. Filter static actions
            let staticActions = actions.filter {
                switch $0.actionType {
                case .move, .restoreTo: return false
                default: return true
                }
            }
            
            // 3. Execute space moves grouped by source space
            if !spaceMoveActions.isEmpty {
                let movesBySource = Dictionary(grouping: spaceMoveActions, by: { $0.window.space.id })
                
                for (sourceId, sourceActions) in movesBySource {
                    DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeBatchMove: Group sourceID=\(sourceId), sourceActions count=\(sourceActions.count)")
                    if let manager = AppDelegate.shared.spaceManager,
                       let spaceObj = manager.spaceNameDict.first(where: { $0.id == sourceId }) {
                        manager.switchToSpace(spaceObj, forceInstant: true)
                    }
                    try await Task.sleep(nanoseconds: 600_000_000) // 0.6s settle time
                    
                    for (index, action) in sourceActions.enumerated() {
                        let targetSpaceID: String
                        
                        switch action.actionType {
                        case .move(let space):
                            targetSpaceID = space.id
                        case .restoreTo(let space):
                            targetSpaceID = space.id
                        default:
                            continue
                        }
                        
                        DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeBatchMove: Move window id=\(action.window.id) from space=\(action.window.space.id) to space=\(targetSpaceID)")
                        if action.window.space.id == targetSpaceID {
                            continue
                        }

                        if case .restoreTo = action.actionType {
                            await WindowActionCoordinator.moveWindow(
                                windowID: action.window.id,
                                pid: action.window.pid,
                                fromSpaceID: action.window.space.id,
                                targetSpaceID: targetSpaceID
                            )
                            if index < sourceActions.count - 1 {
                                if let manager = AppDelegate.shared.spaceManager,
                                   let spaceObj = manager.spaceNameDict.first(where: { $0.id == sourceId }) {
                                    manager.switchToSpace(spaceObj, forceInstant: true)
                                }
                                try await Task.sleep(nanoseconds: 600_000_000) // 0.6s switch settle
                            }
                            continue
                        }
                        
                        // Focus the targeted window first
                        SpaceHelper.focusWindow(id: action.window.id, pid: action.window.pid)
                        try await Task.sleep(nanoseconds: 250_000_000) // 0.25s focus settle
                        
                        // Un-fullscreen first if the window is currently in a fullscreen space
                        if action.window.space.isFullscreen {
                            DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeBatchMove: Un-fullscreen window id=\(action.window.id)")
                            var axWindow = SpaceHelper.getAXWindow(id: action.window.id, pid: action.window.pid)
                            if axWindow == nil {
                                if let app = NSRunningApplication(processIdentifier: action.window.pid) {
                                    app.activate(options: .activateIgnoringOtherApps)
                                    try await Task.sleep(nanoseconds: 400_000_000)
                                    axWindow = SpaceHelper.getAXWindow(id: action.window.id, pid: action.window.pid)
                                }
                            }
                            if let targetAXWindow = axWindow {
                                AXUIElementSetAttributeValue(targetAXWindow, "AXFullScreen" as CFString, false as CFTypeRef)
                                try await Task.sleep(nanoseconds: 1_200_000_000) // Wait for exit-fullscreen animation to settle
                            }
                        }
                        
                        if let manager = AppDelegate.shared.spaceManager {
                            manager.moveActiveWindowToSpace(id: targetSpaceID)
                        }
                        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s movement settle
                        
                        // Switch back to source space
                        if index < sourceActions.count - 1 {
                            if let manager = AppDelegate.shared.spaceManager,
                               let spaceObj = manager.spaceNameDict.first(where: { $0.id == sourceId }) {
                                manager.switchToSpace(spaceObj, forceInstant: true)
                            }
                            try await Task.sleep(nanoseconds: 600_000_000) // 0.6s switch settle
                        }
                    }
                }
            }
            
            // 4. Execute other actions (Close, Minimize, Hide, Fullscreen, Quit, Restore)
            for action in staticActions {
                let windowSpaceID = action.window.space.id
                let isFullscreenWindow = action.window.space.isFullscreen
                let requiresAX = (action.actionType == .close || action.actionType == .minimize || action.actionType == .enterFullScreen || action.actionType == .exitFullScreen || action.actionType == .restore || (action.actionType == .hide && isFullscreenWindow))
                
                DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeBatchMove: Static action: type=\(action.actionType.description), window id=\(action.window.id), app=\(action.window.ownerName), requiresAX=\(requiresAX)")

                if action.actionType == .quit {
                    self.removeApplicationWindowsFromList(pid: action.window.pid)
                }
                
                // If the target window is on a different space, switch to its space first so AX APIs can access it.
                if requiresAX,
                   let manager = AppDelegate.shared.spaceManager,
                   manager.currentSpaceUUID != windowSpaceID,
                   let spaceObj = manager.spaceNameDict.first(where: { $0.id == windowSpaceID }) {
                    manager.switchToSpace(spaceObj, forceInstant: true)
                    try await Task.sleep(nanoseconds: 600_000_000) // 0.6s settle time
                }
                
                // Un-fullscreen first if the window is currently fullscreen and the action requires it
                if isFullscreenWindow && (action.actionType == .close || action.actionType == .minimize || action.actionType == .hide) {
                    var axWindow = SpaceHelper.getAXWindow(id: action.window.id, pid: action.window.pid)
                    if axWindow == nil {
                        if let app = NSRunningApplication(processIdentifier: action.window.pid) {
                            app.activate(options: .activateIgnoringOtherApps)
                            try await Task.sleep(nanoseconds: 400_000_000)
                            axWindow = SpaceHelper.getAXWindow(id: action.window.id, pid: action.window.pid)
                        }
                    }
                    if let targetAXWindow = axWindow {
                        AXUIElementSetAttributeValue(targetAXWindow, "AXFullScreen" as CFString, false as CFTypeRef)
                        try await Task.sleep(nanoseconds: 1_200_000_000) // Wait for exit-fullscreen animation to settle
                    }
                }
                
                switch action.actionType {
                case .close:
                    var axWindow = SpaceHelper.getAXWindow(id: action.window.id, pid: action.window.pid)
                    if axWindow == nil {
                        if let app = NSRunningApplication(processIdentifier: action.window.pid) {
                            app.activate(options: .activateIgnoringOtherApps)
                            try await Task.sleep(nanoseconds: 400_000_000)
                            axWindow = SpaceHelper.getAXWindow(id: action.window.id, pid: action.window.pid)
                        }
                    }
                    if let targetAXWindow = axWindow {
                        var closeButtonRef: CFTypeRef?
                        if AXUIElementCopyAttributeValue(targetAXWindow, kAXCloseButtonAttribute as CFString, &closeButtonRef) == .success,
                           let closeButton = closeButtonRef {
                            AXUIElementPerformAction(closeButton as! AXUIElement, kAXPressAction as CFString)
                        }
                    }
                case .minimize:
                    var axWindow = SpaceHelper.getAXWindow(id: action.window.id, pid: action.window.pid)
                    if axWindow == nil {
                        if let app = NSRunningApplication(processIdentifier: action.window.pid) {
                            app.activate(options: .activateIgnoringOtherApps)
                            try await Task.sleep(nanoseconds: 400_000_000)
                            axWindow = SpaceHelper.getAXWindow(id: action.window.id, pid: action.window.pid)
                        }
                    }
                    if let targetAXWindow = axWindow {
                        AXUIElementSetAttributeValue(targetAXWindow, kAXMinimizedAttribute as CFString, true as CFTypeRef)
                    }
                case .hide:
                    if let app = NSRunningApplication(processIdentifier: action.window.pid) {
                        app.hide()
                    }
                case .enterFullScreen:
                    var axWindow = SpaceHelper.getAXWindow(id: action.window.id, pid: action.window.pid)
                    if axWindow == nil {
                        if let app = NSRunningApplication(processIdentifier: action.window.pid) {
                            app.activate(options: .activateIgnoringOtherApps)
                            try await Task.sleep(nanoseconds: 400_000_000)
                            axWindow = SpaceHelper.getAXWindow(id: action.window.id, pid: action.window.pid)
                        }
                    }
                    if let targetAXWindow = axWindow {
                        AXUIElementSetAttributeValue(targetAXWindow, "AXFullScreen" as CFString, true as CFTypeRef)
                        try await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                case .exitFullScreen:
                    var axWindow = SpaceHelper.getAXWindow(id: action.window.id, pid: action.window.pid)
                    if axWindow == nil {
                        if let app = NSRunningApplication(processIdentifier: action.window.pid) {
                            app.activate(options: .activateIgnoringOtherApps)
                            try await Task.sleep(nanoseconds: 400_000_000)
                            axWindow = SpaceHelper.getAXWindow(id: action.window.id, pid: action.window.pid)
                        }
                    }
                    if let targetAXWindow = axWindow {
                        AXUIElementSetAttributeValue(targetAXWindow, "AXFullScreen" as CFString, false as CFTypeRef)
                        try await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                case .quit:
                    if let app = NSRunningApplication(processIdentifier: action.window.pid) {
                        app.terminate()
                    }
                case .restore:
                    if let app = NSRunningApplication(processIdentifier: action.window.pid) {
                        app.unhide()
                    }
                    var axWindow = SpaceHelper.getAXWindow(id: action.window.id, pid: action.window.pid)
                    if axWindow == nil {
                        if let app = NSRunningApplication(processIdentifier: action.window.pid) {
                            app.activate(options: .activateIgnoringOtherApps)
                            try await Task.sleep(nanoseconds: 400_000_000)
                            axWindow = SpaceHelper.getAXWindow(id: action.window.id, pid: action.window.pid)
                        }
                    }
                    if let targetAXWindow = axWindow {
                        AXUIElementSetAttributeValue(targetAXWindow, kAXMinimizedAttribute as CFString, false as CFTypeRef)
                    }
                default:
                    break
                }
                try await Task.sleep(nanoseconds: 150_000_000) // 150ms delay between commands
            }
            
            DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeBatchMove: Finished batch move execution.")
            if let manager = AppDelegate.shared.spaceManager {
                if manager.returnToOriginalAfterBatchMove {
                    if let originalUUID = originalSpaceUUID,
                       let targetSpace = manager.spaceNameDict.first(where: { $0.id == originalUUID }) {
                        manager.switchToSpace(targetSpace, forceInstant: true)
                    }
                } else if let lastMoveAction = spaceMoveActions.last {
                    let lastTargetSpaceID: String
                    switch lastMoveAction.actionType {
                    case .move(let space), .restoreTo(let space):
                        lastTargetSpaceID = space.id
                    default:
                        lastTargetSpaceID = ""
                    }
                    if !lastTargetSpaceID.isEmpty,
                       let targetSpace = manager.spaceNameDict.first(where: { $0.id == lastTargetSpaceID }) {
                        manager.switchToSpace(targetSpace, forceInstant: true)
                    }
                }
            }
            
            self.closeLauncher()
            } catch {
                DiagnosticEventLog.shared.record(
                    subsystem: "Launcher",
                    level: "info",
                    "executeBatchMove: Cancelled or interrupted (\(error))."
                )
            }
        }
    }
}
