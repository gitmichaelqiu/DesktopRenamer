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
