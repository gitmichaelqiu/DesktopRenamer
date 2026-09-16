import ApplicationServices

import AppKit

extension SpaceHelper {

    struct WindowPresentationState {
        let pid: Int32
        let wasHidden: Bool
        let wasMinimized: Bool?
    }

    static func getAXWindow(id windowID: Int, pid: Int32) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let axWindows = windowsRef as? [AXUIElement] {
            for axWindow in axWindows {
                var cgWID: CGWindowID = 0
                if _AXUIElementGetWindow(axWindow, &cgWID) == 0, cgWID == CGWindowID(windowID) {
                    return axWindow
                }
            }
        }
        return nil
    }

    static func focusWindow(id windowID: Int, pid: Int32) {
        // Use AXUIElement to find and raise the exact window by CGWindowID.
        // This is more reliable than CGSOrderWindow for targeting a specific
        // window when an app has multiple windows.
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        var raised = false

        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let axWindows = windowsRef as? [AXUIElement] {
            for axWindow in axWindows {
                var cgWID: CGWindowID = 0
                if _AXUIElementGetWindow(axWindow, &cgWID) == 0, cgWID == CGWindowID(windowID) {
                    AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                    raised = true
                    break
                }
            }
        }

        // Fallback: use CGSOrderWindow if AX matching failed.
        if !raised {
            let conn = _CGSDefaultConnection()
            _ = CGSOrderWindow(conn, UInt32(windowID), 0, 0)
        }

        // Activate the app so it comes to foreground.
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: .activateIgnoringOtherApps)
        }
    }

    /// Moves a specific window (by CGWindowID) between spaces.
    /// Uses CGSAddWindowsToSpaces + CGSRemoveWindowsFromSpaces (proven in SpaceLabelWindow).
    /// Now handles cross-monitor moves by repositioning the window via Accessibility API.
    @discardableResult
    static func moveWindowToSpace(
        windowID: Int,
        fromSpaceID: String,
        targetSpaceID: String
    ) -> Bool {
        guard let fromID = Int(fromSpaceID), let targetID = Int(targetSpaceID) else {
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceHelper",
                level: "warning",
                "Cannot move window \(windowID): non-numeric Space IDs"
            )
            return false
        }

        return moveWindowToSpace(windowID: windowID, fromSpaceID: fromID, targetSpaceID: targetID)
    }

    @discardableResult
    static func moveWindowToSpace(
        windowID: Int,
        pid: Int32,
        fromSpaceID: String,
        targetSpaceID: String
    ) -> Bool {
        guard let fromID = Int(fromSpaceID), let targetID = Int(targetSpaceID) else {
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceHelper",
                level: "warning",
                "Cannot move window \(windowID): non-numeric Space IDs"
            )
            return false
        }

        return moveWindowToSpace(
            windowID: windowID,
            pid: pid,
            fromSpaceID: fromID,
            targetSpaceID: targetID,
            presentationState: nil,
            restorePresentationState: true
        )
    }

    @discardableResult
    static func moveWindowToSpace(
        windowID: Int,
        pid: Int32,
        fromSpaceID: String,
        targetSpaceID: String,
        presentationState: WindowPresentationState?,
        restorePresentationState: Bool
    ) -> Bool {
        guard let fromID = Int(fromSpaceID), let targetID = Int(targetSpaceID) else {
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceHelper",
                level: "warning",
                "Cannot move window \(windowID): non-numeric Space IDs"
            )
            return false
        }

        let state = presentationState ?? captureWindowPresentationState(windowID: windowID, pid: pid)
        if presentationState == nil {
            prepareWindowForMove(state, windowID: windowID)
        }

        return moveWindowToSpace(
            windowID: windowID,
            fromSpaceID: fromID,
            targetSpaceID: targetID,
            presentationState: state,
            restorePresentationState: restorePresentationState
        )
    }

    @discardableResult
    static func moveWindowToSpace(windowID: Int, fromSpaceID: Int, targetSpaceID: Int) -> Bool {
        guard fromSpaceID != targetSpaceID else { return true }

        let state = captureWindowPresentationState(windowID: windowID, pid: getWindowInfo(id: windowID)?.pid)
        prepareWindowForMove(state, windowID: windowID)

        return moveWindowToSpace(
            windowID: windowID,
            fromSpaceID: fromSpaceID,
            targetSpaceID: targetSpaceID,
            presentationState: state,
            restorePresentationState: true
        )
    }

    @discardableResult
    private static func moveWindowToSpace(
        windowID: Int,
        pid: Int32?,
        fromSpaceID: Int,
        targetSpaceID: Int,
        presentationState: WindowPresentationState?,
        restorePresentationState: Bool
    ) -> Bool {
        guard fromSpaceID != targetSpaceID else { return true }

        let state = presentationState ?? captureWindowPresentationState(windowID: windowID, pid: pid)
        if presentationState == nil {
            prepareWindowForMove(state, windowID: windowID)
        }

        return moveWindowToSpace(
            windowID: windowID,
            fromSpaceID: fromSpaceID,
            targetSpaceID: targetSpaceID,
            presentationState: state,
            restorePresentationState: restorePresentationState
        )
    }

    @discardableResult
    private static func moveWindowToSpace(
        windowID: Int,
        fromSpaceID: Int,
        targetSpaceID: Int,
        presentationState: WindowPresentationState?,
        restorePresentationState: Bool
    ) -> Bool {
        guard fromSpaceID != targetSpaceID else { return true }

        markWindowMoveIntent(to: String(targetSpaceID))
        let targetSpaceIDString = String(targetSpaceID)
        let conn = _CGSDefaultConnection()
        let windowArray = [windowID as NSNumber] as CFArray

        // Cross-monitor move logic
        let targetDisplayID = getDisplayID(for: String(targetSpaceID))
        var sourceDisplayID: String? = nil
        var windowPID: Int32? = nil
        var windowFrame: CGRect? = nil
        
        if let info = getWindowInfo(id: windowID) {
            windowPID = info.pid
            windowFrame = info.frame
            sourceDisplayID = getWindowDisplayID(for: info.frame)
        }
        
        if let targetDisplay = targetDisplayID,
           let sourceDisplay = sourceDisplayID,
           targetDisplay != sourceDisplay {
            if getCurrentSpaceID(for: targetDisplay) != targetSpaceIDString {
                switchToSpace(targetSpaceIDString, forceInstant: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    guard getCurrentSpaceID(for: targetDisplay) == targetSpaceIDString else {
                        DiagnosticEventLog.shared.record(
                            subsystem: "SpaceHelper",
                            level: "error",
                            "Could not activate destination space \(targetSpaceIDString) before moving window \(windowID)."
                        )
                        if restorePresentationState {
                            restoreWindowPresentationState(presentationState, windowID: windowID)
                        }
                        return
                    }
                    _ = moveWindowToSpace(
                        windowID: windowID,
                        fromSpaceID: fromSpaceID,
                        targetSpaceID: targetSpaceID,
                        presentationState: presentationState,
                        restorePresentationState: restorePresentationState
                    )
                }
                return true
            }

            if let pid = windowPID, let frame = windowFrame {
                print("SpaceHelper: Cross-monitor move detected (\(sourceDisplay) -> \(targetDisplay)). Repositioning window \(windowID).")
                repositionWindowToDisplay(windowID: windowID, pid: pid, frame: frame, sourceDisplayID: sourceDisplay, targetDisplayID: targetDisplay)
            }
        }

        // Use the window server's current assignment instead of trusting a
        // cached source Space from a launcher list. A stale source ID would
        // otherwise leave the window in its old Space and make the move look
        // successful while it remains visible in the original location.
        let currentSpaces = getWindowCurrentSpaces(windowID: windowID)
        var spacesToRemove = currentSpaces.filter { $0 != targetSpaceIDString }
        if spacesToRemove.isEmpty, fromSpaceID != targetSpaceID {
            spacesToRemove = [String(fromSpaceID)]
        }

        // Add to target space first for visual stability.
        CGSAddWindowsToSpaces(conn, windowArray, [targetSpaceID as NSNumber] as CFArray)

        // Then remove every previous assignment. This also handles windows
        // that were temporarily assigned to more than one Space by a prior
        // move or by WindowServer while a transition was settling.
        if !spacesToRemove.isEmpty {
            let spacesToRemoveCF = spacesToRemove.compactMap(Int.init).map { NSNumber(value: $0) } as CFArray
            CGSRemoveWindowsFromSpaces(conn, windowArray, spacesToRemoveCF)
        }

        let finalSpaces = getWindowCurrentSpaces(windowID: windowID)
        DiagnosticEventLog.shared.record(
            subsystem: "SpaceHelper",
            level: finalSpaces.contains(targetSpaceIDString) ? "info" : "warning",
            "moveWindowToSpace: window=\(windowID), requestedSource=\(fromSpaceID), target=\(targetSpaceID), before=\(currentSpaces.sorted()), removed=\(spacesToRemove.sorted()), after=\(finalSpaces.sorted())"
        )
        if restorePresentationState {
            restoreWindowPresentationState(presentationState, windowID: windowID)
        }
        return finalSpaces.contains(targetSpaceIDString)
    }

    static func captureWindowPresentationState(windowID: Int, pid: Int32?) -> WindowPresentationState? {
        guard let pid = pid ?? getWindowInfo(id: windowID)?.pid,
              let app = NSRunningApplication(processIdentifier: pid) else {
            return nil
        }

        let wasHidden = app.isHidden

        return WindowPresentationState(
            pid: pid,
            wasHidden: wasHidden,
            wasMinimized: readWindowMinimizedState(windowID: windowID, pid: pid)
        )
    }

    private static func readWindowMinimizedState(windowID: Int, pid: Int32) -> Bool? {
        for attempt in 0..<4 {
            if let axWindow = getAXWindow(id: windowID, pid: pid) {
                var minimizedRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(
                    axWindow,
                    kAXMinimizedAttribute as CFString,
                    &minimizedRef
                ) == .success {
                    return minimizedRef as? Bool
                }
            }

            if attempt < 3 {
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        return nil
    }

    static func prepareWindowForMove(_ state: WindowPresentationState?, windowID: Int) {
        guard let state else { return }

        if state.wasHidden {
            NSRunningApplication(processIdentifier: state.pid)?.unhide()
        }

        if state.wasMinimized == true,
           let axWindow = getAXWindow(id: windowID, pid: state.pid) {
            AXUIElementSetAttributeValue(
                axWindow,
                kAXMinimizedAttribute as CFString,
                false as CFTypeRef
            )
        }

        if state.wasHidden || state.wasMinimized == true {
            // WindowServer needs a short settling period after AX visibility
            // changes before it can reliably reassign the window to a Space.
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    static func restoreWindowPresentationState(_ state: WindowPresentationState?, windowID: Int) {
        guard let state else { return }

        if state.wasMinimized == true,
           let axWindow = getAXWindow(id: windowID, pid: state.pid) {
            AXUIElementSetAttributeValue(
                axWindow,
                kAXMinimizedAttribute as CFString,
                true as CFTypeRef
            )
        }

        if state.wasHidden {
            NSRunningApplication(processIdentifier: state.pid)?.hide()
        }
    }

    private static func repositionWindowToDisplay(windowID: Int, pid: Int32, frame: CGRect, sourceDisplayID: String, targetDisplayID: String) {
        guard let sourceRect = getDisplayRect(for: sourceDisplayID),
              let targetRect = getDisplayRect(for: targetDisplayID) else { return }
        
        // Calculate relative position (offset from source display top-left)
        let relativeX = frame.origin.x - sourceRect.origin.x
        let relativeY = frame.origin.y - sourceRect.origin.y
        
        // Apply same offset to target display
        let newX = targetRect.origin.x + relativeX
        let newY = targetRect.origin.y + relativeY
        
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let axWindows = windowsRef as? [AXUIElement] {
            for axWindow in axWindows {
                var cgWID: CGWindowID = 0
                if _AXUIElementGetWindow(axWindow, &cgWID) == 0, cgWID == CGWindowID(windowID) {
                    var point = CGPoint(x: newX, y: newY)
                    if let positionRef = AXValueCreate(.cgPoint, &point) {
                        AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, positionRef)
                        print("SpaceHelper: Repositioned window \(windowID) to \(newX), \(newY) on target display.")
                    }
                    break
                }
            }
        }
    }

}
