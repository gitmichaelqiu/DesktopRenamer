import Foundation
import AppKit
import Combine

extension SpaceAPI {

    func executeCommand(_ command: String, arguments: [String: String]) async throws -> String {
        guard let manager = spaceManager else { throw SpaceAPIError.appUnavailable }

        switch command {
        case "getAPIVersion":
            return DesktopRenamerAPIVersion.current
        case "getSpaceSnapshot":
            return try makeSpaceSnapshot(manager)
        case "getCurrentSpaceName":
            return manager.getSpaceName(manager.currentSpaceUUID)
        case "getCurrentSpaceID":
            return SpaceHelper.getCurrentSpaceIDs().joined(separator: ",")
        case "getAllSpaces":
            return manager.spaceNameDict.sorted {
                if $0.displayID != $1.displayID {
                    return $0.displayID.localizedStandardCompare($1.displayID) == .orderedAscending
                }
                return $0.num < $1.num
            }.map { space in
                let name = manager.getSpaceName(space.id)
                return "\(space.id)~\(name)~\(space.displayID)~\(space.num)~\(space.isFullscreen ? "1" : "0")~\(space.appPath ?? "")"
            }.joined(separator: "\n")
        case "switchToSpace":
            guard let spaceID = arguments["spaceID"],
                  let space = manager.spaceNameDict.first(where: { $0.id == spaceID }) else {
                throw SpaceAPIError.invalidArgument("Invalid space ID.")
            }
            manager.switchToSpace(space, forceInstant: true)
            return ""
        case "renameCurrentSpace":
            guard let name = arguments["name"] else { throw SpaceAPIError.invalidArgument("Missing space name.") }
            manager.renameSpace(manager.currentSpaceUUID, to: name)
            return ""
        case "renameSpace":
            guard let spaceID = arguments["spaceID"], let name = arguments["name"] else {
                throw SpaceAPIError.invalidArgument("Missing space ID or name.")
            }
            manager.renameSpace(spaceID, to: name)
            return ""
        case "rearrangeSpace":
            guard let spaceID = arguments["spaceID"], let direction = arguments["direction"] else {
                throw SpaceAPIError.invalidArgument("Missing space ID or direction.")
            }
            return try await rearrangeSpace(spaceID: spaceID, direction: direction, manager: manager)
        case "moveWindowNext":
            manager.moveActiveWindowToNextSpace()
            return ""
        case "moveWindowPrevious":
            manager.moveActiveWindowToPreviousSpace()
            return ""
        case "moveWindowToSpace":
            guard let spaceID = arguments["spaceID"] else { throw SpaceAPIError.invalidArgument("Missing space ID.") }
            try await moveActiveWindow(toSpaceID: spaceID, manager: manager)
            return ""
        case "reloadSpaceLabels":
            guard let labelManager = AppDelegate.shared.statusBarController?.labelManager else {
                throw SpaceAPIError.appUnavailable
            }
            labelManager.reloadAllWindows()
            return ""
        case "toggleMenubar":
            StatusBarController.toggleStatusBar()
            return StatusBarController.isStatusBarHidden ? "false" : "true"
        case "toggleLauncher":
            LauncherWindowController.shared.toggle()
            return LauncherWindowController.shared.window?.isVisible == true ? "true" : "false"
        case "toggleLabels":
            guard let labelManager = AppDelegate.shared.statusBarController?.labelManager else {
                throw SpaceAPIError.appUnavailable
            }
            labelManager.showActiveLabels.toggle()
            labelManager.showPreviewLabels.toggle()
            return labelManager.showActiveLabels && labelManager.showPreviewLabels ? "true" : "false"
        case "toggleActiveLabel":
            guard let labelManager = AppDelegate.shared.statusBarController?.labelManager else {
                throw SpaceAPIError.appUnavailable
            }
            labelManager.showActiveLabels.toggle()
            return labelManager.showActiveLabels ? "true" : "false"
        case "togglePreviewLabel":
            guard let labelManager = AppDelegate.shared.statusBarController?.labelManager else {
                throw SpaceAPIError.appUnavailable
            }
            labelManager.showPreviewLabels.toggle()
            return labelManager.showPreviewLabels ? "true" : "false"
        case "toggleDesktopVisibility":
            guard let labelManager = AppDelegate.shared.statusBarController?.labelManager else {
                throw SpaceAPIError.appUnavailable
            }
            labelManager.showOnDesktop.toggle()
            return labelManager.showOnDesktop ? "true" : "false"
        case "getWindows":
            let spaces = manager.spaceNameDict
            let names = Dictionary(uniqueKeysWithValues: spaces.map { ($0.id, manager.getSpaceName($0.id)) })
            return SpaceHelper.getWindowsForAllSpaces(spaces: spaces, spaceNames: names)
        case "focusWindow":
            guard let windowID = Int(arguments["windowID"] ?? ""), let pid = Int32(arguments["pid"] ?? "") else {
                throw SpaceAPIError.invalidArgument("Missing window ID or process ID.")
            }
            SpaceHelper.focusWindow(id: windowID, pid: pid)
            return ""
        case "executeWindowAction":
            guard let windowID = Int(arguments["windowID"] ?? ""),
                  let pid = Int32(arguments["pid"] ?? ""),
                  let action = arguments["action"] else {
                throw SpaceAPIError.invalidArgument("Missing window action arguments.")
            }
            try await executeWindowAction(windowID: windowID, pid: pid, action: action, manager: manager)
            return ""
        case "moveSpecificWindow":
            guard let windowID = Int(arguments["windowID"] ?? ""),
                  let fromSpaceID = arguments["fromSpaceID"],
                  let targetSpaceID = arguments["targetSpaceID"] else {
                throw SpaceAPIError.invalidArgument("Missing window move arguments.")
            }
            let moved: Bool
            if let pid = Int32(arguments["pid"] ?? "") {
                moved = await WindowActionCoordinator.moveWindow(
                    windowID: windowID,
                    pid: pid,
                    fromSpaceID: fromSpaceID,
                    targetSpaceID: targetSpaceID
                )
            } else if let fromSpaceID = Int(fromSpaceID), let targetSpaceID = Int(targetSpaceID) {
                SpaceHelper.moveWindowToSpace(
                    windowID: windowID,
                    fromSpaceID: fromSpaceID,
                    targetSpaceID: targetSpaceID
                )
                moved = true
            } else {
                throw SpaceAPIError.invalidArgument("A process ID or numeric space IDs are required.")
            }
            guard moved else { throw SpaceAPIError.operationFailed("Window move failed.") }
            return ""
        default:
            throw SpaceAPIError.unsupportedCommand(command)
        }
    }

