import AppKit
import Foundation
import SwiftUI

@MainActor
extension LauncherViewModel {

    func executeSwitchToDesktop(_ space: SpaceGroup) {
        DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeSwitchToDesktop: space=\(space.name) (id=\(space.id))")
        LauncherWindowController.shared.shouldRestoreFocus = false
        incrementCommandFrequency(LauncherCommandType.switchToDesktop.rawValue)
        if let manager = AppDelegate.shared.spaceManager,
           let desktopSpace = manager.spaceNameDict.first(where: { $0.id == space.id }) {
            manager.switchToSpace(desktopSpace, forceInstant: true)
        }
        closeLauncher()
    }
    
    func executeSwitchToSpaceID(_ spaceID: String) {
        DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeSwitchToSpaceID: spaceID=\(spaceID)")
        LauncherWindowController.shared.shouldRestoreFocus = false
        incrementCommandFrequency(LauncherCommandType.switchToDesktop.rawValue)
        if let manager = AppDelegate.shared.spaceManager,
           let desktopSpace = manager.spaceNameDict.first(where: { $0.id == spaceID }) {
            manager.switchToSpace(desktopSpace, forceInstant: true)
        }
        closeLauncher()
    }
    
    func executeMoveWindow(_ space: SpaceGroup) {
        DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeMoveWindow: space=\(space.name) (id=\(space.id))")
        incrementCommandFrequency(LauncherCommandType.moveWindow.rawValue)
        let handled = movePreviouslyActiveWindow(toSpaceID: space.id)
        if !handled {
            closeLauncher()
        }
    }
    
    @discardableResult
    func movePreviouslyActiveWindow(toSpaceID spaceID: String) -> Bool {
        guard let prevWindow = previouslyActiveWindow else {
            DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "warning", "movePreviouslyActiveWindow: previouslyActiveWindow is nil")
            return false
        }
        
        let displayID = SpaceHelper.getWindowDisplayID(for: prevWindow.frame) ?? ""
        let fromSpaceIDStr = SpaceHelper.getCurrentSpaceID(for: displayID) ?? "0"
        DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "movePreviouslyActiveWindow: window=\(prevWindow.id), fromSpace=\(fromSpaceIDStr), targetSpace=\(spaceID)")
        
        if spaceID == fromSpaceIDStr {
            print("Launcher: Window \(prevWindow.id) is already on space \(spaceID). No move needed.")
            return false
        }
        
        guard let manager = AppDelegate.shared.spaceManager,
              let targetSpace = manager.spaceNameDict.first(where: { $0.id == spaceID }) else {
            DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "warning", "movePreviouslyActiveWindow: targetSpace object not found for ID \(spaceID)")
            return false
        }

        let originalSourceSpaceID = SpaceHelper.getCurrentSpaceID(for: displayID)
        let isCrossDisplayMove = displayID != targetSpace.displayID

        guard !targetSpace.isFullscreen else {
            DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "movePreviouslyActiveWindow: target space is fullscreen; no move performed")
            return false
        }

        DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "movePreviouslyActiveWindow: moving window \(prevWindow.id) from space \(fromSpaceIDStr) to space \(spaceID)")

        LauncherWindowController.shared.shouldRestoreFocus = true
        closeLauncher()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            let moved = await WindowActionCoordinator.moveWindow(
                windowID: prevWindow.id,
                pid: prevWindow.pid,
                fromSpaceID: fromSpaceIDStr,
                targetSpaceID: spaceID
            )

            guard moved, manager.returnToOriginalAfterBatchMove else {
                return
            }

            // Cross-display moves restore both displays in the lower-level
            // SpaceManager path. Do not issue a second return here: this
            // launcher task may hold a stale global current-space ID and could
            // overwrite the correct source-display restoration.
            guard !isCrossDisplayMove else { return }

            try? await Task.sleep(nanoseconds: 800_000_000)

            if let originalSourceSpaceID,
               let originalSourceSpace = manager.spaceNameDict.first(where: {
                   $0.id == originalSourceSpaceID && $0.displayID == displayID
               }),
               SpaceHelper.getCurrentSpaceID(for: displayID) != originalSourceSpace.id {
                manager.switchToSpace(originalSourceSpace, forceInstant: true)
            }
        }
        return true
    }
    
    func executeFocusWindow(_ window: WindowEntry) {
        DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeFocusWindow: window=\(window.title) (id=\(window.id), pid=\(window.pid))")
        LauncherWindowController.shared.shouldRestoreFocus = false
        incrementCommandFrequency(LauncherCommandType.listWindows.rawValue)
        SpaceHelper.focusWindow(id: window.id, pid: window.pid)
        closeLauncher()
    }
    
    func executeRenameCurrentSpace(_ newName: String) {
        DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeRenameCurrentSpace: newName=\(newName)")
        incrementCommandFrequency(LauncherCommandType.renameCurrentSpace.rawValue)
        if let manager = AppDelegate.shared.spaceManager {
            manager.renameSpace(manager.currentSpaceUUID, to: newName)
        }
        closeLauncher()
    }

    func showRenameDialog(for space: SpaceGroup) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Rename Space")
        alert.informativeText = String(localized: "Enter a new name for \"\(space.name)\":")
        alert.addButton(withTitle: String(localized: "Rename"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.stringValue = space.name
        alert.accessoryView = textField

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newName.isEmpty, let manager = AppDelegate.shared.spaceManager {
                manager.renameSpace(space.id, to: newName)
            }
        }
    }
}
