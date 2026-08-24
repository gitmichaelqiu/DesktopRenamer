import AppKit
import Foundation
import SwiftUI
import WidgetKit

extension SpaceManager {

    // MARK: - Move Window Functions
    
    func moveActiveWindowToNextSpace() {
        // Determine window and display context.
        guard let frame = SpaceHelper.getActiveWindowFrame() else {
            moveActiveWindowToNextSpaceLegacy()
            return
        }
        
        let displayID = SpaceHelper.getWindowDisplayID(for: frame) ?? self.currentDisplayID
        let currentSpaceID = SpaceHelper.getCurrentSpaceID(for: displayID) ?? self.currentSpaceUUID
        
        // Resolve space objects for the specific display.
        // Robustness: If the exact ID doesn't match, we fallback to finding any space on this display that's marked current.
        let spaceList = spaceNameDict
            .filter { $0.displayID == displayID }
            .sorted { $0.num < $1.num }
        
        guard !spaceList.isEmpty else {
            // Fallback: If no spaces for this display ID, maybe the display ID is wrong?
            // Try global search for the space ID.
            moveActiveWindowToNextSpaceLegacy()
            return
        }
        
        guard let current = spaceList.first(where: { $0.id == currentSpaceID }) else {
            // Fallback: try to guess current if the ID mismatch persists
            moveActiveWindowToNextSpaceLegacy()
            return
        }
        
        // Target the next available space.
        guard let currentIndex = spaceList.firstIndex(of: current),
              currentIndex < spaceList.count - 1 else { return }
        
        let target = spaceList[currentIndex + 1]
        SpaceHelper.dragActiveWindow(to: target.id, forceInstant: true)
    }

    private func moveActiveWindowToNextSpaceLegacy() {
        let displayID = SpaceHelper.getCursorDisplayID() ?? self.currentDisplayID
        let currentSpaceID = SpaceHelper.getCurrentSpaceID(for: displayID) ?? self.currentSpaceUUID
        
        let spaceList = spaceNameDict
            .filter { $0.displayID == displayID }
            .sorted { $0.num < $1.num }
        
        guard let current = spaceList.first(where: { $0.id == currentSpaceID }) else { return }
        guard let currentIndex = spaceList.firstIndex(of: current),
              currentIndex < spaceList.count - 1 else { return }
        
        let target = spaceList[currentIndex + 1]
        SpaceHelper.dragActiveWindow(to: target.id, forceInstant: true)
    }
    
    func moveActiveWindowToPreviousSpace() {
        guard let frame = SpaceHelper.getActiveWindowFrame() else {
            moveActiveWindowToPreviousSpaceLegacy()
            return
        }
        
        let displayID = SpaceHelper.getWindowDisplayID(for: frame) ?? self.currentDisplayID
        let currentSpaceID = SpaceHelper.getCurrentSpaceID(for: displayID) ?? self.currentSpaceUUID
        
        let spaceList = spaceNameDict
            .filter { $0.displayID == displayID }
            .sorted { $0.num < $1.num }
        
        guard !spaceList.isEmpty else {
            moveActiveWindowToPreviousSpaceLegacy()
            return
        }
        
        guard let current = spaceList.first(where: { $0.id == currentSpaceID }) else {
            moveActiveWindowToPreviousSpaceLegacy()
            return
        }
        
        guard let currentIndex = spaceList.firstIndex(of: current),
              currentIndex > 0 else { return }
        
        let target = spaceList[currentIndex - 1]
        SpaceHelper.dragActiveWindow(to: target.id, forceInstant: true)
    }

    private func moveActiveWindowToPreviousSpaceLegacy() {
        let displayID = SpaceHelper.getCursorDisplayID() ?? self.currentDisplayID
        let currentSpaceID = SpaceHelper.getCurrentSpaceID(for: displayID) ?? self.currentSpaceUUID
        
        let spaceList = spaceNameDict
            .filter { $0.displayID == displayID }
            .sorted { $0.num < $1.num }
        
        guard let current = spaceList.first(where: { $0.id == currentSpaceID }) else { return }
        guard let currentIndex = spaceList.firstIndex(of: current),
              currentIndex > 0 else { return }
        
        let target = spaceList[currentIndex - 1]
        SpaceHelper.dragActiveWindow(to: target.id, forceInstant: true)
    }
    
    func moveActiveWindowToSpace(number: Int) {
        if let target = spaceNameDict.first(where: { $0.num == number && $0.displayID == currentDisplayID }) {
            // BUG FIX: Prevent redundant move attempts if the target is already current.
            if target.id == currentSpaceUUID { return }
            SpaceHelper.dragActiveWindow(to: target.id, forceInstant: true)
        }
    }
    
    func switchToSpace(number: Int) {
        if let target = spaceNameDict.first(where: { $0.num == number && $0.displayID == currentDisplayID }) {
            switchToSpace(target)
        }
    }
    
