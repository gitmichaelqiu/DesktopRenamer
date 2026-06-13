import Foundation
import AppKit

// Resolves MainActor isolation for NSScriptCommand implementation.
// Note: Explicitly enters actor context to satisfy concurrency requirements.
func runOnMain<T>(_ block: @MainActor () -> T) -> T {
    if Thread.isMainThread {
        return MainActor.assumeIsolated(block)
    } else {
        return DispatchQueue.main.sync {
            return MainActor.assumeIsolated(block)
        }
    }
}

extension NSScriptCommand {
    func isAPIEnabled() -> Bool {
        if !SpaceManager.isAPIEnabled {
            self.scriptErrorNumber = -1
            self.scriptErrorString = "API Disabled"
            return false
        }
        return true
    }
}

class ToggleMenubarCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "info", "Command performed: ToggleMenubarCommand")
        guard isAPIEnabled() else { return false }
        return runOnMain {
            StatusBarController.toggleStatusBar()
            return !StatusBarController.isStatusBarHidden
        }
    }
}

class ToggleLauncherCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "info", "Command performed: ToggleLauncherCommand")
        guard isAPIEnabled() else { return false }
        return runOnMain {
            LauncherWindowController.shared.toggle()
            return LauncherWindowController.shared.window?.isVisible == true
        }
    }
}


class ToggleActiveLabelCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "info", "Command performed: ToggleActiveLabelCommand")
        guard isAPIEnabled() else { return false }
        return runOnMain {
            if let manager = AppDelegate.shared.statusBarController?.labelManager {
                manager.showActiveLabels.toggle()
                return manager.showActiveLabels
            }
            return false
        }
    }
}

class TogglePreviewLabelCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "info", "Command performed: TogglePreviewLabelCommand")
        guard isAPIEnabled() else { return false }
        return runOnMain {
            if let manager = AppDelegate.shared.statusBarController?.labelManager {
                manager.showPreviewLabels.toggle()
                return manager.showPreviewLabels
            }
            return false
        }
    }
}

class ToggleDesktopVisibilityCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "info", "Command performed: ToggleDesktopVisibilityCommand")
        guard isAPIEnabled() else { return false }
        return runOnMain {
            if let manager = AppDelegate.shared.statusBarController?.labelManager {
                // Toggles "Keep visible on desktop" (showOnDesktop).
                // Note: This modifies the user preference for visibility; it does not directly 
                // toggle the internal window pinning logic.
                manager.showOnDesktop.toggle()
                return manager.showOnDesktop
            }
            return false
        }
    }
}

class RenameCurrentSpaceCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard isAPIEnabled() else { return nil }
        guard let newName = self.directParameter as? String else { return nil }
        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "info", "Command performed: RenameCurrentSpaceCommand (newName: \(newName))")
        
        // No return value needed, so standard async is fine.
        DispatchQueue.main.async {
            if let manager = AppDelegate.shared.spaceManager {
                manager.renameSpace(manager.currentSpaceUUID, to: newName)
            }
        }
        return nil
    }
}

class GetCurrentSpaceNameCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "info", "Command performed: GetCurrentSpaceNameCommand")
        guard isAPIEnabled() else { return "API Disabled" }
        return runOnMain {
            if let manager = AppDelegate.shared.spaceManager {
                return manager.getSpaceName(manager.currentSpaceUUID)
            }
            return "Unknown"
        }
    }
}

class GetAllSpacesCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "info", "Command performed: GetAllSpacesCommand")
        guard isAPIEnabled() else { return "API Disabled" }
        return runOnMain {
            guard let manager = AppDelegate.shared.spaceManager else { return "" }
            
            // Format: "UUID|Name|DisplayID|Num"
            // Entries are grouped by display and sorted by displayID (UUID) and number.
            let sortedSpaces = manager.spaceNameDict.sorted {
                if $0.displayID != $1.displayID { return $0.displayID < $1.displayID }
                return $0.num < $1.num
            }
            
            // Format: "UUID~Name~DisplayID~Num~IsFullscreen"
            let lines = sortedSpaces.map { space in
                let name = manager.getSpaceName(space.id)
                // Retrieve the display label for the space's displayID
                let displayName = getDisplayName(for: space.displayID)
                
                // Return string split by ~ to prevent escaping issues.
                return "\(space.id)~\(name)~\(displayName)~\(space.num)~\(space.isFullscreen ? "1" : "0")"
            }
            return lines.joined(separator: "\n")
        }
    }
}

private func getDisplayName(for uuidString: String) -> String {
    for screen in NSScreen.screens {
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { continue }
        let uuidStr = CFUUIDCreateString(nil, uuid) as String
        if uuidStr == uuidString {
            return screen.localizedName
        }
    }
    // Fallback if not found (e.g. disconnected) or if main
    return "Display"
}

class SwitchToSpaceCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard isAPIEnabled() else { return nil }
        guard let spaceID = self.directParameter as? String else { return nil }
        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "info", "Command performed: SwitchToSpaceCommand (spaceID: \(spaceID))")
        
        DispatchQueue.main.async {
            if let manager = AppDelegate.shared.spaceManager {
                // Resolve space object by identifier.
                if let space = manager.spaceNameDict.first(where: { $0.id == spaceID }) {
                    manager.switchToSpace(space, forceInstant: true)
                }
            }
        }
        return nil
    }
}

class RenameSpaceCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard isAPIEnabled() else { return nil }
        guard let spaceID = self.directParameter as? String,
              let arguments = self.evaluatedArguments,
              let newName = arguments["newName"] as? String else { return nil }
        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "info", "Command performed: RenameSpaceCommand (spaceID: \(spaceID), newName: \(newName))")
        
        DispatchQueue.main.async {
            if let manager = AppDelegate.shared.spaceManager {
                manager.renameSpace(spaceID, to: newName)
            }
        }
        return nil
    }
}

class MoveWindowNextCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "info", "Command performed: MoveWindowNextCommand")
        guard isAPIEnabled() else { return nil }
        DispatchQueue.main.async {
            if let manager = AppDelegate.shared.spaceManager {
                manager.moveActiveWindowToNextSpace()
            }
        }
        return nil
    }
}

class MoveWindowPreviousCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "info", "Command performed: MoveWindowPreviousCommand")
        guard isAPIEnabled() else { return nil }
        DispatchQueue.main.async {
            if let manager = AppDelegate.shared.spaceManager {
                manager.moveActiveWindowToPreviousSpace()
            }
        }
        return nil
    }
}

class MoveWindowToSpaceCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard isAPIEnabled() else { return nil }
        guard let spaceID = self.directParameter as? String else { return nil }
        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "info", "Command performed: MoveWindowToSpaceCommand (spaceID: \(spaceID))")
        
        DispatchQueue.main.async {
            if let manager = AppDelegate.shared.spaceManager {
                manager.moveActiveWindowToSpace(id: spaceID)
            }
        }
        return nil
    }
}

class ReloadSpaceLabelsCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "info", "Command performed: ReloadSpaceLabelsCommand")
        guard isAPIEnabled() else { return false }
        return runOnMain {
            if let manager = AppDelegate.shared.statusBarController?.labelManager {
                manager.reloadAllWindows()
                return true
            }
            return false
        }
    }
}

class GetWindowsCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "info", "Command performed: GetWindowsCommand")
        guard isAPIEnabled() else { return "API Disabled" }
        
        // Fetch necessary space data on the main thread.
        let data: ([DesktopSpace], [String: String])? = runOnMain {
            guard let manager = AppDelegate.shared.spaceManager else { return nil }
            let spaces = manager.spaceNameDict
            var names: [String: String] = [:]
            for s in spaces {
                names[s.id] = manager.getSpaceName(s.id)
            }
            return (spaces, names)
        }
        
        guard let (spaces, names) = data else { return "" }
        
        // Perform heavy window enumeration on the background thread (NSScriptCommand defaults to background).
        return SpaceHelper.getWindowsForAllSpaces(spaces: spaces, spaceNames: names)
    }
}

class FocusWindowCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard isAPIEnabled() else { return nil }
        guard let windowIDStr = self.directParameter as? String,
              let windowID = Int(windowIDStr),
              let arguments = self.evaluatedArguments,
              let pidStr = arguments["ownerPID"] as? String,
              let pid = Int32(pidStr)
        else { return nil }
        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "info", "Command performed: FocusWindowCommand (windowID: \(windowIDStr), pid: \(pidStr))")

        DispatchQueue.main.async {
            SpaceHelper.focusWindow(id: windowID, pid: pid)
        }
        return nil
    }
}

class MoveSpecificWindowToSpaceCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard isAPIEnabled() else { return nil }
        guard let windowIDStr = self.directParameter as? String,
              let windowID = Int(windowIDStr),
              let arguments = self.evaluatedArguments,
              let fromSpaceStr = arguments["fromSpace"] as? String,
              let fromSpaceID = Int(fromSpaceStr),
              let targetSpaceStr = arguments["targetSpace"] as? String,
              let targetSpaceID = Int(targetSpaceStr)
        else { return nil }
        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "info", "Command performed: MoveSpecificWindowToSpaceCommand (windowID: \(windowIDStr), fromSpace: \(fromSpaceStr), targetSpace: \(targetSpaceStr))")

        DispatchQueue.main.async {
            SpaceHelper.moveWindowToSpace(windowID: windowID, fromSpaceID: fromSpaceID, targetSpaceID: targetSpaceID)
        }
        return nil
    }
}

class GetCurrentSpaceIDCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "info", "Command performed: GetCurrentSpaceIDCommand")
        guard isAPIEnabled() else { return "API Disabled" }
        return runOnMain {
            let ids = SpaceHelper.getCurrentSpaceIDs()
            return ids.joined(separator: ",")
        }
    }
}

class ExecuteWindowActionCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard isAPIEnabled() else { return nil }
        guard let windowIDStr = self.directParameter as? String,
              let windowID = Int(windowIDStr),
              let arguments = self.evaluatedArguments,
              let pidStr = arguments["ownerPID"] as? String,
              let pid = Int32(pidStr),
              let actionName = arguments["actionName"] as? String
        else { return nil }
        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "info", "Command performed: ExecuteWindowActionCommand (windowID: \(windowIDStr), pid: \(pidStr), actionName: \(actionName))")
        
        // Fire-and-forget: the command returns nil, so there is no need to block
        // the calling thread. All other AppleScript commands use the same pattern.
        Task { @MainActor in
            await executeActionAsync(windowID: windowID, pid: pid, actionName: actionName)
        }
        return nil
    }
    
    @MainActor
    private func executeActionAsync(windowID: Int, pid: Int32, actionName: String) async {
        let windowSpaceID = SpaceHelper.getWindowSpaceID(id: windowID)
        
        // Find if this space is fullscreen in SpaceManager
        var isFullscreenWindow = false
        if let spaceID = windowSpaceID,
           let manager = AppDelegate.shared.spaceManager,
           let spaceObj = manager.spaceNameDict.first(where: { $0.id == spaceID }) {
            isFullscreenWindow = spaceObj.isFullscreen
        }
        
        let requiresAX = (actionName == "close" || actionName == "minimize" || actionName == "enterFullScreen" || actionName == "exitFullScreen" || actionName == "restore" || (actionName == "hide" && isFullscreenWindow))
        
        // If target window is on a different space, switch to its space first so AX APIs can access it.
        if requiresAX,
           let spaceID = windowSpaceID,
           let manager = AppDelegate.shared.spaceManager,
           manager.currentSpaceUUID != spaceID,
           let spaceObj = manager.spaceNameDict.first(where: { $0.id == spaceID }) {
            manager.switchToSpace(spaceObj, forceInstant: true)
            try? await Task.sleep(nanoseconds: 600_000_000) // 0.6s settle time
        }
        
        // Un-fullscreen first if the window is currently fullscreen and the action requires it
        if isFullscreenWindow && (actionName == "close" || actionName == "minimize" || actionName == "hide") {
            var axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid)
            if axWindow == nil {
                if let app = NSRunningApplication(processIdentifier: pid) {
                    app.activate(options: .activateIgnoringOtherApps)
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid)
                }
            }
            if let targetAXWindow = axWindow {
                AXUIElementSetAttributeValue(targetAXWindow, "AXFullScreen" as CFString, false as CFTypeRef)
                try? await Task.sleep(nanoseconds: 1_200_000_000) // Wait for exit-fullscreen animation to settle
            }
        }
        
        switch actionName {
        case "close":
            var axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid)
            if axWindow == nil {
                if let app = NSRunningApplication(processIdentifier: pid) {
                    app.activate(options: .activateIgnoringOtherApps)
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid)
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
        case "minimize":
            var axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid)
            if axWindow == nil {
                if let app = NSRunningApplication(processIdentifier: pid) {
                    app.activate(options: .activateIgnoringOtherApps)
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid)
                }
            }
            if let targetAXWindow = axWindow {
                AXUIElementSetAttributeValue(targetAXWindow, kAXMinimizedAttribute as CFString, true as CFTypeRef)
            }
        case "hide":
            if let app = NSRunningApplication(processIdentifier: pid) {
                app.hide()
            }
        case "enterFullScreen":
            var axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid)
            if axWindow == nil {
                if let app = NSRunningApplication(processIdentifier: pid) {
                    app.activate(options: .activateIgnoringOtherApps)
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid)
                }
            }
            if let targetAXWindow = axWindow {
                AXUIElementSetAttributeValue(targetAXWindow, "AXFullScreen" as CFString, true as CFTypeRef)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        case "exitFullScreen":
            var axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid)
            if axWindow == nil {
                if let app = NSRunningApplication(processIdentifier: pid) {
                    app.activate(options: .activateIgnoringOtherApps)
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid)
                }
            }
            if let targetAXWindow = axWindow {
                AXUIElementSetAttributeValue(targetAXWindow, "AXFullScreen" as CFString, false as CFTypeRef)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        case "quit":
            if let app = NSRunningApplication(processIdentifier: pid) {
                app.terminate()
            }
        case "restore":
            if let app = NSRunningApplication(processIdentifier: pid) {
                app.unhide()
            }
            var axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid)
            if axWindow == nil {
                if let app = NSRunningApplication(processIdentifier: pid) {
                    app.activate(options: .activateIgnoringOtherApps)
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid)
                }
            }
            if let targetAXWindow = axWindow {
                AXUIElementSetAttributeValue(targetAXWindow, kAXMinimizedAttribute as CFString, false as CFTypeRef)
            }
        default:
            break
        }
        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms settle delay
    }
}
