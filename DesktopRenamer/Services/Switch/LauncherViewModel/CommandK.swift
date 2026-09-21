import AppKit
import Foundation
import SwiftUI

enum LauncherCommandKAction: Equatable {
    case moveWindow
    case moveWindowTo
    case window(BatchStagedActionType)
    case space(LauncherSpaceAction)

    var description: String {
        switch self {
        case .moveWindow:
            return "Move Window"
        case .moveWindowTo:
            return "Move to..."
        case .window(let action):
            return action.description
        case .space(let action):
            return action.description
        }
    }

    var shortcutText: String {
        switch self {
        case .moveWindow:
            return "⌘T"
        case .moveWindowTo:
            return "⌘⇧T"
        case .window(let action):
            switch action {
            case .close: return "⌃⇧W"
            case .minimize: return "⌃⇧M"
            case .hide: return "⌃⇧H"
            case .enterFullScreen, .exitFullScreen: return "⌃⇧F"
            case .quit: return "⌃⇧Q"
            case .restore: return "⌃⇧R"
            case .move, .restoreTo: return ""
            }
        case .space(let action):
            switch action {
            case .toggleLock:
                return "⌘L"
            case .restoreMovedWindows:
                return "⌘Z"
            case .rename:
                return "⌘R"
            case .moveUp:
                return "⌘⇧↑"
            case .moveDown:
                return "⌘⇧↓"
            }
        }
    }
}

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
    
    var commandKActions: [LauncherCommandKAction] {
        if let space = commandKTargetSpace {
            guard !space.isFullscreen else { return [] }

            let isLocked = AppDelegate.shared.spaceManager?.lockedSpaceIDs.contains(space.id) == true
            let movedWindowsCount = AppDelegate.shared.spaceManager?.movedWindowsOriginalSpaces.count ?? 0
            let available: [LauncherCommandKAction] = [
                .space(.toggleLock(isLocked: isLocked)),
                .space(.restoreMovedWindows(count: movedWindowsCount)),
                .space(.rename),
                .space(.moveUp),
                .space(.moveDown)
            ]
            guard !submenuSearchQuery.isEmpty else { return available }

            return available.filter {
                commandKActionLabel($0).localizedCaseInsensitiveContains(submenuSearchQuery) ||
                $0.description.localizedCaseInsensitiveContains(submenuSearchQuery)
            }
        }

        guard let window = commandKTargetWindow else { return [] }
        var available: [LauncherCommandKAction] = []
        if activeCommand?.type == .listWindows {
            available.append(.moveWindow)
            available.append(.moveWindowTo)
        }
        available.append(contentsOf: getAvailableCommandKActions(for: window).map { .window($0) })
        guard !submenuSearchQuery.isEmpty else { return available }

        return available.filter {
            commandKActionLabel($0).localizedCaseInsensitiveContains(submenuSearchQuery) ||
            $0.description.localizedCaseInsensitiveContains(submenuSearchQuery)
        }
    }

    var selectedSwitchDesktopSpace: SpaceGroup? {
        guard activeCommand?.type == .switchToDesktop else { return nil }
        let spaces = filteredSpaces
        guard spaces.indices.contains(selectedRowIndex) else { return nil }
        return spaces[selectedRowIndex]
    }

    func commandKActionLabel(_ action: LauncherCommandKAction) -> String {
        switch action {
        case .moveWindow:
            return NSLocalizedString("Move Window", comment: "")
        case .moveWindowTo:
            return NSLocalizedString("Move to...", comment: "")
        case .window(let action):
            switch action {
            case .close: return NSLocalizedString("Close", comment: "")
            case .minimize: return NSLocalizedString("Minimize", comment: "")
            case .hide: return NSLocalizedString("Hide", comment: "")
            case .enterFullScreen: return NSLocalizedString("Enter Full Screen", comment: "")
            case .exitFullScreen: return NSLocalizedString("Exit Full Screen", comment: "")
            case .quit: return NSLocalizedString("Quit", comment: "")
            case .restore: return NSLocalizedString("Restore", comment: "")
            case .restoreTo(let space):
                return space.name.isEmpty
                    ? NSLocalizedString("Restore to...", comment: "")
                    : String(format: NSLocalizedString("Restore to %@", comment: ""), space.name)
            case .move(let space):
                return space.name.isEmpty
                    ? NSLocalizedString("Move to...", comment: "")
                    : String(format: NSLocalizedString("Move to %@", comment: ""), space.name)
            }
        case .space(let action):
            switch action {
            case .toggleLock(let isLocked):
                return isLocked
                    ? NSLocalizedString("Unlock Space", comment: "")
                    : NSLocalizedString("Lock Space", comment: "")
            case .restoreMovedWindows(let count):
                let title = NSLocalizedString("Restore Moved Windows", comment: "")
                return "\(title) (\(count))"
            case .rename:
                return NSLocalizedString("Rename Space", comment: "")
            case .moveUp:
                return NSLocalizedString("Move Space Up", comment: "")
            case .moveDown:
                return NSLocalizedString("Move Space Down", comment: "")
            }
        }
    }
    
    func showCommandKPanel(isKeyboardInitiated: Bool = true) {
        submenuSearchQuery = ""
        isKeyboardSelection = isKeyboardInitiated
        renameTargetSpace = nil
        commandKTargetWindow = nil
        commandKTargetSpace = nil
        if activeCommand?.type == .listWindows {
            let windows = filteredWindows
            let index = selectedRowIndex
            guard index >= 0 && index < windows.count else { return }
            commandKTargetWindow = windows[index]
            commandKSelectedIndex = 0
        } else if activeCommand?.type == .switchToDesktop {
            let spaces = filteredSpaces
            let index = selectedRowIndex
            guard spaces.indices.contains(index),
                  !spaces[index].isFullscreen else { return }
            commandKTargetSpace = spaces[index]
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

    @discardableResult
    func handleCommandKActionShortcut(_ event: NSEvent) -> Bool {
        guard !isLauncherBusy,
              (commandKTargetWindow != nil || commandKTargetSpace != nil),
              event.type == .keyDown else {
            return false
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if commandKTargetSpace != nil {
            guard modifiers.subtracting([.command, .numericPad, .function]).isEmpty,
                  modifiers.contains(.command) else {
                return false
            }

            let action: LauncherCommandKAction?
            if characters == "l" {
                action = commandKActions.first(where: {
                    if case .space(.toggleLock) = $0 {
                        return true
                    }
                    return false
                })
            } else if characters == "z" {
                action = commandKActions.first(where: {
                    if case .space(.restoreMovedWindows) = $0 {
                        return true
                    }
                    return false
                })
            } else {
                return false
            }

            guard let action,
                  let index = commandKActions.firstIndex(of: action) else {
                return false
            }

            isKeyboardSelection = true
            commandKSelectedIndex = index
            executeCommandKAction()
            return true
        }

        guard commandKTargetWindow != nil else { return false }
        let action: LauncherCommandKAction?

        if modifiers.subtracting([.command, .shift, .numericPad, .function]).isEmpty,
           modifiers.contains(.command),
           characters == "t" {
            action = modifiers.contains(.shift) ? .moveWindowTo : .moveWindow
        } else if modifiers.subtracting([.control, .shift, .numericPad, .function]).isEmpty,
                  modifiers.contains(.control),
                  modifiers.contains(.shift) {
            guard let window = commandKTargetWindow else { return false }
            switch characters {
            case "w": action = .window(.close)
            case "m": action = .window(.minimize)
            case "r": action = .window(.restore)
            case "f":
                action = .window(window.space.isFullscreen ? .exitFullScreen : .enterFullScreen)
            case "h": action = .window(.hide)
            case "q": action = .window(.quit)
            default: return false
            }
        } else {
            return false
        }

        guard let action,
              let index = commandKActions.firstIndex(of: action) else {
            return false
        }
        isKeyboardSelection = true
        commandKSelectedIndex = index
        executeCommandKAction()
        return true
    }
    
    func selectPreviousCommandKAction() {
        guard !isLauncherBusy else { return }

        let count = commandKActions.count
        if count > 0 {
            isKeyboardSelection = true
            commandKSelectedIndex = (commandKSelectedIndex - 1 + count) % count
        }
    }
    
    func selectNextCommandKAction() {
        guard !isLauncherBusy else { return }

        let count = commandKActions.count
        if count > 0 {
            isKeyboardSelection = true
            commandKSelectedIndex = (commandKSelectedIndex + 1) % count
        }
    }
    
    func executeCommandKAction() {
        guard !isLauncherBusy else { return }
        let available = commandKActions
        guard commandKSelectedIndex >= 0 && commandKSelectedIndex < available.count else { return }
        let action = available[commandKSelectedIndex]

        if let space = commandKTargetSpace {
            commandKTargetSpace = nil
            submenuSearchQuery = ""

            guard let manager = AppDelegate.shared.spaceManager else { return }
            switch action {
            case .space(.toggleLock):
                guard !space.isFullscreen else { return }
                _ = manager.toggleLockSpace(space.id)
                loadData()
                requestLauncherFieldFocus()
            case .space(.restoreMovedWindows):
                manager.restoreAllMovedWindows()
                closeLauncher()
            case .space(.rename):
                showRenameSubmenu(for: space)
            case .space(.moveUp):
                rearrangeSelectedDesktop(direction: .up)
            case .space(.moveDown):
                rearrangeSelectedDesktop(direction: .down)
            default:
                break
            }
            return
        }

        guard let window = commandKTargetWindow else { return }
        
        DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeCommandKAction: window=\(window.title) (id=\(window.id)), action=\(action.description)")
        let isListWindows = activeCommand?.type == .listWindows
        switch action {
        case .moveWindow:
            guard isListWindows else { return }
            commandKTargetWindow = nil
            moveSelectedListWindowToCurrentDesktop()
        case .moveWindowTo:
            guard isListWindows else { return }
            guard stageSelectedListWindowForMove() else { return }
            // Clear the action target only after the target-space state is
            // ready, so the overlay transitions directly to the space menu.
            commandKTargetWindow = nil
        case .window(let actionType):
            commandKTargetWindow = nil
            if isListWindows {
                executeActionImmediately(window: window, actionType: actionType)
            } else {
                let originalItems = batchMoveSelectableItems
                let originalIndex = selectedRowIndex
                stagedMoves[window.id] = BatchStagedAction(window: window, actionType: actionType)
                restoreBatchMoveSelection(
                    afterActingOn: originalIndex,
                    in: originalItems
                )
            }
        case .space:
            break
        }
    }

    /// Raycast stages window actions from the Manage Windows action panel.
    /// Keep the native launcher's direct Control+Shift shortcuts on that same
    /// staging path instead of executing a background window immediately.
    func stageSelectedBatchWindowAction(_ actionType: BatchStagedActionType) {
        guard activeCommand?.type == .batchMoveWindows,
              stagingWindow == nil,
              selectedRowIndex >= 0,
              selectedRowIndex < batchMoveSelectableItems.count else {
            return
        }

        let item = batchMoveSelectableItems[selectedRowIndex]
        guard case .unstaged(let window, _) = item else { return }
        let originalItems = batchMoveSelectableItems
        let originalIndex = selectedRowIndex
        stagedMoves[window.id] = BatchStagedAction(window: window, actionType: actionType)
        restoreBatchMoveSelection(
            afterActingOn: originalIndex,
            in: originalItems
        )
    }
    
    func executeActionImmediately(window: WindowEntry, actionType: BatchStagedActionType) {
        guard !isLauncherBusy else { return }

        switch actionType {
        case .move(let space), .restoreTo(let space):
            guard !space.isFullscreen else {
                DiagnosticEventLog.shared.record(
                    subsystem: "Launcher",
                    level: "warning",
                    "executeActionImmediately: refusing to move window \(window.id) into fullscreen Space \(space.id)"
                )
                return
            }
        default:
            break
        }

        let windowDisplayID = window.space.displayID
        let originalSpaceUUID = SpaceHelper.getCurrentSpaceID(for: windowDisplayID)
        let originalSpacesByDisplay: [String: String] = {
            guard actionType != .quit,
                  let manager = AppDelegate.shared.spaceManager,
                  manager.returnToOriginalAfterBatchMove else {
                return [:]
            }
            return SpaceHelper.getCurrentSpaceIDsByDisplay()
        }()
        DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeActionImmediately: window=\(window.title) (id=\(window.id)), actionType=\(actionType.description), display=\(windowDisplayID), originalSpaceUUID=\(originalSpaceUUID ?? "nil")")

        if actionType == .quit {
            removeApplicationWindowsFromList(pid: window.pid)
        }

        let movesWindow = switch actionType {
        case .move, .restoreTo:
            true
        default:
            false
        }
        let appName = window.ownerName.isEmpty ? window.title : window.ownerName

        isExecutingAction = true

        if movesWindow {
            // The native launcher is still ordered above the selected window
            // when this action comes from the list-window submenu. Order it
            // out before the synthetic drag, otherwise the drag can start on
            // the launcher panel instead of the target window.
            closeLauncher()
        }
        
        Task { @MainActor in
            defer {
                self.isExecutingAction = false
                self.requestLauncherFieldFocus()
            }

            if movesWindow {
                // Let WindowServer finish removing the panel from the hit-test
                // stack before the move coordinator captures the drag point.
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            let windowSpaceID = window.space.id
            let isFullscreenWindow = window.space.isFullscreen
            var moveSucceeded = true
            let requiresAX = (actionType == .close || actionType == .minimize || actionType == .enterFullScreen || actionType == .exitFullScreen || actionType == .restore || (actionType == .hide && isFullscreenWindow))
            DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeActionImmediately: Task started. requiresAX=\(requiresAX), isFullscreenWindow=\(isFullscreenWindow)")
            
            // If the target window is on a different space, switch to its space first so AX APIs can access it.
            if requiresAX,
               let manager = AppDelegate.shared.spaceManager,
               SpaceHelper.getCurrentSpaceID(for: windowDisplayID) != windowSpaceID,
               let spaceObj = manager.spaceNameDict.first(where: { $0.id == windowSpaceID }) {
                manager.switchToSpace(spaceObj, forceInstant: true, isManual: false)
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
                    var closeButtonRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(targetAXWindow, kAXCloseButtonAttribute as CFString, &closeButtonRef) == .success,
                       let closeButton = closeButtonRef,
                       CFGetTypeID(closeButton) == AXUIElementGetTypeID() {
                        AXUIElementPerformAction(closeButton as! AXUIElement, kAXPressAction as CFString)
                    }
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
                moveSucceeded = await WindowActionCoordinator.moveWindow(
                    windowID: window.id,
                    pid: window.pid,
                    fromSpaceID: window.space.id,
                    targetSpaceID: space.id,
                    wasMinimized: window.isMinimized,
                    wasHidden: window.isHidden
                )
                if moveSucceeded {
                    await WindowActionCoordinator.waitForMoveToSettle(
                        isFullscreen: isFullscreenWindow
                    )
                }
            case .move(let space):
                if window.space.id != space.id {
                    moveSucceeded = await WindowActionCoordinator.moveWindow(
                        windowID: window.id,
                        pid: window.pid,
                        fromSpaceID: window.space.id,
                        targetSpaceID: space.id,
                        wasMinimized: window.isMinimized,
                        wasHidden: window.isHidden
                    )
                    if moveSucceeded {
                        await WindowActionCoordinator.waitForMoveToSettle(
                            isFullscreen: isFullscreenWindow
                        )
                    }
                }
            }

            guard moveSucceeded else {
                DiagnosticEventLog.shared.record(
                    subsystem: "Launcher",
                    level: "warning",
                    "executeActionImmediately: move failed; leaving original Spaces untouched for window \(window.id)"
                )
                HUDWindowController.shared.show(
                    message: commandKActionMessage(
                        for: actionType,
                        appName: appName,
                        succeeded: false
                    ),
                    style: .failure
                )
                return
            }
            
            // Return to original space after actions that needed a temporary switch.
            // Quitting an app does not require visiting its space, so preserve the
            // user's current space for quit actions.
            if actionType != .quit,
               let manager = AppDelegate.shared.spaceManager,
               manager.returnToOriginalAfterBatchMove {
                if !originalSpacesByDisplay.isEmpty {
                    await WindowActionCoordinator.restoreOriginalSpaces(originalSpacesByDisplay, using: manager)
                } else if let originalUUID = originalSpaceUUID,
                          let targetSpace = manager.spaceNameDict.first(where: {
                              $0.id == originalUUID && $0.displayID == windowDisplayID
                          }),
                          SpaceHelper.getCurrentSpaceID(for: windowDisplayID) != originalUUID {
                    manager.switchToSpace(targetSpace, forceInstant: true, isManual: false)
                }
            }

            HUDWindowController.shared.show(
                message: commandKActionMessage(
                    for: actionType,
                    appName: appName,
                    succeeded: true
                ),
                style: .success
            )
            
            await MainActor.run {
                self.loadData()
            }
        }
    }

    private func commandKActionMessage(
        for actionType: BatchStagedActionType,
        appName: String,
        succeeded: Bool
    ) -> String {
        switch actionType {
        case .move(let space), .restoreTo(let space):
            if succeeded {
                return String(format: String(localized: "Moved %@ to %@"), appName, space.name)
            }
            return String(format: String(localized: "Could not move %@ to %@"), appName, space.name)
        case .close:
            if succeeded {
                return String(format: String(localized: "Closed %@"), appName)
            }
            return String(format: String(localized: "Could not close %@"), appName)
        case .minimize:
            if succeeded {
                return String(format: String(localized: "Minimized %@"), appName)
            }
            return String(format: String(localized: "Could not minimize %@"), appName)
        case .hide:
            if succeeded {
                return String(format: String(localized: "Hidden %@"), appName)
            }
            return String(format: String(localized: "Could not hide %@"), appName)
        case .enterFullScreen:
            if succeeded {
                return String(format: String(localized: "Entered Full Screen for %@"), appName)
            }
            return String(format: String(localized: "Could not enter Full Screen for %@"), appName)
        case .exitFullScreen:
            if succeeded {
                return String(format: String(localized: "Exited Full Screen for %@"), appName)
            }
            return String(format: String(localized: "Could not exit Full Screen for %@"), appName)
        case .quit:
            if succeeded {
                return String(format: String(localized: "Quit %@"), appName)
            }
            return String(format: String(localized: "Could not quit %@"), appName)
        case .restore:
            if succeeded {
                return String(format: String(localized: "Restored %@"), appName)
            }
            return String(format: String(localized: "Could not restore %@"), appName)
        }
    }
}
