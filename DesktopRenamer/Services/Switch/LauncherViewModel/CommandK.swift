import AppKit
import Foundation
import SwiftUI

@MainActor
extension LauncherViewModel {

    func isWindowMinimizedOrAppHidden(_ window: WindowEntry) -> (minimized: Bool, hidden: Bool) {
        var isMin = false
        var isHid = false
        
        if let app = NSRunningApplication(processIdentifier: window.pid) {
            isHid = app.isHidden
        }
        
        if let axWindow = SpaceHelper.getAXWindow(id: window.id, pid: window.pid) {
            var minimizedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
               let isMinimized = minimizedRef as? Bool {
                isMin = isMinimized
            }
        }
        
        return (minimized: isMin, hidden: isHid)
    }

    func getAvailableCommandKActions(for window: WindowEntry) -> [BatchStagedActionType] {
        let (minimized, hidden) = isWindowMinimizedOrAppHidden(window)
        let isFS = window.space.isFullscreen
        let fullscreenAction: BatchStagedActionType = isFS ? .exitFullScreen : .enterFullScreen
        
        var actions: [BatchStagedActionType] = []
        actions.append(.close)
        if minimized || hidden {
            actions.append(.restore)
        }
        if !minimized {
            actions.append(.minimize)
        }
        if !hidden {
            actions.append(.hide)
        }
        actions.append(fullscreenAction)
        actions.append(.quit)
        
        return actions
    }
    
    var commandKActions: [BatchStagedActionType] {
        guard let window = commandKTargetWindow else { return [] }
        return getAvailableCommandKActions(for: window)
    }
    
    func showCommandKPanel() {
        if activeCommand?.type == .listWindows {
            let windows = filteredWindows
            let index = selectedRowIndex
            guard index >= 0 && index < windows.count else { return }
            commandKTargetWindow = windows[index]
            commandKSelectedIndex = 0
        } else {
            let items = batchMoveSelectableItems
            let index = selectedRowIndex
            guard index >= 0 && index < items.count else { return }
            let selectedItem = items[index]
            
            switch selectedItem {
            case .staged:
                return
            case .unstaged(let window, _):
                commandKTargetWindow = window
                commandKSelectedIndex = 0
            }
        }
    }
    
    func selectPreviousCommandKAction() {
        let count = commandKActions.count
        if count > 0 {
            commandKSelectedIndex = (commandKSelectedIndex - 1 + count) % count
        }
    }
    
    func selectNextCommandKAction() {
        let count = commandKActions.count
        if count > 0 {
            commandKSelectedIndex = (commandKSelectedIndex + 1) % count
        }
    }
    
    func executeCommandKAction() {
        guard let window = commandKTargetWindow else { return }
        let available = commandKActions
        guard commandKSelectedIndex >= 0 && commandKSelectedIndex < available.count else { return }
        let action = available[commandKSelectedIndex]
        
        DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeCommandKAction: window=\(window.title) (id=\(window.id)), action=\(action.description)")
        commandKTargetWindow = nil
        if activeCommand?.type == .listWindows {
            executeActionImmediately(window: window, actionType: action)
        } else {
            stagedMoves[window.id] = BatchStagedAction(window: window, actionType: action)
        }
    }
    