    func moveActiveWindowToSpace(id: String) {
        guard let targetSpace = spaceNameDict.first(where: { $0.id == id }), !targetSpace.isFullscreen else {
            return
        }

        // The global current-space ID belongs to whichever display most
        // recently reported a transition. It cannot be used to decide whether
        // a window on another display is already in the target space.
        if let windowInfo = SpaceHelper.getActiveWindowInfo(),
           let sourceDisplayID = SpaceHelper.getWindowDisplayID(for: windowInfo.frame),
           sourceDisplayID == targetSpace.displayID,
           SpaceHelper.getCurrentSpaceID(for: sourceDisplayID) == id {
            return
        }

        // Un-fullscreen first if current space is fullscreen
        if let currentSpaceObj = spaceNameDict.first(where: { $0.id == currentSpaceUUID }), currentSpaceObj.isFullscreen {
            // Guard against unbounded recursive retry: if the AX exit is silently
            // ignored (sandboxed app, slow animation) we would loop forever.
            guard fullscreenExitRetrying.insert(id).inserted else { return }

            if let windowInfo = SpaceHelper.getActiveWindowInfo() {
                if let axWindow = SpaceHelper.getAXWindow(id: windowInfo.id, pid: windowInfo.pid) {
                    AXUIElementSetAttributeValue(axWindow, "AXFullScreen" as CFString, false as CFTypeRef)
                    // Wait for the exit-fullscreen animation to complete
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                        self?.fullscreenExitRetrying.remove(id)
                        self?.moveActiveWindowToSpace(id: id)
                    }
                    return
                }
            }
            fullscreenExitRetrying.remove(id)
        }

        // Robust Cross-Monitor Support: 
        // If the target space is on a different monitor, we use the direct CGS+AX move method
        // since the "swipe while dragging" gesture is limited to a single display.
        if let windowInfo = SpaceHelper.getActiveWindowInfo() {
            let sourceDisplayID = SpaceHelper.getWindowDisplayID(for: windowInfo.frame)
            if let sourceDisplay = sourceDisplayID, sourceDisplay != targetSpace.displayID {
                print("SpaceManager: Cross-monitor move requested (\(sourceDisplay) -> \(targetSpace.displayID)). Using robust method.")
                
                let fromSpaceID = Int(SpaceHelper.getCurrentSpaceID(for: sourceDisplay) ?? "0") ?? 0
                let targetSpaceID = Int(targetSpace.id) ?? 0
                
                // Activate the destination display's space before the direct
                // CGS assignment. The helper also performs this preflight for
                // API callers that do not go through this method.
                self.switchToSpace(targetSpace, forceInstant: true)
                SpaceHelper.moveWindowToSpace(windowID: windowInfo.id, fromSpaceID: fromSpaceID, targetSpaceID: targetSpaceID)
                return
            }
        }
        
        SpaceHelper.dragActiveWindow(to: id, forceInstant: true)
    }

    func isFirstSpace(onDisplayID displayID: String? = nil) -> Bool {
        var targetDisplayID = displayID
        var currentSpaceID = currentSpaceUUID
        
        if let requestedDisplayID = displayID {
            if let space = SpaceHelper.getCurrentSpaceID(for: requestedDisplayID) {
                currentSpaceID = space
                targetDisplayID = requestedDisplayID
            } else { return false }
        }
        
        guard let current = spaceNameDict.first(where: { $0.id == currentSpaceID }) else { return false }
        if targetDisplayID == nil { targetDisplayID = current.displayID }
        
        // Check manual filtering logic in displaySpaces
        let displaySpaces = spaceNameDict
            .filter { $0.displayID == targetDisplayID }
            .sorted { $0.num < $1.num }
            
        guard let currentIndex = displaySpaces.firstIndex(of: current) else { return false }
        return currentIndex == 0
    }
    
    func moveActiveWindowToNextDisplay() {
        moveActiveWindowToDisplay(offset: 1)
    }

    func moveActiveWindowToPreviousDisplay() {
        moveActiveWindowToDisplay(offset: -1)
    }

    private func moveActiveWindowToDisplay(offset: Int) {
        guard let windowInfo = SpaceHelper.getActiveWindowInfo() else { return }
        let sourceDisplayID = SpaceHelper.getWindowDisplayID(for: windowInfo.frame) ?? self.currentDisplayID
        
        let displayIDs = SpaceHelper.getAllDisplayUUIDs()
        guard displayIDs.count > 1 else { return }
        
        guard let currentIndex = displayIDs.firstIndex(of: sourceDisplayID) else { return }
        
        let targetIndex = (currentIndex + offset + displayIDs.count) % displayIDs.count
        let targetDisplayID = displayIDs[targetIndex]
        
        // Find the current space on the target display
        guard let targetSpaceIDStr = SpaceHelper.getCurrentSpaceID(for: targetDisplayID),
              let targetSpace = spaceNameDict.first(where: { $0.id == targetSpaceIDStr }) else { return }
        
        // Perform move using the robust cross-monitor logic
        let fromSpaceID = Int(SpaceHelper.getCurrentSpaceID(for: sourceDisplayID) ?? "0") ?? 0
        let targetSpaceID = Int(targetSpaceIDStr) ?? 0
        
        print("SpaceManager: Moving active window to display \(targetDisplayID)")
        SpaceHelper.moveWindowToSpace(windowID: windowInfo.id, fromSpaceID: fromSpaceID, targetSpaceID: targetSpaceID)
        
        // Switch to the target space to follow the window
        self.switchToSpace(targetSpace, forceInstant: true)
    }
    
    func isLastSpace(onDisplayID displayID: String? = nil) -> Bool {
        var targetDisplayID = displayID
        var currentSpaceID = currentSpaceUUID
        
        if let requestedDisplayID = displayID {
             if let space = SpaceHelper.getCurrentSpaceID(for: requestedDisplayID) {
                 currentSpaceID = space
                 targetDisplayID = requestedDisplayID
             } else { return false }
         }
         
         guard let current = spaceNameDict.first(where: { $0.id == currentSpaceID }) else { return false }
         if targetDisplayID == nil { targetDisplayID = current.displayID }
         
         let displaySpaces = spaceNameDict
             .filter { $0.displayID == targetDisplayID }
             .sorted { $0.num < $1.num }
             
         guard let currentIndex = displaySpaces.firstIndex(of: current) else { return false }
         return currentIndex == displaySpaces.count - 1
    }
}
