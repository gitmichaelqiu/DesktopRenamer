import Foundation
import AppKit

class MoveWindowNextCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "info", "Command performed: MoveWindowNextCommand")
        guard isAPIEnabled() else { return nil }
        guard runOnMain({ AppDelegate.shared.spaceManager != nil }) else {
            _ = failAppUnavailable()
            return nil
        }
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
        guard runOnMain({ AppDelegate.shared.spaceManager != nil }) else {
            _ = failAppUnavailable()
            return nil
        }
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
        guard let spaceID = requiredDirectString(parameter: "space ID") else { return nil }
        guard let manager = runOnMain({ AppDelegate.shared.spaceManager }) else {
            _ = failAppUnavailable()
            return nil
        }
        guard runOnMain({ manager.spaceNameDict.contains(where: { $0.id == spaceID }) }) else {
            _ = failInvalidArgument("Invalid space ID.")
            return nil
        }
        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "info", "Command performed: MoveWindowToSpaceCommand (spaceID: \(spaceID))")
        
        DispatchQueue.main.async {
            manager.moveActiveWindowToSpace(id: spaceID)
        }
        return nil
    }
}

class ReloadSpaceLabelsCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "info", "Command performed: ReloadSpaceLabelsCommand")
        guard isAPIEnabled() else { return false }
        return runOnMain {
            guard let manager = AppDelegate.shared.statusBarController?.labelManager else {
                _ = failAppUnavailable()
                return nil
            }
            manager.reloadAllWindows()
            return true
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
        
        guard let (spaces, names) = data else {
            _ = failAppUnavailable()
            return nil
        }
        
        // Perform heavy window enumeration on the background thread (NSScriptCommand defaults to background).
        return SpaceHelper.getWindowsForAllSpaces(spaces: spaces, spaceNames: names)
    }
}

class FocusWindowCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard isAPIEnabled() else { return nil }
        guard let windowIDStr = requiredPositiveIntegerString(directParameter, parameter: "window ID"),
              let windowID = Int(windowIDStr),
              let pidStr = requiredProcessIDString(evaluatedArguments?["ownerPID"], parameter: "owner PID"),
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
        guard let windowIDStr = requiredPositiveIntegerString(directParameter, parameter: "window ID"),
              let windowID = Int(windowIDStr),
              let fromSpaceStr = requiredArgumentString("fromSpace"),
              let targetSpaceStr = requiredArgumentString("targetSpace")
        else { return nil }
        let arguments = evaluatedArguments ?? [:]
        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "info", "Command performed: MoveSpecificWindowToSpaceCommand (windowID: \(windowIDStr), fromSpace: \(fromSpaceStr), targetSpace: \(targetSpaceStr))")

        if let pidValue = arguments["ownerPID"] {
            guard let pidStr = requiredProcessIDString(pidValue, parameter: "owner PID"),
                  let pid = Int32(pidStr) else { return nil }
            Task { @MainActor in
                await WindowActionCoordinator.moveWindow(
                    windowID: windowID,
                    pid: pid,
                    fromSpaceID: fromSpaceStr,
                    targetSpaceID: targetSpaceStr
                )
            }
        } else if let fromSpaceID = Int(fromSpaceStr),
                  let targetSpaceID = Int(targetSpaceStr) {
            DispatchQueue.main.async {
                SpaceHelper.moveWindowToSpace(windowID: windowID, fromSpaceID: fromSpaceID, targetSpaceID: targetSpaceID)
            }
        } else {
            failInvalidArgument("Space IDs must be integer values when owner PID is omitted.")
            return nil
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
        guard let windowIDStr = requiredPositiveIntegerString(directParameter, parameter: "window ID"),
              let windowID = Int(windowIDStr),
              let pidStr = requiredProcessIDString(evaluatedArguments?["ownerPID"], parameter: "owner PID"),
              let pid = Int32(pidStr),
              let actionName = requiredArgumentString("actionName")
        else { return nil }
        guard DesktopRenamerAPIContract.windowActionNames.contains(actionName) else {
            _ = failInvalidArgument("Unsupported window action: \(actionName)")
            return nil
        }
        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "info", "Command performed: ExecuteWindowActionCommand (windowID: \(windowIDStr), pid: \(pidStr), actionName: \(actionName))")
        
        // Raycast restores the original desktop after this command completes.
        // Wait for the main-actor action to finish so that restoration cannot
        // race the delayed switch to the window's space.
        let completion = DispatchSemaphore(value: 0)
        Task { @MainActor in
            defer { completion.signal() }
            await executeActionAsync(windowID: windowID, pid: pid, actionName: actionName)
        }
        waitForCompletion(completion)
        return true
    }

    private func waitForCompletion(_ completion: DispatchSemaphore) {
        guard Thread.isMainThread else {
            completion.wait()
            return
        }

        // NSScriptCommand may be invoked on the main thread. Pump the run loop
        // while the main-actor task performs its asynchronous settling delays.
        while completion.wait(timeout: .now()) == .timedOut {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
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
                    // The Core Foundation type check guarantees this bridge.
                    let closeButtonElement = closeButton as! AXUIElement
                    AXUIElementPerformAction(closeButtonElement, kAXPressAction as CFString)
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
