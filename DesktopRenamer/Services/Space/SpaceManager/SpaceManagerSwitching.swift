import AppKit
import Foundation
import SwiftUI
import WidgetKit

extension SpaceManager {

    // Space navigation and switching logic.
    func switchToSpace(_ space: DesktopSpace, forceInstant: Bool = false, isManual: Bool = true) {
        print("SpaceManager: switchToSpace(\(space.id)) on display \(space.displayID) forceInstant: \(forceInstant) isManual: \(isManual)")
        if isManual {
            self.lastManualSwitchTime = Date().timeIntervalSince1970
            self.lastManualSwitchTargetUUID = space.id
        }
        SpaceHelper.switchToSpace(space.id, forceInstant: forceInstant)
    }
    
    func switchToPreviousSpace(onDisplayID displayID: String? = nil, forceInstant: Bool? = nil) {
        let targetDisplayID = displayID ?? spaceNameDict.first(where: { $0.id == currentSpaceUUID })?.displayID ?? currentDisplayID
        if let current = findBestCurrentSpace(for: targetDisplayID) {
            proceedToSwitch(from: current, on: targetDisplayID, direction: -1, forceInstant: forceInstant ?? false)
        }
    }

    func switchToNextSpace(onDisplayID displayID: String? = nil, forceInstant: Bool? = nil) {
        let targetDisplayID = displayID ?? spaceNameDict.first(where: { $0.id == currentSpaceUUID })?.displayID ?? currentDisplayID
        if let current = findBestCurrentSpace(for: targetDisplayID) {
            proceedToSwitch(from: current, on: targetDisplayID, direction: 1, forceInstant: forceInstant ?? false)
        }
    }

    private func findBestCurrentSpace(for displayID: String) -> DesktopSpace? {
        // Identify the visible space for the specified monitor.
        if let liveID = SpaceHelper.getCurrentSpaceID(for: displayID),
           let space = spaceNameDict.first(where: { $0.id == liveID && $0.displayID == displayID }) {
            // Update cache while we're at it
            currentSpaceByDisplay[displayID] = liveID
            return space
        }

        // Fallback: check the per-display cache.
        if let cachedID = currentSpaceByDisplay[displayID],
           let space = spaceNameDict.first(where: { $0.id == cachedID && $0.displayID == displayID }) {
            return space
        }
        
        // Fallback: check if the globally focused space is on this display.
        if let global = spaceNameDict.first(where: { $0.id == currentSpaceUUID && $0.displayID == displayID }) {
            return global
        }
        
        // Fallback: default to the first available space on this monitor.
        return spaceNameDict.first(where: { $0.displayID == displayID })
    }

    private func proceedToSwitch(from current: DesktopSpace, on targetDisplayID: String, direction: Int, forceInstant: Bool = false) {
        // Use spaces from the TARGET display
        let displaySpaces = spaceNameDict
            .filter { $0.displayID == targetDisplayID }
            .sorted { $0.num < $1.num }
        
        guard let currentIndex = displaySpaces.firstIndex(of: current) else { return }
        
        let targetIndex = currentIndex + direction
        guard targetIndex >= 0 && targetIndex < displaySpaces.count else { return }
        
        let target = displaySpaces[targetIndex]
        switchToSpace(target, forceInstant: forceInstant)
    }
}
