import Foundation
import AppKit

// Helper to safely execute MainActor logic from NSScriptCommand
// This satisfies the compiler by explicitly entering the actor context
func runOnMain<T>(_ block: @MainActor () -> T) -> T {
    if Thread.isMainThread {
        return MainActor.assumeIsolated(block)
    } else {
        return DispatchQueue.main.sync {
            return MainActor.assumeIsolated(block)
        }
    }
}

class ToggleMenubarCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        return runOnMain {
            StatusBarController.toggleStatusBar()
            return !StatusBarController.isStatusBarHidden
        }
    }
}

class ToggleLabelsCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        return runOnMain {
            if let manager = AppDelegate.shared.statusBarController?.labelManager {
                manager.toggleEnabled()
                return manager.isEnabled
            }
            return false
        }
    }
}

class ToggleActiveLabelCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
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
        return runOnMain {
            if let manager = AppDelegate.shared.statusBarController?.labelManager {
                // Toggles "Keep visible on desktop" (showOnDesktop)
                // This does NOT toggle the internal window pinning/docking logic directly,
                // just the user preference for visibility.
                manager.showOnDesktop.toggle()
                return manager.showOnDesktop
            }
            return false
        }
    }
}

class RenameCurrentSpaceCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let newName = self.directParameter as? String else { return nil }
        
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
        return runOnMain {
            guard let manager = AppDelegate.shared.spaceManager else { return "" }
            
            // Format: "UUID|Name|DisplayID|Num"
            // We want to group by Display. To make specific displays contiguous, we sort by UUID (or Name).
            // Sorting by displayID (UUID) matches previous behavior.
            let sortedSpaces = manager.spaceNameDict.sorted {
                if $0.displayID != $1.displayID { return $0.displayID < $1.displayID }
                return $0.num < $1.num
            }
            
            let lines = sortedSpaces.map { space in
                let name = manager.getSpaceName(space.id)
                // Resolve Display Name from UUID
                let displayName = getDisplayName(for: space.displayID)
                return "\(space.id)|\(name)|\(displayName)|\(space.num)"
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
        guard let spaceID = self.directParameter as? String else { return nil }
        
        DispatchQueue.main.async {
            if let manager = AppDelegate.shared.spaceManager {
                // Find the space object
                if let space = manager.spaceNameDict.first(where: { $0.id == spaceID }) {
                    manager.switchToSpace(space)
                }
            }
        }
        return nil
    }
}

class RenameSpaceCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let spaceID = self.directParameter as? String,
              let arguments = self.evaluatedArguments,
              let newName = arguments["newName"] as? String else { return nil }
        
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
        guard let spaceID = self.directParameter as? String else { return nil }
        
        DispatchQueue.main.async {
            if let manager = AppDelegate.shared.spaceManager {
                manager.moveActiveWindowToSpace(id: spaceID)
            }
        }
        return nil
    }
}
