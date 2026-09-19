import AppKit
import Foundation
import SwiftUI

@MainActor
extension LauncherViewModel {

    func executeSwitchToDesktop(_ space: SpaceGroup) {
        DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeSwitchToDesktop: space=\(space.name) (id=\(space.id))")
        incrementCommandFrequency(LauncherCommandType.switchToDesktop.rawValue)
        guard let manager = AppDelegate.shared.spaceManager,
              let desktopSpace = manager.spaceNameDict.first(where: { $0.id == space.id }) else {
            closeLauncher()
            HUDWindowController.shared.show(
                message: String(localized: "Could not switch to the selected space."),
                style: .failure
            )
            return
        }

        manager.switchToSpace(desktopSpace, forceInstant: true)
        closeLauncher()
        HUDWindowController.shared.showAfterLauncherDismissal(
            message: String(format: String(localized: "Switched to %@"), launcherSpaceName(for: desktopSpace)),
            style: .success
        )
    }
    
    func executeSwitchToSpaceID(_ spaceID: String) {
        DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeSwitchToSpaceID: spaceID=\(spaceID)")
        incrementCommandFrequency(LauncherCommandType.switchToDesktop.rawValue)
        guard let manager = AppDelegate.shared.spaceManager,
              let desktopSpace = manager.spaceNameDict.first(where: { $0.id == spaceID }) else {
            closeLauncher()
            HUDWindowController.shared.show(
                message: String(localized: "Could not switch to the selected space."),
                style: .failure
            )
            return
        }

        manager.switchToSpace(desktopSpace, forceInstant: true)
        closeLauncher()
        HUDWindowController.shared.showAfterLauncherDismissal(
            message: String(format: String(localized: "Switched to %@"), launcherSpaceName(for: desktopSpace)),
            style: .success
        )
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
    func stageSelectedListWindowForMove() -> Bool {
        guard activeCommand?.type == .listWindows,
              stagingWindow == nil,
              let window = selectedWindowForListWindows else {
            return false
        }

        let previousRowIndex = selectedRowIndex
        batchMoveLastSelectedIndex = previousRowIndex
        submenuSearchQuery = ""
        stagingWindow = window
        isSpaceMenuOpen = true
        spaceMenuSelectedIndex = 0
        isExecutingRestoreToImmediately = true
        selectedRowIndex = previousRowIndex
        return true
    }

    /// Matches Raycast's Move to Current Desktop action. The target must be
    /// the current Space on the selected window's display, not the first
    /// current Space returned across all displays.
    func moveSelectedListWindowToCurrentDesktop() {
        guard let window = selectedWindowForListWindows,
              let manager = AppDelegate.shared.spaceManager,
              let targetSpaceID = SpaceHelper.getCurrentSpaceID(for: window.space.displayID),
              let targetSpace = manager.spaceNameDict.first(where: { $0.id == targetSpaceID }) else {
            return
        }

        guard !targetSpace.isFullscreen else {
            DiagnosticEventLog.shared.record(
                subsystem: "Launcher",
                level: "warning",
                "moveSelectedListWindowToCurrentDesktop: current Space \(targetSpaceID) is fullscreen"
            )
            return
        }

        guard window.space.id != targetSpace.id else {
            DiagnosticEventLog.shared.record(
                subsystem: "Launcher",
                level: "info",
                "moveSelectedListWindowToCurrentDesktop: window \(window.id) is already on \(targetSpaceID)"
            )
            return
        }

        incrementCommandFrequency(LauncherCommandType.listWindows.rawValue)
        moveListWindow(window, to: targetSpace, using: manager)
    }

    private func moveListWindow(_ window: WindowEntry, to targetSpace: DesktopSpace, using manager: SpaceManager) {
        let originalSpaces = manager.returnToOriginalAfterBatchMove
            ? SpaceHelper.getCurrentSpaceIDsByDisplay()
            : [:]

        isExecutingAction = true
        closeLauncher()

        Task { @MainActor in
            defer {
                self.isExecutingAction = false
                self.requestLauncherFieldFocus()
            }

            try? await Task.sleep(nanoseconds: 200_000_000)
            let moved = await WindowActionCoordinator.moveWindow(
                windowID: window.id,
                pid: window.pid,
                fromSpaceID: window.space.id,
                targetSpaceID: targetSpace.id,
                wasMinimized: window.isMinimized,
                wasHidden: window.isHidden
            )

            guard moved else {
                HUDWindowController.shared.show(
                    message: String(format: String(localized: "Could not move %@"), window.title),
                    style: .failure
                )
                return
            }
            if manager.returnToOriginalAfterBatchMove {
                await WindowActionCoordinator.waitForMoveToSettle(
                    isFullscreen: window.space.isFullscreen
                )
                await WindowActionCoordinator.restoreOriginalSpaces(originalSpaces, using: manager)
            }
            HUDWindowController.shared.show(
                message: String(format: String(localized: "Moved window to %@"), launcherSpaceName(for: targetSpace)),
                style: .success
            )
        }
    }
    
    @discardableResult
    func movePreviouslyActiveWindow(toSpaceID spaceID: String) -> Bool {
        guard let prevWindow = previouslyActiveWindow else {
            DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "warning", "movePreviouslyActiveWindow: previouslyActiveWindow is nil")
            return false
        }
        
        let displayID = SpaceHelper.getWindowDisplayID(for: prevWindow.frame)
        let currentSpaceID = displayID.flatMap { SpaceHelper.getCurrentSpaceID(for: $0) }
        let assignedSpaceIDs = SpaceHelper.getWindowCurrentSpaces(windowID: prevWindow.id)
        let fromSpaceIDStr = currentSpaceID.flatMap { assignedSpaceIDs.contains($0) ? $0 : nil }
            ?? SpaceHelper.getWindowSpaceID(id: prevWindow.id)
            ?? currentSpaceID

        guard let fromSpaceIDStr else {
            DiagnosticEventLog.shared.record(
                subsystem: "Launcher",
                level: "warning",
                "movePreviouslyActiveWindow: could not resolve source Space for window \(prevWindow.id), assigned=\(assignedSpaceIDs.sorted()), current=\(currentSpaceID ?? "nil")"
            )
            return false
        }
        DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "movePreviouslyActiveWindow: window=\(prevWindow.id), fromSpace=\(fromSpaceIDStr), targetSpace=\(spaceID)")
        
