import AppKit

@MainActor
enum WindowActionCoordinator {
    /// Selects the window's desktop before raising it. Focusing a window while
    /// its desktop is still in the background can make WindowServer restore the
    /// previous desktop, especially when the window is on another display.
    static func focusWindow(windowID: Int, pid: Int32, spaceID: String) async -> Bool {
        guard let manager = AppDelegate.shared.spaceManager,
              let space = manager.spaceNameDict.first(where: { $0.id == spaceID }) else {
            return false
        }

        if SpaceHelper.getCurrentSpaceID(for: space.displayID) != space.id {
            manager.switchToSpace(space, forceInstant: true, isManual: false)
            guard await waitForSpace(space.id, on: space.displayID) else {
                return false
            }
        }

        SpaceHelper.focusWindow(id: windowID, pid: pid)
        return true
    }

    @discardableResult
    static func moveWindow(
        windowID: Int,
        pid: Int32,
        fromSpaceID: String,
        targetSpaceID: String
    ) async -> Bool {
        guard fromSpaceID != targetSpaceID else { return true }
        guard let manager = AppDelegate.shared.spaceManager,
              let sourceSpace = manager.spaceNameDict.first(where: { $0.id == fromSpaceID }),
              let targetSpace = manager.spaceNameDict.first(where: { $0.id == targetSpaceID }) else {
            return false
        }

        if sourceSpace.isFullscreen || targetSpace.isFullscreen {
            if sourceSpace.isFullscreen {
                guard let axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid) else {
                    return false
                }
                AXUIElementSetAttributeValue(axWindow, "AXFullScreen" as CFString, false as CFTypeRef)
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            }
        }

        // A launcher move must not raise or activate the target window. Move
        // the captured window directly between Spaces instead of synthesizing
        // an active-window drag.
        guard SpaceHelper.moveWindowToSpace(
            windowID: windowID,
            fromSpaceID: fromSpaceID,
            targetSpaceID: targetSpaceID
        ) else {
            return false
        }
        try? await Task.sleep(nanoseconds: 150_000_000)

        return true
    }

    private static func waitForSpace(_ spaceID: String, on displayID: String) async -> Bool {
        for _ in 0..<8 {
            if SpaceHelper.getCurrentSpaceID(for: displayID) == spaceID {
                return true
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }
}
