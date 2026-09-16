import AppKit

@MainActor
enum WindowActionCoordinator {
    private struct WindowPresentationState {
        let pid: Int32
        let wasHidden: Bool
        let wasMinimized: Bool?
    }

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

        guard !targetSpace.isFullscreen else {
            DiagnosticEventLog.shared.record(
                subsystem: "WindowActionCoordinator",
                level: "warning",
                "Refusing to move window \(windowID) into fullscreen Space \(targetSpaceID)."
            )
            return false
        }

        guard resolvedFromSpaceID != targetSpaceID else { return true }

        let presentationState = captureWindowPresentationState(windowID: windowID, pid: pid)
        let needsSourceSpacePreparation = presentationState.map {
            $0.wasHidden || $0.wasMinimized != false
        } ?? false
        if needsSourceSpacePreparation,
           SpaceHelper.getCurrentSpaceID(for: sourceSpace.displayID) != sourceSpace.id {
            // Restore a minimized/hidden window while its source Space is
            // active. Otherwise macOS can restore it into the current Space,
            // making the later move appear to succeed without moving it.
            manager.switchToSpace(sourceSpace, forceInstant: true, isManual: false)
            guard await waitForSpace(sourceSpace.id, on: sourceSpace.displayID) else {
                return false
            }
        }

        // Presentation changes are an asynchronous transaction. Do not call
        // the move primitive until unhide/unminimize has been observed by AX;
        // otherwise macOS can restore the window into the current Space and
        // the later move becomes a no-op.
        if let presentationState {
            guard await prepareWindowForMove(presentationState, windowID: windowID) else {
                await restoreWindowPresentationState(presentationState, windowID: windowID)
                return false
            }
        }

        // The source membership must still be present after AX finishes
        // restoring the window. If it is not, the requested source is stale;
        // proceeding would allow a successful-looking no-op in the current
        // Space.
        guard await waitForWindow(windowID: windowID, inSpace: resolvedFromSpaceID) else {
            await restoreWindowPresentationState(presentationState, windowID: windowID)
            return false
        }

        let requiresFullscreenHandling = sourceSpace.isFullscreen || targetSpace.isFullscreen

