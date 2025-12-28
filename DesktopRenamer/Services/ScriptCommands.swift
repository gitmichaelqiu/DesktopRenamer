import Foundation
import AppKit

class ToggleMenubarCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        DispatchQueue.main.async {
            StatusBarController.toggleStatusBar()
        }
        return nil
    }
}

class ToggleLabelsCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        DispatchQueue.main.async {
            AppDelegate.shared.statusBarController?.labelManager.toggleEnabled()
        }
        return nil
    }
}

class ToggleActiveLabelCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        DispatchQueue.main.async {
            guard let manager = AppDelegate.shared.statusBarController?.labelManager else { return }
            manager.showActiveLabels.toggle()
        }
        return nil
    }
}

class TogglePreviewLabelCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        DispatchQueue.main.async {
            guard let manager = AppDelegate.shared.statusBarController?.labelManager else { return }
            manager.showPreviewLabels.toggle()
        }
        return nil
    }
}

class ToggleDesktopVisibilityCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        DispatchQueue.main.async {
            guard let manager = AppDelegate.shared.statusBarController?.labelManager else { return }
            manager.showOnDesktop.toggle()
        }
        return nil
    }
}

class RenameCurrentSpaceCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        // 1. Get the text passed from Raycast
        guard let newName = self.directParameter as? String else { return nil }
        
        DispatchQueue.main.async {
            // 2. Access SpaceManager directly
            if let manager = AppDelegate.shared.spaceManager {
                // 3. Rename silently without triggering UI
                manager.renameSpace(manager.currentSpaceUUID, to: newName)
            }
        }
        return nil
    }
}
