import AppKit
import Foundation
import SwiftUI
import WidgetKit

extension SpaceManager {

    // MARK: - Diagnostic Report Accessors

    /// Returns a human-readable description of the last wake time, including
    /// remaining cooling time if we are still in the post-wake stabilization window.
    var lastWakeTimeAgo: String {
        let elapsed = Date().timeIntervalSince(lastWakeTime)
        if elapsed < wakeCoolingDuration {
            let remaining = wakeCoolingDuration - elapsed
            return "cooling (\(String(format: "%.1f", remaining))s remaining, started \(String(format: "%.1f", elapsed))s ago)"
        }
        return "\(String(format: "%.1f", elapsed))s ago"
    }

    /// Space change retry count / max for diagnostic reports.
    var spaceChangeRetryInfo: String {
        "\(spaceChangeRetryCount)/\(maxSpaceChangeRetries)"
    }

    /// Fullscreen exit retry set contents for diagnostic reports.
    var fullscreenExitRetryingInfo: String {
        fullscreenExitRetrying.isEmpty ? "(empty)" : fullscreenExitRetrying.sorted().joined(separator: ", ")
    }

    /// Connected display UUIDs for diagnostic reports.
    var connectedDisplayUUIDsInfo: String {
        connectedDisplayUUIDs.isEmpty ? "(none)" : connectedDisplayUUIDs.sorted().joined(separator: ", ")
    }

    /// Last manual switch target space UUID for diagnostic reports.
    var lastManualSwitchTargetUUIDInfo: String {
        lastManualSwitchTargetUUID ?? "nil"
    }

    private func pruneStaleMovedWindows() {
        guard !SpaceHelper.isDragging else { return }
        var staleKeys: [Int] = []
        for (windowID, entry) in movedWindowsOriginalSpaces {
            guard let actualCgsSpaceID = SpaceHelper.getWindowSpaceID(id: windowID) else {
                staleKeys.append(windowID)
                continue
            }
            if actualCgsSpaceID != entry.currentSpaceUUID {
                print("SpaceManager: Pruning window \(windowID) from restore queue — expected \(entry.currentSpaceUUID), actual \(actualCgsSpaceID)")
                staleKeys.append(windowID)
            }
        }
        for key in staleKeys {
            movedWindowsOriginalSpaces.removeValue(forKey: key)
        }
    }

    func restoreAllMovedWindows() {
        pruneStaleMovedWindows()
        let list = movedWindowsOriginalSpaces.map { (windowID: $0.key, originalSpaceUUID: $0.value.originalSpaceUUID, currentSpaceUUID: $0.value.currentSpaceUUID, pid: $0.value.pid) }
        guard !list.isEmpty else { return }
        
        let initialSpaceUUID = self.currentSpaceUUID
        restoreNextWindow(index: 0, list: list, initialSpaceUUID: initialSpaceUUID)
    }
    
    private func restoreNextWindow(index: Int, list: [(windowID: Int, originalSpaceUUID: String, currentSpaceUUID: String, pid: Int32)], initialSpaceUUID: String) {
        if index >= list.count {
            // All windows restored! Switch back to the user's initial space instantly after a short delay
            // to allow the last programmatic drag and OS space change state to fully settle.
            if let initialSpaceObj = self.spaceNameDict.first(where: { $0.id == initialSpaceUUID }) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    print("SpaceManager: All restorations complete. Switching back to initial space \(initialSpaceUUID)")
                    self?.switchToSpace(initialSpaceObj, forceInstant: true, isManual: true)
                }
            }
            return
        }
        
        let item = list[index]
        print("SpaceManager: Restoring window \(item.windowID) from \(item.currentSpaceUUID) back to \(item.originalSpaceUUID)")
        
        // 1. Switch to the window's current space instantly to grab it
        if let currentSpaceObj = self.spaceNameDict.first(where: { $0.id == item.currentSpaceUUID }) {
            self.switchToSpace(currentSpaceObj, forceInstant: true, isManual: false)
            
            // 2. Wait 600ms for the space switch to finish, focus the window, and drag it to originalSpaceUUID
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.60) { [weak self] in
                SpaceHelper.focusWindow(id: item.windowID, pid: item.pid)
                
                // Wait 250ms for the window to raise/focus
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    SpaceHelper.dragActiveWindow(to: item.originalSpaceUUID, forceInstant: true)
                    self?.movedWindowsOriginalSpaces.removeValue(forKey: item.windowID)
                    
                    // 3. Wait 500ms for the drag-move operation to fully complete before starting the next one!
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.50) {
                        self?.restoreNextWindow(index: index + 1, list: list, initialSpaceUUID: initialSpaceUUID)
                    }
                }
            }
        } else {
            // Space not found, skip this one
            self.restoreNextWindow(index: index + 1, list: list, initialSpaceUUID: initialSpaceUUID)
        }
    }
}