        // AX cannot reliably access a window in a background fullscreen
        // Space. Make only that source Space current long enough to leave
        // fullscreen; ordinary moves remain non-activating.
        if requiresFullscreenHandling, sourceSpace.isFullscreen {
            if SpaceHelper.getCurrentSpaceID(for: sourceSpace.displayID) != sourceSpace.id {
                manager.switchToSpace(sourceSpace, forceInstant: true, isManual: false)
                guard await waitForSpace(sourceSpace.id, on: sourceSpace.displayID) else {
                    await restoreWindowPresentationState(presentationState, windowID: windowID)
                    return false
                }
            }

            guard let axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid) else {
                DiagnosticEventLog.shared.record(
                    subsystem: "WindowActionCoordinator",
                    level: "warning",
                    "Could not access fullscreen window \(windowID) before moving it from \(resolvedFromSpaceID)."
                )
                await restoreWindowPresentationState(presentationState, windowID: windowID)
                return false
            }
            AXUIElementSetAttributeValue(axWindow, "AXFullScreen" as CFString, false as CFTypeRef)
            try? await Task.sleep(nanoseconds: 1_200_000_000)
        }

        // Cross-display moves, and direct moves of temporarily restored
        // windows, need the destination Space active so WindowServer can
        // place the window before it is minimized/hidden again.
        let destinationMustBeCurrent = sourceSpace.displayID != targetSpace.displayID
        let destinationIsCurrent = SpaceHelper.getCurrentSpaceID(for: targetSpace.displayID) == targetSpace.id
        let requiresDirectMove = presentationState.map {
            $0.wasHidden || $0.wasMinimized != false
        } ?? false
        if (destinationMustBeCurrent || requiresDirectMove), !destinationIsCurrent {
            manager.switchToSpace(targetSpace, forceInstant: true, isManual: false)
            guard await waitForSpace(targetSpace.id, on: targetSpace.displayID) else {
                await restoreWindowPresentationState(presentationState, windowID: windowID)
                return false
            }
        }

        // Ordinary same-display visible windows follow the same established
        // Option-drag primitive as a user move. A background window must have
        // its source Space current before its frame can be hit-tested; focus is
        // not required as a separate step. Hidden and minimized windows use
        // direct WindowServer assignment after the explicit presentation
        // transaction above.
        if !destinationMustBeCurrent,
           !sourceSpace.isFullscreen,
           presentationState?.wasHidden != true,
           presentationState?.wasMinimized == false,
           NSRunningApplication(processIdentifier: pid)?.isHidden != true {
            if SpaceHelper.getCurrentSpaceID(for: sourceSpace.displayID) != sourceSpace.id {
                manager.switchToSpace(sourceSpace, forceInstant: true, isManual: false)
                guard await waitForSpace(sourceSpace.id, on: sourceSpace.displayID) else {
                    await restoreWindowPresentationState(presentationState, windowID: windowID)
                    return false
                }
            }

            let isMinimized: Bool? = SpaceHelper.getAXWindow(id: windowID, pid: pid).flatMap { axWindow in
                var minimizedRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(
                    axWindow,
                    kAXMinimizedAttribute as CFString,
                    &minimizedRef
                ) == .success else { return nil }
                return minimizedRef as? Bool
            }

            // An unavailable AX state is not evidence that the window is
            // usable. Minimized windows can temporarily disappear from the
            // AX hierarchy, so send them through the direct move path instead
            // of starting a drag that can never succeed.
            if isMinimized == false, let windowInfo = SpaceHelper.getWindowInfo(id: windowID) {
                SpaceHelper.dragWindow(
                    (id: windowID, pid: pid, frame: windowInfo.frame),
                    to: targetSpaceID,
                    forceInstant: true
                )
                if await waitForWindow(
                    windowID: windowID,
                    inSpace: targetSpaceID,
                    excluding: resolvedFromSpaceID
                ) {
                    await restoreWindowPresentationState(presentationState, windowID: windowID)
                    return true
                }
            }
        }

        // Direct assignment is the fallback for hidden/minimized/fullscreen or
        // cross-display windows, and also recovers if a synthetic drag did not
        // complete. It never raises or activates the application. This is the
        // existing move module; presentation restoration stays in this
        // coordinator so it cannot race the move's completion.
        let wasImmediatelyObserved = SpaceHelper.moveWindowToSpace(
            windowID: windowID,
            fromSpaceID: resolvedFromSpaceID,
            targetSpaceID: targetSpaceID
        )
        if !wasImmediatelyObserved {
            DiagnosticEventLog.shared.record(
                subsystem: "WindowActionCoordinator",
                level: "info",
                "Window \(windowID) move was not visible in the immediate WindowServer read; waiting for destination \(targetSpaceID)."
            )
        }
        var moved = await waitForWindow(
            windowID: windowID,
            inSpace: targetSpaceID,
            excluding: resolvedFromSpaceID
        )

        // WindowServer can reject the first assignment while a restored
        // window is settling. Retry the already-completed preparation/move
        // boundary once before restoring presentation state.
        if !moved {
            _ = SpaceHelper.moveWindowToSpace(
                windowID: windowID,
                fromSpaceID: resolvedFromSpaceID,
                targetSpaceID: targetSpaceID
            )
            moved = await waitForWindow(
                windowID: windowID,
                inSpace: targetSpaceID,
                excluding: resolvedFromSpaceID
            )
        }
        await restoreWindowPresentationState(presentationState, windowID: windowID)
        return moved
    }

    /// Restores every display to the snapshot captured before a launcher
    /// operation. Window actions can temporarily activate a different display,
    /// so restoring only the selected window's display leaves multi-monitor
    /// sessions in a different arrangement than where they started.
    static func restoreOriginalSpaces(
        _ originalSpaceByDisplay: [String: String],
        using manager: SpaceManager
    ) async {
        guard manager.returnToOriginalAfterBatchMove else { return }

        for (displayID, originalSpaceID) in originalSpaceByDisplay {
            guard let originalSpace = manager.spaceNameDict.first(where: {
                $0.id == originalSpaceID && $0.displayID == displayID
            }) else {
                continue
            }

            if SpaceHelper.getCurrentSpaceID(for: displayID) != originalSpaceID {
                manager.switchToSpace(originalSpace, forceInstant: true, isManual: false)
                _ = await waitForSpace(originalSpace.id, on: displayID)
            }
        }
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

    private static func captureWindowPresentationState(windowID: Int, pid: Int32) -> WindowPresentationState? {
        guard NSRunningApplication(processIdentifier: pid) != nil else {
            return nil
        }

        return WindowPresentationState(
            pid: pid,
            wasHidden: NSRunningApplication(processIdentifier: pid)?.isHidden == true,
            wasMinimized: readWindowMinimizedState(windowID: windowID, pid: pid)
        )
    }

    private static func prepareWindowForMove(
        _ state: WindowPresentationState,
        windowID: Int
    ) async -> Bool {
        // Keep the source Space active while unhiding. macOS may otherwise
        // attach the restored window to whichever Space is currently shown.
        if state.wasHidden {
            NSRunningApplication(processIdentifier: state.pid)?.unhide()
            guard await waitForAppHidden(state.pid, isHidden: false) else {
                return false
            }
        }

        // A missing AX value is not proof that the window is minimized. If AX
        // becomes available after unhide, however, honor the value and wait
        // for the requested transition before calling the move module.
        let minimizedState = state.wasMinimized ?? readWindowMinimizedState(windowID: windowID, pid: state.pid)
        if minimizedState == true {
            guard await setWindowMinimized(
                windowID: windowID,
                pid: state.pid,
                minimized: false
            ) else {
                return false
            }
        }

        return true
    }

    private static func restoreWindowPresentationState(
        _ state: WindowPresentationState?,
        windowID: Int
    ) async {
        guard let state else { return }

        // The move must be fully observed before restoring either flag. In
        // particular, minimizing immediately after CGS assignment can make
        // WindowServer keep the window in its old Space.
        if state.wasMinimized == true {
            _ = await setWindowMinimized(
                windowID: windowID,
                pid: state.pid,
                minimized: true
            )
        }

        if state.wasHidden {
            NSRunningApplication(processIdentifier: state.pid)?.hide()
            _ = await waitForAppHidden(state.pid, isHidden: true)
        }
    }

    private static func waitForAXWindow(windowID: Int, pid: Int32) async -> AXUIElement? {
        for attempt in 0..<12 {
            if let axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid) {
                return axWindow
            }
            if attempt < 11 {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        return nil
    }

    private static func readWindowMinimizedState(windowID: Int, pid: Int32) -> Bool? {
        guard let axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid) else {
            return nil
        }

        var minimizedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            axWindow,
            kAXMinimizedAttribute as CFString,
            &minimizedRef
        ) == .success else {
            return nil
        }
        return minimizedRef as? Bool
    }

    @discardableResult
    private static func setWindowMinimized(
        windowID: Int,
        pid: Int32,
        minimized: Bool
    ) async -> Bool {
        guard let axWindow = await waitForAXWindow(windowID: windowID, pid: pid),
              AXUIElementSetAttributeValue(
                  axWindow,
                  kAXMinimizedAttribute as CFString,
                  minimized as CFTypeRef
              ) == .success else {
            return false
        }

        for attempt in 0..<12 {
            if readWindowMinimizedState(windowID: windowID, pid: pid) == minimized {
                return true
            }
            if attempt < 11 {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        return readWindowMinimizedState(windowID: windowID, pid: pid) == minimized
    }

    private static func waitForAppHidden(_ pid: Int32, isHidden: Bool) async -> Bool {
        for attempt in 0..<12 {
            if NSRunningApplication(processIdentifier: pid)?.isHidden == isHidden {
                return true
            }
            if attempt < 11 {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        return NSRunningApplication(processIdentifier: pid)?.isHidden == isHidden
    }

    private static func waitForWindow(
        windowID: Int,
        inSpace spaceID: String,
        excluding sourceSpaceID: String
    ) async -> Bool {
        for _ in 0..<12 {
            let assignedSpaceIDs = SpaceHelper.getWindowCurrentSpaces(windowID: windowID)
            if assignedSpaceIDs.contains(spaceID), !assignedSpaceIDs.contains(sourceSpaceID) {
                return true
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        DiagnosticEventLog.shared.record(
            subsystem: "WindowActionCoordinator",
            level: "warning",
            "Window \(windowID) was not exclusively observed in destination Space \(spaceID) after move; source=\(sourceSpaceID)."
        )
        return false
    }

    private static func waitForWindow(windowID: Int, inSpace spaceID: String) async -> Bool {
        for _ in 0..<12 {
            if SpaceHelper.getWindowCurrentSpaces(windowID: windowID).contains(spaceID) {
                return true
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }
}