    private func moveActiveWindow(toSpaceID targetSpaceID: String, manager: SpaceManager) async throws {
        guard let targetSpace = manager.spaceNameDict.first(where: { $0.id == targetSpaceID }) else {
            throw SpaceAPIError.invalidArgument("Invalid target Space ID.")
        }
        guard !targetSpace.isFullscreen else {
            throw SpaceAPIError.operationFailed("Window moves into fullscreen Spaces are not supported.")
        }
        guard let activeWindow = SpaceHelper.getActiveWindowInfo() else {
            throw SpaceAPIError.operationFailed("Could not identify the active window.")
        }

        let sourceDisplayID = SpaceHelper.getWindowDisplayID(for: activeWindow.frame)
        let sourceSpaceID = sourceDisplayID.flatMap { SpaceHelper.getCurrentSpaceID(for: $0) }
            ?? SpaceHelper.getWindowSpaceID(id: activeWindow.id)
            ?? manager.currentSpaceUUID

        guard manager.spaceNameDict.contains(where: { $0.id == sourceSpaceID }) else {
            throw SpaceAPIError.operationFailed("Could not identify the active window's source Space.")
        }

        let moved = await WindowActionCoordinator.moveWindow(
            windowID: activeWindow.id,
            pid: activeWindow.pid,
            fromSpaceID: sourceSpaceID,
            targetSpaceID: targetSpaceID
        )
        guard moved else {
            throw SpaceAPIError.operationFailed("Window move failed.")
        }
    }

