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

    @discardableResult
    func failInvalidArgument(_ message: String) -> Bool {
        scriptErrorNumber = -2
        scriptErrorString = message
        return false
    }

    @discardableResult
    func failAppUnavailable(_ message: String = "DesktopRenamer is not ready.") -> Bool {
        scriptErrorNumber = -3
        scriptErrorString = message
        return false
    }

    func requiredString(_ value: Any?, parameter: String) -> String? {
        guard let string = value as? String, !string.isEmpty else {
            failInvalidArgument("Parameter '\(parameter)' must be a non-empty text value.")
            return nil
        }
        return string
    }

    func requiredDirectString(parameter: String) -> String? {
        requiredString(directParameter, parameter: parameter)
    }

    func requiredArgumentString(_ parameter: String) -> String? {
        requiredString(evaluatedArguments?[parameter], parameter: parameter)
    }

    func requiredIntegerString(_ value: Any?, parameter: String) -> String? {
        guard let string = requiredString(value, parameter: parameter), Int(string) != nil else {
            if scriptErrorNumber == 0 {
                failInvalidArgument("Parameter '\(parameter)' must be an integer.")
            }
            return nil
        }
        return string
    }

    func requiredProcessIDString(_ value: Any?, parameter: String) -> String? {
        guard let string = requiredIntegerString(value, parameter: parameter),
              let pid = Int32(string), pid > 0 else {
            failInvalidArgument("Parameter '\(parameter)' must be a positive process ID.")
            return nil
        }
        return string
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

class ToggleLabelsCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "info", "Command performed: ToggleLabelsCommand")
        guard isAPIEnabled() else { return false }
        return runOnMain {
            guard let manager = AppDelegate.shared.statusBarController?.labelManager else {
                failAppUnavailable()
                return false
            }
            manager.showActiveLabels.toggle()
            manager.showPreviewLabels.toggle()
            return manager.showActiveLabels && manager.showPreviewLabels
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
            failAppUnavailable()
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
            failAppUnavailable()
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
            failAppUnavailable()
            return false
        }
    }
}

class RenameCurrentSpaceCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard isAPIEnabled() else { return nil }
        guard let newName = requiredDirectString(parameter: "name") else { return nil }
        guard runOnMain({ AppDelegate.shared.spaceManager != nil }) else {
            _ = failAppUnavailable()
            return nil
        }
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
            failAppUnavailable()
            return nil
        }
    }
}

class GetAPIVersionCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "info", "Command performed: GetAPIVersionCommand")
        guard isAPIEnabled() else { return "API Disabled" }
        return DesktopRenamerAPIVersion.current
    }
}

class GetAllSpacesCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "info", "Command performed: GetAllSpacesCommand")
        guard isAPIEnabled() else { return "API Disabled" }
        return runOnMain {
            guard let manager = AppDelegate.shared.spaceManager else {
                failAppUnavailable()
                return nil
            }
            
            // Format: "UUID|Name|DisplayID|Num"
            // Entries are grouped by display and sorted by displayID (UUID) and number.
            let sortedSpaces = manager.spaceNameDict.sorted {
                if $0.displayID != $1.displayID { return $0.displayID < $1.displayID }
                return $0.num < $1.num
            }
            
            // Format: "UUID~Name~DisplayID~Num~IsFullscreen~AppPath"
            let lines = sortedSpaces.map { space in
                let name = manager.getSpaceName(space.id)
                let displayName = getDisplayName(for: space.displayID)

                // Return string split by ~ to prevent escaping issues.
                return "\(space.id)~\(name)~\(displayName)~\(space.num)~\(space.isFullscreen ? "1" : "0")~\(space.appPath ?? "")"
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
        guard let spaceID = requiredDirectString(parameter: "space ID") else { return nil }
        guard let manager = runOnMain({ AppDelegate.shared.spaceManager }) else {
            _ = failAppUnavailable()
            return nil
        }
        guard runOnMain({ manager.spaceNameDict.contains(where: { $0.id == spaceID }) }) else {
            _ = failInvalidArgument("Invalid space ID.")
            return nil
        }
        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "info", "Command performed: SwitchToSpaceCommand (spaceID: \(spaceID))")
        
        DispatchQueue.main.async {
            // Resolve space object by identifier again because Mission Control
            // may have recreated the space between validation and dispatch.
            if let space = manager.spaceNameDict.first(where: { $0.id == spaceID }) {
                manager.switchToSpace(space, forceInstant: true)
            }
        }
        return nil
    }
}

class RearrangeSpaceCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard isAPIEnabled() else { return nil }
        guard let sourceID = requiredDirectString(parameter: "space ID"),
              let direction = requiredArgumentString("direction") else { return nil }

        let rearrangementDirection: DesktopRearrangementDirection
        switch direction.lowercased() {
        case "up":
            rearrangementDirection = .up
        case "down":
            rearrangementDirection = .down
        default:
            self.scriptErrorNumber = -2
            self.scriptErrorString = "Direction must be up or down"
            return nil
        }

        guard let manager = runOnMain({ AppDelegate.shared.spaceManager }) else {
            _ = failAppUnavailable()
            return nil
        }
        guard runOnMain({ manager.spaceNameDict.contains(where: { $0.id == sourceID }) }) else {
            _ = failInvalidArgument("Invalid space ID.")
            return nil
        }

        DiagnosticEventLog.shared.record(
            subsystem: "AppleScript",
            level: "info",
            "Command performed: RearrangeSpaceCommand (sourceID: \(sourceID), direction: \(direction))"
        )

        DispatchQueue.main.async {
            guard let sourceSpace = manager.spaceNameDict.first(where: { $0.id == sourceID }) else {
                DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "warning", "Space disappeared before rearrangement: \(sourceID)")
                return
            }

            let orderedSpaces = manager.spaceNameDict
                .filter {
                    $0.displayID == sourceSpace.displayID && (sourceSpace.isFullscreen || !$0.isFullscreen)
                }
                .sorted { $0.num < $1.num }
            let orderedIDs = orderedSpaces.map(\.id)
            guard let sourceIndex = orderedIDs.firstIndex(of: sourceID) else {
                DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "warning", "Space is not rearrangeable: \(sourceID)")
                return
            }

            switch rearrangementDirection {
            case .up:
                guard sourceIndex > 0 else {
                    DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "warning", "Space is already first: \(sourceID)")
                    return
                }
                SpaceRearrangementService.shared.rearrange(
                    sourceID: sourceID,
                    before: orderedIDs[sourceIndex - 1],
                    orderedSpaceIDs: orderedIDs,
                    displayID: sourceSpace.displayID
                ) { result in
                    if case .failure(let message) = result {
                        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "warning", message)
                    }
                    manager.refreshSpaceState()
                }
            case .down:
                guard sourceIndex < orderedIDs.count - 1 else {
                    DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "warning", "Space is already last: \(sourceID)")
                    return
                }
                let completion: (SpaceRearrangementService.Result) -> Void = { result in
                    if case .failure(let message) = result {
                        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "warning", message)
                    }
                    manager.refreshSpaceState()
                }
                if sourceIndex + 2 < orderedIDs.count {
                    SpaceRearrangementService.shared.rearrange(
                        sourceID: sourceID,
                        before: orderedIDs[sourceIndex + 2],
                        orderedSpaceIDs: orderedIDs,
                        displayID: sourceSpace.displayID,
                        completion: completion
                    )
                } else {
                    SpaceRearrangementService.shared.rearrangeToEnd(
                        sourceID: sourceID,
                        orderedSpaceIDs: orderedIDs,
                        displayID: sourceSpace.displayID,
                        completion: completion
                    )
                }
            }
        }
        return nil
    }
}

class RenameSpaceCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard isAPIEnabled() else { return nil }
        guard let spaceID = requiredDirectString(parameter: "space ID"),
              let newName = requiredArgumentString("newName") else { return nil }
        guard let manager = runOnMain({ AppDelegate.shared.spaceManager }) else {
            _ = failAppUnavailable()
            return nil
        }
        guard runOnMain({ manager.spaceNameDict.contains(where: { $0.id == spaceID }) }) else {
            _ = failInvalidArgument("Invalid space ID.")
            return nil
        }
        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "info", "Command performed: RenameSpaceCommand (spaceID: \(spaceID), newName: \(newName))")
        
        DispatchQueue.main.async {
            manager.renameSpace(spaceID, to: newName)
        }
        return nil
    }
}