        guard let manager = AppDelegate.shared.spaceManager,
              manager.spaceNameDict.contains(where: { $0.id == fromSpaceIDStr }),
              let targetSpace = manager.spaceNameDict.first(where: { $0.id == spaceID }),
              !targetSpace.isFullscreen else {
            DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "warning", "movePreviouslyActiveWindow: source or target Space is no longer available, source=\(fromSpaceIDStr), target=\(spaceID)")
            return false
        }

        if spaceID == fromSpaceIDStr {
            print("Launcher: Window \(prevWindow.id) is already on space \(spaceID). No move needed.")
            return false
        }

        let originalSpaces = manager.returnToOriginalAfterBatchMove
            ? SpaceHelper.getCurrentSpaceIDsByDisplay()
            : [:]

        DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "movePreviouslyActiveWindow: moving window \(prevWindow.id) from space \(fromSpaceIDStr) to space \(spaceID)")

        let sourceSpaceIsFullscreen = manager.spaceNameDict.first {
            $0.id == fromSpaceIDStr
        }?.isFullscreen ?? false

        isExecutingAction = true
        closeLauncher()

        Task { @MainActor in
            defer {
                self.isExecutingAction = false
                self.requestLauncherFieldFocus()
            }

            try? await Task.sleep(nanoseconds: 200_000_000)
            let moved = await WindowActionCoordinator.moveWindow(
                windowID: prevWindow.id,
                pid: prevWindow.pid,
                fromSpaceID: fromSpaceIDStr,
                targetSpaceID: spaceID
            )

            guard moved else {
                HUDWindowController.shared.show(
                    message: String(localized: "Could not move the window."),
                    style: .failure
                )
                return
            }
            if manager.returnToOriginalAfterBatchMove {
                await WindowActionCoordinator.waitForMoveToSettle(
                    isFullscreen: sourceSpaceIsFullscreen
                )
                await WindowActionCoordinator.restoreOriginalSpaces(originalSpaces, using: manager)
            }
            HUDWindowController.shared.show(
                message: String(format: String(localized: "Moved window to %@"), launcherSpaceName(for: targetSpace)),
                style: .success
            )
        }
        return true
    }
    
    func executeFocusWindow(_ window: WindowEntry) {
        DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeFocusWindow: window=\(window.title) (id=\(window.id), pid=\(window.pid))")
        incrementCommandFrequency(LauncherCommandType.listWindows.rawValue)
        isExecutingAction = true
        closeLauncher()

        Task { @MainActor in
            defer {
                self.isExecutingAction = false
                self.requestLauncherFieldFocus()
            }

            let focused = await WindowActionCoordinator.focusWindow(
                windowID: window.id,
                pid: window.pid,
                spaceID: window.space.id
            )
            let message: String
            if focused {
                message = String(format: String(localized: "Switched to %@"), window.title)
            } else {
                message = String(format: String(localized: "Could not focus %@"), window.title)
            }
            HUDWindowController.shared.show(
                message: message,
                style: focused ? .success : .failure
            )
        }
    }
    
    func executeRenameCurrentSpace(_ newName: String) {
        DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeRenameCurrentSpace: newName=\(newName)")
        incrementCommandFrequency(LauncherCommandType.renameCurrentSpace.rawValue)
        if let manager = AppDelegate.shared.spaceManager {
            manager.renameSpace(manager.currentSpaceUUID, to: newName)
        }
        closeLauncher()
        HUDWindowController.shared.showAfterLauncherDismissal(
            message: String(format: String(localized: "Renamed space to \"%@\""), newName),
            style: .success
        )
    }

    private func launcherSpaceName(for space: DesktopSpace) -> String {
        guard !space.customName.isEmpty else {
            return String(format: String(localized: "Space %lld"), space.num)
        }
        return space.customName
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
