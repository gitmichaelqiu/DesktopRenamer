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
        DispatchQueue.main.async {
            // This triggers the existing popover UI
            AppDelegate.shared.statusBarController?.renameCurrentSpace()
        }
        return nil
    }
}
