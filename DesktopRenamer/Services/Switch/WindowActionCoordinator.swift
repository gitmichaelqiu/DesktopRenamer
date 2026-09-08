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
        guard let manager = AppDelegate.shared.spaceManager,
              let resolvedFromSpaceID = resolveSourceSpaceID(
                  windowID: windowID,
                  requestedSpaceID: fromSpaceID,
                  manager: manager
              ),
              let sourceSpace = manager.spaceNameDict.first(where: { $0.id == resolvedFromSpaceID }),
              let targetSpace = manager.spaceNameDict.first(where: { $0.id == targetSpaceID }) else {
            return false
        }

        guard resolvedFromSpaceID != targetSpaceID else { return true }

        let requiresFullscreenHandling = sourceSpace.isFullscreen || targetSpace.isFullscreen

        // AX cannot reliably access a window in a background fullscreen
        // Space. Make only that source Space current long enough to leave
        // fullscreen; ordinary moves remain non-activating.
        if requiresFullscreenHandling, sourceSpace.isFullscreen {
            if SpaceHelper.getCurrentSpaceID(for: sourceSpace.displayID) != sourceSpace.id {
                manager.switchToSpace(sourceSpace, forceInstant: true, isManual: false)
                guard await waitForSpace(sourceSpace.id, on: sourceSpace.displayID) else {
                    return false
                }
            }

            guard let axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid) else {
                DiagnosticEventLog.shared.record(
                    subsystem: "WindowActionCoordinator",
                    level: "warning",
                    "Could not access fullscreen window \(windowID) before moving it from \(resolvedFromSpaceID)."
                )
                return false
            }
            AXUIElementSetAttributeValue(axWindow, "AXFullScreen" as CFString, false as CFTypeRef)
            try? await Task.sleep(nanoseconds: 1_200_000_000)
        }

        // Cross-display moves need the destination display's Space active so
        // WindowServer can place and reposition the window on that display.
        // A fullscreen destination has the same requirement even when it is
        // on the source display.
        let destinationMustBeCurrent = sourceSpace.displayID != targetSpace.displayID
            || (requiresFullscreenHandling && targetSpace.isFullscreen)
        let destinationIsCurrent = SpaceHelper.getCurrentSpaceID(for: targetSpace.displayID) == targetSpace.id
        if destinationMustBeCurrent, !destinationIsCurrent {
            manager.switchToSpace(targetSpace, forceInstant: true, isManual: false)
            guard await waitForSpace(targetSpace.id, on: targetSpace.displayID) else {
                return false
            }
        }

        // Same-display moves use the same captured-window drag primitive as
        // the Raycast/API path. It preserves the app-specific grab offsets
        // and lets WindowServer complete the move through the established
        // Space-switch transaction. Cross-display moves and already-current
        // destinations use the direct CGS path because a synthetic drag cannot
        // reliably address a background window in those cases.
        // Synthetic dragging requires the target Space to become current: the
        // source window may be in a background Space, so its captured frame is
        // not a reliable hit-test location while the destination is already
        // visible. Direct WindowServer assignment handles that case without
        // activating or raising either application.
        if !destinationMustBeCurrent && !destinationIsCurrent,
           let windowInfo = SpaceHelper.getWindowInfo(id: windowID) {
            SpaceHelper.dragWindow(
                (id: windowID, pid: pid, frame: windowInfo.frame),
                to: targetSpaceID,
                forceInstant: true
            )
        } else if !SpaceHelper.moveWindowToSpace(
            windowID: windowID,
            fromSpaceID: resolvedFromSpaceID,
            targetSpaceID: targetSpaceID
        ) {
            return false
        }

        return await waitForWindow(windowID: windowID, inSpace: targetSpaceID)
    }

    private static func resolveSourceSpaceID(
        windowID: Int,
        requestedSpaceID: String,
        manager: SpaceManager
    ) -> String? {
        let assignedSpaceIDs = SpaceHelper.getWindowCurrentSpaces(windowID: windowID)
        if assignedSpaceIDs.contains(requestedSpaceID) {
            return requestedSpaceID
        }

        if let authoritativeSpaceID = SpaceHelper.getWindowSpaceID(id: windowID),
           manager.spaceNameDict.contains(where: { $0.id == authoritativeSpaceID }) {
            DiagnosticEventLog.shared.record(
                subsystem: "WindowActionCoordinator",
                level: "info",
                "Using authoritative source Space \(authoritativeSpaceID) for window \(windowID) instead of requested \(requestedSpaceID), assigned=\(assignedSpaceIDs.sorted())"
            )
            return authoritativeSpaceID
        }

        guard manager.spaceNameDict.contains(where: { $0.id == requestedSpaceID }) else {
            return nil
        }
        return requestedSpaceID
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

    private static func waitForWindow(windowID: Int, inSpace spaceID: String) async -> Bool {
        for _ in 0..<12 {
            if SpaceHelper.getWindowCurrentSpaces(windowID: windowID).contains(spaceID) {
                return true
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        DiagnosticEventLog.shared.record(
            subsystem: "WindowActionCoordinator",
            level: "warning",
            "Window \(windowID) was not observed in destination Space \(spaceID) after move."
        )
        return false
    }
}