    private func executeWindowAction(windowID: Int, pid: Int32, action: String, manager: SpaceManager) async throws {
        // Quitting an app is process-scoped and does not require its window to
        // be made frontmost. Avoid moving the user's desktop just to terminate
        // an application in another space.
        if action == "quit" {
            guard let app = NSRunningApplication(processIdentifier: pid) else {
                throw SpaceAPIError.operationFailed("Application is no longer running.")
            }
            app.terminate()
            return
        }

        if let spaceID = SpaceHelper.getWindowSpaceID(id: windowID),
           manager.currentSpaceUUID != spaceID,
           let space = manager.spaceNameDict.first(where: { $0.id == spaceID }) {
            manager.switchToSpace(space, forceInstant: true)
            try await Task.sleep(nanoseconds: 600_000_000)
        }

        await exitFullscreenWindowIfNeeded(
            windowID: windowID,
            pid: pid,
            action: action,
            manager: manager
        )

        if action == "hide" {
            NSRunningApplication(processIdentifier: pid)?.hide()
            return
        }

        if action == "restore" {
            NSRunningApplication(processIdentifier: pid)?.unhide()
        }

        var axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid)
        if axWindow == nil, let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: .activateIgnoringOtherApps)
            try await Task.sleep(nanoseconds: 400_000_000)
            axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid)
        }
        guard let axWindow else { throw SpaceAPIError.operationFailed("Window is no longer accessible.") }

        switch action {
        case "close":
            var closeButtonRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axWindow, kAXCloseButtonAttribute as CFString, &closeButtonRef) == .success,
                  let closeButton = closeButtonRef,
                  CFGetTypeID(closeButton) == AXUIElementGetTypeID() else {
                throw SpaceAPIError.operationFailed("Window does not expose a close action.")
            }
            AXUIElementPerformAction(closeButton as! AXUIElement, kAXPressAction as CFString)
        case "minimize", "restore":
            AXUIElementSetAttributeValue(
                axWindow,
                kAXMinimizedAttribute as CFString,
                (action == "minimize") as CFTypeRef
            )
        case "enterFullScreen", "exitFullScreen":
            AXUIElementSetAttributeValue(
                axWindow,
                "AXFullScreen" as CFString,
                (action == "enterFullScreen") as CFTypeRef
            )
            try await Task.sleep(nanoseconds: 1_000_000_000)
        default:
            throw SpaceAPIError.invalidArgument("Unsupported window action: \(action)")
        }
    }

    private func exitFullscreenWindowIfNeeded(
        windowID: Int,
        pid: Int32,
        action: String,
        manager: SpaceManager
    ) async {
        guard action == "close" || action == "minimize" || action == "hide",
              let spaceID = SpaceHelper.getWindowSpaceID(id: windowID),
              let space = manager.spaceNameDict.first(where: { $0.id == spaceID }),
              space.isFullscreen else {
            return
        }

        var axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid)
        if axWindow == nil, let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: .activateIgnoringOtherApps)
            try? await Task.sleep(nanoseconds: 400_000_000)
            axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid)
        }

        if let axWindow {
            AXUIElementSetAttributeValue(axWindow, "AXFullScreen" as CFString, false as CFTypeRef)
            try? await Task.sleep(nanoseconds: 1_200_000_000)
        }
    }

    private func rearrangeSpace(spaceID: String, direction: String, manager: SpaceManager) async throws -> String {
        guard let sourceSpace = manager.spaceNameDict.first(where: { $0.id == spaceID }) else {
            throw SpaceAPIError.invalidArgument("Invalid space ID.")
        }
        let orderedSpaces = manager.spaceNameDict
            .filter { $0.displayID == sourceSpace.displayID && (sourceSpace.isFullscreen || !$0.isFullscreen) }
            .sorted { $0.num < $1.num }
        guard let sourceIndex = orderedSpaces.firstIndex(where: { $0.id == sourceSpace.id }) else {
            throw SpaceAPIError.invalidArgument("Invalid space ID.")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let completion: (SpaceRearrangementService.Result) -> Void = { result in
                switch result {
                case .success:
                    manager.refreshSpaceState()
                    continuation.resume(returning: "")
                case .failure(let message):
                    continuation.resume(throwing: SpaceAPIError.operationFailed(message))
                }
            }

            switch direction.lowercased() {
            case "up":
                guard sourceIndex > 0 else {
                    continuation.resume(throwing: SpaceAPIError.invalidArgument("Space is already first."))
                    return
                }
                SpaceRearrangementService.shared.rearrange(
                    sourceID: spaceID,
                    before: orderedSpaces[sourceIndex - 1].id,
                    orderedSpaceIDs: orderedSpaces.map(\.id),
                    displayID: sourceSpace.displayID,
                    completion: completion
                )
            case "down":
                guard sourceIndex < orderedSpaces.count - 1 else {
                    continuation.resume(throwing: SpaceAPIError.invalidArgument("Space is already last."))
                    return
                }
                if sourceIndex + 2 < orderedSpaces.count {
                    SpaceRearrangementService.shared.rearrange(
                        sourceID: spaceID,
                        before: orderedSpaces[sourceIndex + 2].id,
                        orderedSpaceIDs: orderedSpaces.map(\.id),
                        displayID: sourceSpace.displayID,
                        completion: completion
                    )
                } else {
                    SpaceRearrangementService.shared.rearrangeToEnd(
                        sourceID: spaceID,
                        orderedSpaceIDs: orderedSpaces.map(\.id),
                        displayID: sourceSpace.displayID,
                        completion: completion
                    )
                }
            default:
                continuation.resume(throwing: SpaceAPIError.invalidArgument("Direction must be up or down."))
            }
        }
    }
    
}
