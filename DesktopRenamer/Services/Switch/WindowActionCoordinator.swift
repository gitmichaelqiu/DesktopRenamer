import AppKit

@MainActor
enum WindowActionCoordinator {
    private static let operationGate = WindowOperationGate()

    /// Raycast waits for the synthetic drag and WindowServer's presentation
    /// transition before restoring the launcher's original Spaces. Native
    /// launcher callers use the same boundary so both clients serialize the
    /// same move transaction.
    static func waitForMoveToSettle(isFullscreen: Bool, batch: Bool = false) async {
        let nanoseconds: UInt64
        if isFullscreen {
            nanoseconds = batch ? 1_700_000_000 : 1_750_000_000
        } else {
            nanoseconds = batch ? 500_000_000 : 600_000_000
        }
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    private struct WindowPresentationState {
        let pid: Int32
        let wasHidden: Bool
        var wasMinimized: Bool?
        var isUnminimizedForMove = false
        var isRaisedForMove = false

        var requiresPresentationTransition: Bool {
            wasHidden || wasMinimized != false
        }
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
        targetSpaceID: String,
        wasMinimized: Bool? = nil,
        wasHidden: Bool? = nil
    ) async -> Bool {
        guard await operationGate.acquire() else { return false }
        guard !Task.isCancelled else {
            await operationGate.release()
            return false
        }

        let result = await performMoveWindow(
            windowID: windowID,
            pid: pid,
            fromSpaceID: fromSpaceID,
            targetSpaceID: targetSpaceID,
            wasMinimized: wasMinimized,
            wasHidden: wasHidden
        )
        await operationGate.release()
        return result
    }

    private static func performMoveWindow(
        windowID: Int,
        pid: Int32,
        fromSpaceID: String,
        targetSpaceID: String,
        wasMinimized: Bool?,
        wasHidden: Bool?
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

        var presentationState = captureWindowPresentationState(
            windowID: windowID,
            pid: pid,
            minimizedHint: wasMinimized,
            hiddenHint: wasHidden
        )
        let needsSourceSpacePreparation = presentationState?.requiresPresentationTransition ?? false
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
        if let capturedState = presentationState {
            guard let preparedState = await prepareWindowForMove(
                capturedState,
                windowID: windowID
            ) else {
                await restoreWindowPresentationState(capturedState, windowID: windowID)
                return false
            }
            presentationState = preparedState
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

        // Cross-display moves need the destination Space active so the move
        // primitive can place the window on that display. Same-display
        // restored windows intentionally remain in their source Space until
        // after the move; changing Spaces here can make WindowServer restore
        // them into the current Space before the assignment runs.
        let destinationMustBeCurrent = sourceSpace.displayID != targetSpace.displayID
        let destinationIsCurrent = SpaceHelper.getCurrentSpaceID(for: targetSpace.displayID) == targetSpace.id
        let requiresDirectMove = presentationState?.requiresPresentationTransition ?? false
        if destinationMustBeCurrent, !destinationIsCurrent {
            manager.switchToSpace(targetSpace, forceInstant: true, isManual: false)
            guard await waitForSpace(targetSpace.id, on: targetSpace.displayID) else {
                await restoreWindowPresentationState(presentationState, windowID: windowID)
                return false
            }
        }

        // Direct moves must start with the source display's Space current when
        // both Spaces are on the same display. This is especially important
        // after AX has just unminimized a window from a background Space.
        if requiresDirectMove,
           !destinationMustBeCurrent,
           SpaceHelper.getCurrentSpaceID(for: sourceSpace.displayID) != sourceSpace.id {
            manager.switchToSpace(sourceSpace, forceInstant: true, isManual: false)
            guard await waitForSpace(sourceSpace.id, on: sourceSpace.displayID) else {
                await restoreWindowPresentationState(presentationState, windowID: windowID)
                return false
            }
        }

        // Use the established Option-drag move module for every window that
        // is usable after preparation, including windows that were just
        // unhidden or unminimized. CGS assignment is not a reliable move
        // primitive for a restored user window; it can leave the window in
        // the source Space while the later presentation restore makes the
        // operation look like a completed no-op.
        if !destinationMustBeCurrent,
           !sourceSpace.isFullscreen,
           NSRunningApplication(processIdentifier: pid)?.isHidden != true {
            if SpaceHelper.getCurrentSpaceID(for: sourceSpace.displayID) != sourceSpace.id {
                manager.switchToSpace(sourceSpace, forceInstant: true, isManual: false)
                guard await waitForSpace(sourceSpace.id, on: sourceSpace.displayID) else {
                    await restoreWindowPresentationState(presentationState, windowID: windowID)
                    return false
                }
            }

            let isMinimized = readWindowMinimizedState(windowID: windowID, pid: pid)
            let isUnminimizedForMove = isMinimized == false
                || (isMinimized == nil && presentationState?.isUnminimizedForMove == true)

            if isUnminimizedForMove {
                var isRaisedForMove = presentationState?.isRaisedForMove == true
                if !isRaisedForMove {
                    isRaisedForMove = await raiseWindowForMove(windowID: windowID, pid: pid)
                    if isRaisedForMove {
                        presentationState?.isRaisedForMove = true
                    }
                }

                if isRaisedForMove,
                   let windowInfo = await waitForWindowInfo(windowID: windowID, pid: pid) {
                    SpaceHelper.dragWindow(
                        (id: windowID, pid: pid, frame: windowInfo.frame),
                        to: targetSpaceID,
                        forceInstant: true
                    )
                    let reachedDestination = await waitForWindow(
                        windowID: windowID,
                        inSpace: targetSpaceID,
                        excluding: resolvedFromSpaceID
                    )
                    guard await waitForSyntheticDragToFinish() else {
                        DiagnosticEventLog.shared.record(
                            subsystem: "WindowActionCoordinator",
                            level: "warning",
                            "Synthetic drag for window \(windowID) did not release before presentation restoration; refusing to minimize or hide it again."
                        )
                        return false
                    }
                    if reachedDestination {
                        if presentationState?.requiresPresentationTransition == true {
                            await waitForMoveToSettle(isFullscreen: sourceSpace.isFullscreen)
                        }
                        await restoreWindowPresentationState(presentationState, windowID: windowID)
                        return true
                    }
                }
            }
        }

        // Direct assignment is the fallback for hidden/minimized/fullscreen or
        // cross-display windows, and also recovers if a synthetic drag did not
        // complete. It never raises or activates the application. This is the
        // existing move module; presentation restoration stays in this
        // coordinator so it cannot race the move's completion.
        DiagnosticEventLog.shared.record(
            subsystem: "WindowActionCoordinator",
            level: "info",
            "Calling moveWindowToSpace: window=\(windowID), source=\(resolvedFromSpaceID), target=\(targetSpaceID), minimized=\(presentationState?.wasMinimized.map(String.init) ?? "unknown"), hidden=\(presentationState?.wasHidden ?? false)"
        )
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

        // WindowServer can reject an assignment while a restored window is
        // settling. Retry the direct move while the window is still
        // unminimized; restoring presentation state is the final phase and
        // must never race one of these attempts.
        for _ in 0..<2 where !moved {
            try? await Task.sleep(nanoseconds: 300_000_000)
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

        // A direct same-display move does not switch Spaces as a side effect.
        // Show the destination only after WindowServer confirms that the
        // window has left its source, then restore its original presentation.
        if moved,
           !destinationMustBeCurrent,
           SpaceHelper.getCurrentSpaceID(for: targetSpace.displayID) != targetSpace.id {
            manager.switchToSpace(targetSpace, forceInstant: true, isManual: false)
            guard await waitForSpace(targetSpace.id, on: targetSpace.displayID) else {
                await restoreWindowPresentationState(presentationState, windowID: windowID)
                return false
            }
        }
        if moved, presentationState?.requiresPresentationTransition == true {
            await waitForMoveToSettle(isFullscreen: sourceSpace.isFullscreen)
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
        var consecutiveMatches = 0

        for attempt in 0..<30 {
            if SpaceHelper.getCurrentSpaceID(for: displayID) == spaceID {
                consecutiveMatches += 1
                if consecutiveMatches >= 3 {
                    return true
                }
            } else {
                consecutiveMatches = 0
            }
            if attempt < 29 {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        return false
    }

    private static func captureWindowPresentationState(
        windowID: Int,
        pid: Int32,
        minimizedHint: Bool?,
        hiddenHint: Bool?
    ) -> WindowPresentationState? {
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            return nil
        }

        let observedMinimized = readWindowMinimizedState(windowID: windowID, pid: pid)
        // A true observation or hint is authoritative. A false hint remains a
        // useful fallback when AX cannot expose a background/minimized window,
        // while a fresh true AX observation must always win over a stale hint.
        var wasMinimized: Bool?
        if observedMinimized == true || minimizedHint == true {
            wasMinimized = true
        } else {
            wasMinimized = observedMinimized ?? minimizedHint
        }

        return WindowPresentationState(
            pid: pid,
            wasHidden: app.isHidden || hiddenHint == true,
            wasMinimized: wasMinimized
        )
    }

    private static func prepareWindowForMove(
        _ state: WindowPresentationState,
        windowID: Int
    ) async -> WindowPresentationState? {
        var preparedState = state

        // Keep the source Space active while unhiding. macOS may otherwise
        // attach the restored window to whichever Space is currently shown.
        if state.wasHidden {
            NSRunningApplication(processIdentifier: state.pid)?.unhide()
            guard await waitForAppHidden(state.pid, isHidden: false) else {
                return nil
            }
        }

        if preparedState.wasMinimized == false {
            preparedState.isUnminimizedForMove = true
        }

        // Unhiding can make the exact AX window appear after the initial
        // snapshot. Re-check it and preserve that newly observed state so a
        // hidden + minimized window is minimized again after the move.
        if readWindowMinimizedState(windowID: windowID, pid: state.pid) == true {
            preparedState.wasMinimized = true
        }

        if preparedState.wasMinimized == true {
            guard await setWindowMinimized(
                windowID: windowID,
                pid: state.pid,
                minimized: false
            ) else {
                return nil
            }
            preparedState.isUnminimizedForMove = true
        } else if readWindowMinimizedState(windowID: windowID, pid: state.pid) == false {
            preparedState.isUnminimizedForMove = true
        }

        if state.wasHidden {
            // Unhiding an application does not necessarily raise the target
            // window. If another window is in front of it, the synthetic
            // drag will hit that window (or the desktop) and the request can
            // be reported as a no-op. Raise the exact window only after any
            // unminimization has completed so it is a usable drag target.
            guard await raiseWindowForMove(windowID: windowID, pid: state.pid) else {
                return nil
            }
            preparedState.isRaisedForMove = true
        }

        // The AX transition above is the completion boundary for
        // unminimization. A CGWindow record or Space assignment can lag behind
        // AX (and can briefly disappear during the restore animation), so it
        // must not be allowed to roll the window back into its original Space.
        // The move primitive below is responsible for waiting for the
        // destination assignment; presentation restoration happens only after
        // that verification completes.
        return preparedState
    }

    private static func raiseWindowForMove(windowID: Int, pid: Int32) async -> Bool {
        guard let axWindow = await waitForAXWindow(windowID: windowID, pid: pid) else {
            return false
        }

        let initialRaiseSucceeded = AXUIElementPerformAction(
            axWindow,
            kAXRaiseAction as CFString
        ) == .success

        // AXRaise can succeed without making a hidden application's window
        // the frontmost hit-test target. Activate the owning application and
        // wait for WindowServer to acknowledge it before starting the
        // synthetic drag. The presentation state is restored after the
        // destination Space has been confirmed.
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            return false
        }
        app.activate(options: .activateIgnoringOtherApps)
        guard await waitForApplicationFrontmost(pid) else {
            return false
        }

        // Some applications report AXRaise as successful while hidden. Fetch
        // the now-visible AX element again and always raise it after
        // activation so the exact window, rather than another window
        // belonging to the same app, remains the drag target.
        guard let activeAXWindow = await waitForAXWindow(windowID: windowID, pid: pid) else {
            return initialRaiseSucceeded
        }
        let finalRaiseSucceeded = AXUIElementPerformAction(
            activeAXWindow,
            kAXRaiseAction as CFString
        ) == .success
        return finalRaiseSucceeded || initialRaiseSucceeded
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

    private static func waitForWindowInfo(
        windowID: Int,
        pid: Int32
    ) async -> (pid: Int32, frame: CGRect)? {
        for attempt in 0..<20 {
            if let windowInfo = SpaceHelper.getWindowInfo(id: windowID),
               windowInfo.pid == pid {
                return windowInfo
            }
            if attempt < 19 {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        return nil
    }

    private static func readWindowMinimizedState(windowID: Int, pid: Int32) -> Bool? {
        guard let axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid) else {
            return nil
        }

        return readWindowMinimizedState(of: axWindow)
    }

    private static func readWindowMinimizedState(of axWindow: AXUIElement) -> Bool? {
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
        guard let axWindow = await waitForAXWindow(windowID: windowID, pid: pid) else {
            return false
        }

        guard AXUIElementSetAttributeValue(
            axWindow,
            kAXMinimizedAttribute as CFString,
            minimized as CFTypeRef
        ) == .success else {
            return false
        }

        // Keep polling the same AX element that received the request. A
        // minimized window can temporarily disappear from AXWindows while it
        // is being restored; immediately looking it up again turns a
        // completed unminimize into a false failure and causes the caller to
        // minimize it back in the source Space.
        var consecutiveMatches = 0
        for attempt in 0..<20 {
            let currentState = readWindowMinimizedState(of: axWindow)
                ?? readWindowMinimizedState(windowID: windowID, pid: pid)
            if currentState == minimized {
                consecutiveMatches += 1
                if consecutiveMatches >= 3 {
                    return true
                }
            } else {
                consecutiveMatches = 0
            }
            if attempt < 19 {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        return false
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

    private static func waitForApplicationFrontmost(_ pid: Int32) async -> Bool {
        for attempt in 0..<12 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
                return true
            }
            if attempt < 11 {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }

    private static func waitForSyntheticDragToFinish() async -> Bool {
        for attempt in 0..<30 {
            if !SpaceHelper.isDragging {
                return true
            }
            if attempt < 29 {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        return !SpaceHelper.isDragging
    }

    private static func waitForWindow(
        windowID: Int,
        inSpace spaceID: String,
        excluding sourceSpaceID: String
    ) async -> Bool {
        var consecutiveDestinationReads = 0

        for attempt in 0..<40 {
            let assignedSpaceIDs = SpaceHelper.getWindowCurrentSpaces(windowID: windowID)
            if assignedSpaceIDs.contains(spaceID), !assignedSpaceIDs.contains(sourceSpaceID) {
                consecutiveDestinationReads += 1
                if consecutiveDestinationReads >= 3 {
                    return true
                }
            } else {
                consecutiveDestinationReads = 0
            }
            if attempt < 39 {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        DiagnosticEventLog.shared.record(
            subsystem: "WindowActionCoordinator",
            level: "warning",
            "Window \(windowID) was not exclusively observed in destination Space \(spaceID) after move; source=\(sourceSpaceID)."
        )
        return false
    }

    private static func waitForWindow(windowID: Int, inSpace spaceID: String) async -> Bool {
        var consecutiveMatches = 0

        for attempt in 0..<40 {
            if SpaceHelper.getWindowCurrentSpaces(windowID: windowID).contains(spaceID) {
                consecutiveMatches += 1
                if consecutiveMatches >= 3 {
                    return true
                }
            } else {
                consecutiveMatches = 0
            }
            if attempt < 39 {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        return false
    }
}

private actor WindowOperationGate {
    private var isOccupied = false
    private var nextWaiterID = 0
    private var waiters: [(id: Int, continuation: CheckedContinuation<Bool, Never>)] = []

    func acquire() async -> Bool {
        guard !Task.isCancelled else { return false }

        if !isOccupied {
            isOccupied = true
            return true
        }

        let waiterID = nextWaiterID
        nextWaiterID += 1

        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                if Task.isCancelled {
                    continuation.resume(returning: false)
                } else {
                    waiters.append((id: waiterID, continuation: continuation))
                }
            }
        }, onCancel: {
            Task { await self.cancel(waiterID: waiterID) }
        })
    }

    func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.continuation.resume(returning: true)
        } else {
            isOccupied = false
        }
    }

    private func cancel(waiterID: Int) {
        guard let index = waiters.firstIndex(where: { $0.id == waiterID }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(returning: false)
    }
}