    func executeActionImmediately(window: WindowEntry, actionType: BatchStagedActionType) {
        let originalSpaceUUID = AppDelegate.shared.spaceManager?.currentSpaceUUID
        DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeActionImmediately: window=\(window.title) (id=\(window.id)), actionType=\(actionType.description), originalSpaceUUID=\(originalSpaceUUID ?? "nil")")

        if actionType == .quit {
            removeApplicationWindowsFromList(pid: window.pid)
        }
        
        Task {
            let windowSpaceID = window.space.id
            let isFullscreenWindow = window.space.isFullscreen
            let requiresAX = (actionType == .close || actionType == .minimize || actionType == .enterFullScreen || actionType == .exitFullScreen || actionType == .restore || (actionType == .hide && isFullscreenWindow))
            DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeActionImmediately: Task started. requiresAX=\(requiresAX), isFullscreenWindow=\(isFullscreenWindow)")
            
            // If the target window is on a different space, switch to its space first so AX APIs can access it.
            if requiresAX,
               let manager = AppDelegate.shared.spaceManager,
               manager.currentSpaceUUID != windowSpaceID,
               let spaceObj = manager.spaceNameDict.first(where: { $0.id == windowSpaceID }) {
                manager.switchToSpace(spaceObj, forceInstant: true)
                try? await Task.sleep(nanoseconds: 600_000_000) // 0.6s settle time
            }
            
            // Un-fullscreen first if the window is currently fullscreen and the action requires it
            if isFullscreenWindow && (actionType == .close || actionType == .minimize || actionType == .hide) {
                var axWindow = SpaceHelper.getAXWindow(id: window.id, pid: window.pid)
                if axWindow == nil {
                    if let app = NSRunningApplication(processIdentifier: window.pid) {
                        app.activate(options: .activateIgnoringOtherApps)
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        axWindow = SpaceHelper.getAXWindow(id: window.id, pid: window.pid)
                    }
                }
                if let targetAXWindow = axWindow {
                    AXUIElementSetAttributeValue(targetAXWindow, "AXFullScreen" as CFString, false as CFTypeRef)
                    try? await Task.sleep(nanoseconds: 1_200_000_000) // Wait for exit-fullscreen animation to settle
                }
            }
            
            switch actionType {
            case .close:
                var axWindow = SpaceHelper.getAXWindow(id: window.id, pid: window.pid)
                if axWindow == nil {
                    if let app = NSRunningApplication(processIdentifier: window.pid) {
                        app.activate(options: .activateIgnoringOtherApps)
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        axWindow = SpaceHelper.getAXWindow(id: window.id, pid: window.pid)
                    }
                }
                if let targetAXWindow = axWindow {
                    SpaceHelper.closeWindow(targetAXWindow)
                }
            case .minimize:
                var axWindow = SpaceHelper.getAXWindow(id: window.id, pid: window.pid)
                if axWindow == nil {
                    if let app = NSRunningApplication(processIdentifier: window.pid) {
                        app.activate(options: .activateIgnoringOtherApps)
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        axWindow = SpaceHelper.getAXWindow(id: window.id, pid: window.pid)
                    }
                }
                if let targetAXWindow = axWindow {
                    AXUIElementSetAttributeValue(targetAXWindow, kAXMinimizedAttribute as CFString, true as CFTypeRef)
                }
            case .hide:
                if let app = NSRunningApplication(processIdentifier: window.pid) {
                    app.hide()
                }
            case .enterFullScreen:
                var axWindow = SpaceHelper.getAXWindow(id: window.id, pid: window.pid)
                if axWindow == nil {
                    if let app = NSRunningApplication(processIdentifier: window.pid) {
                        app.activate(options: .activateIgnoringOtherApps)
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        axWindow = SpaceHelper.getAXWindow(id: window.id, pid: window.pid)
                    }
                }
                if let targetAXWindow = axWindow {
                    AXUIElementSetAttributeValue(targetAXWindow, "AXFullScreen" as CFString, true as CFTypeRef)
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            case .exitFullScreen:
                var axWindow = SpaceHelper.getAXWindow(id: window.id, pid: window.pid)
                if axWindow == nil {
                    if let app = NSRunningApplication(processIdentifier: window.pid) {
                        app.activate(options: .activateIgnoringOtherApps)
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        axWindow = SpaceHelper.getAXWindow(id: window.id, pid: window.pid)
                    }
                }
                if let targetAXWindow = axWindow {
                    AXUIElementSetAttributeValue(targetAXWindow, "AXFullScreen" as CFString, false as CFTypeRef)
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            case .quit:
                if let app = NSRunningApplication(processIdentifier: window.pid) {
                    app.terminate()
                }
            case .restore:
                if let app = NSRunningApplication(processIdentifier: window.pid) {
                    app.unhide()
                }
                var axWindow = SpaceHelper.getAXWindow(id: window.id, pid: window.pid)
                if axWindow == nil {
                    if let app = NSRunningApplication(processIdentifier: window.pid) {
                        app.activate(options: .activateIgnoringOtherApps)
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        axWindow = SpaceHelper.getAXWindow(id: window.id, pid: window.pid)
                    }
                }
                if let targetAXWindow = axWindow {
                    AXUIElementSetAttributeValue(targetAXWindow, kAXMinimizedAttribute as CFString, false as CFTypeRef)
                }
            case .restoreTo(let space):
                await WindowActionCoordinator.moveWindow(
                    windowID: window.id,
                    pid: window.pid,
                    fromSpaceID: window.space.id,
                    targetSpaceID: space.id
                )
            case .move(let space):
                if window.space.id != space.id {
                    _ = await WindowActionCoordinator.moveWindow(
                        windowID: window.id,
                        pid: window.pid,
                        fromSpaceID: window.space.id,
                        targetSpaceID: space.id
                    )
                }            
            }
            
            // Return to original space
            if let originalUUID = originalSpaceUUID,
               let manager = AppDelegate.shared.spaceManager,
               manager.returnToOriginalAfterBatchMove {
                if manager.currentSpaceUUID != originalUUID,
                   let targetSpace = manager.spaceNameDict.first(where: { $0.id == originalUUID }) {
                    manager.switchToSpace(targetSpace, forceInstant: true)
                }
            }
            
            await MainActor.run {
                self.loadData()
            }
        }
    }
}
