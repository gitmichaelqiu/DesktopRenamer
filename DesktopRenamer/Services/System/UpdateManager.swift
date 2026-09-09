import Foundation
import AppKit
import Sparkle

extension NSApplication {
    // Resolves the most appropriate window for presenting sheet-modal interfaces.
    var suitableSheetWindow: NSWindow? {
        suitableSheetWindow(nil)
    }

    func suitableSheetWindow(_ preferred: NSWindow?) -> NSWindow? {
        if let w = preferred, w.isVisible { return w }

        return keyWindow
            ?? mainWindow
            ?? windows.first { $0.isVisible && $0.isKeyWindow }
            ?? windows.first { $0.isVisible }
            ?? windows.first
    }
}

class UpdateManager: NSObject, SPUStandardUserDriverDelegate, SPUUpdaterDelegate {
    static let shared = UpdateManager()
    
    var updaterController: SPUStandardUpdaterController!
    
    private override init() {
        super.init()
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        guard DesktopRenamerIdentity.isCurrentApplication else {
            return []
        }

        return [DesktopRenamerIdentity.currentUpdateChannel]
    }

    func bestValidUpdate(in appcast: SUAppcast, for updater: SPUUpdater) -> SUAppcastItem? {
        guard DesktopRenamerIdentity.isCurrentApplication else {
            return nil
        }

        let eligibleItems = appcast.items.filter { item in
            item.propertiesDictionary[DesktopRenamerIdentity.appcastTargetBundleIdentifierKey] as? String
                == DesktopRenamerIdentity.currentBundleIdentifier
        }

        guard !eligibleItems.isEmpty else {
            return SUAppcastItem.empty()
        }

        let comparator = SUStandardVersionComparator.default
        return eligibleItems.max { left, right in
            comparator.compareVersion(left.versionString, toVersion: right.versionString) == .orderedAscending
        }
    }
    
    var supportsGentleScheduledUpdateReminders: Bool {
        return true
    }
    
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        return true
    }
}
