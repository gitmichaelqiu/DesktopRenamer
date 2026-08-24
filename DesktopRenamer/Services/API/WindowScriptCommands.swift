import Foundation
import AppKit

private enum AppleScriptWindowActionSupport {
    static func wait(_ nanoseconds: UInt64, operation: String) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: nanoseconds)
            return true
        } catch {
            DiagnosticEventLog.shared.record(
                subsystem: "AppleScript",
                level: "info",
                "Cancelled while waiting to " + operation + "."
            )
            return false
        }
    }

    static func resolveWindow(windowID: Int, pid: Int32) async -> AXUIElement? {
        if let window = SpaceHelper.getAXWindow(id: windowID, pid: pid) {
            return window
        }

        guard let app = NSRunningApplication(processIdentifier: pid) else {
            return nil
        }
        app.activate(options: .activateIgnoringOtherApps)
        guard await wait(400_000_000, operation: "find the window") else {
            return nil
        }
        return SpaceHelper.getAXWindow(id: windowID, pid: pid)
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
        let data: ([DesktopSpace], [String: String], WindowEnumerationContext)? = runOnMain {
            guard let manager = AppDelegate.shared.spaceManager else { return nil }
            let spaces = manager.spaceNameDict
            var names: [String: String] = [:]
            for s in spaces {
                names[s.id] = manager.getSpaceName(s.id)
            }
            return (spaces, names, SpaceHelper.makeWindowEnumerationContext())
        }
        
        guard let (spaces, names, context) = data else { return "" }
        
        // Perform heavy window enumeration on the background thread (NSScriptCommand defaults to background).
        return SpaceHelper.getWindowSnapshots(spaces: spaces, spaceNames: names, context: context).map { space in
            var output = ">\(space.id)~\(space.name)~\(space.displayName)~\(space.num)~\(space.isFullscreen ? "1" : "0")~\(space.appPath ?? "")\n"
            for window in space.windows {
                output += "  \(window.id)|\(window.pid)|\(window.ownerName)|\(window.appPath)|\(window.title)|\(window.isMinimized ? "1" : "0")|\(window.isHidden ? "1" : "0")\n"
            }
            return output
        }.joined()
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
              let targetSpaceStr = arguments["targetSpace"] as? String
        else { return nil }
        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "info", "Command performed: MoveSpecificWindowToSpaceCommand (windowID: \(windowIDStr), fromSpace: \(fromSpaceStr), targetSpace: \(targetSpaceStr))")

        if let pidStr = arguments["ownerPID"] as? String,
           let pid = Int32(pidStr) {
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
            guard await AppleScriptWindowActionSupport.wait(600_000_000, operation: "switch to the window space") else {
                return
            }
        }
        
        // Un-fullscreen first if the window is currently fullscreen and the action requires it
        if isFullscreenWindow && (actionName == "close" || actionName == "minimize" || actionName == "hide") {
            guard let axWindow = await AppleScriptWindowActionSupport.resolveWindow(windowID: windowID, pid: pid),
                  SpaceHelper.performWindowAction(.exitFullScreen, on: axWindow),
                  await AppleScriptWindowActionSupport.wait(1_200_000_000, operation: "exit fullscreen") else {
                return
            }
        }
        
        switch actionName {
        case "close":
            guard let axWindow = await AppleScriptWindowActionSupport.resolveWindow(windowID: windowID, pid: pid),
                  SpaceHelper.performWindowAction(.close, on: axWindow) else {
                return
            }
        case "minimize":
            guard let axWindow = await AppleScriptWindowActionSupport.resolveWindow(windowID: windowID, pid: pid),
                  SpaceHelper.performWindowAction(.minimize, on: axWindow) else {
                return
            }
        case "hide":
            if let app = NSRunningApplication(processIdentifier: pid) {
                app.hide()
            }
        case "enterFullScreen":
            guard let axWindow = await AppleScriptWindowActionSupport.resolveWindow(windowID: windowID, pid: pid),
                  SpaceHelper.performWindowAction(.enterFullScreen, on: axWindow),
                  await AppleScriptWindowActionSupport.wait(1_000_000_000, operation: "enter fullscreen") else {
                return
            }
        case "exitFullScreen":
            guard let axWindow = await AppleScriptWindowActionSupport.resolveWindow(windowID: windowID, pid: pid),
                  SpaceHelper.performWindowAction(.exitFullScreen, on: axWindow),
                  await AppleScriptWindowActionSupport.wait(1_000_000_000, operation: "exit fullscreen") else {
                return
            }
        case "quit":
            if let app = NSRunningApplication(processIdentifier: pid) {
                app.terminate()
            }
        case "restore":
            if let app = NSRunningApplication(processIdentifier: pid) {
                app.unhide()
            }
            guard let axWindow = await AppleScriptWindowActionSupport.resolveWindow(windowID: windowID, pid: pid),
                  SpaceHelper.performWindowAction(.restore, on: axWindow) else {
                return
            }
        default:
            break
        }
        _ = await AppleScriptWindowActionSupport.wait(150_000_000, operation: "settle the window action")
    }
}
