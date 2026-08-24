import AppKit
import SwiftUI
import ApplicationServices

extension SpaceHelper {

    // MARK: - Window Moving Logic
    
    static func dragActiveWindow(to spaceID: String, forceInstant: Bool = false) {
        // Option+swipe can emit several callbacks while the same gesture is
        // settling. Repeating the same request would cancel the existing
        // restoration timer and leave the mouse-down session stuck.
        if isDragging, targetSpaceID == spaceID {
            return
        }

        DiagnosticEventLog.shared.record(subsystem: "SpaceHelper", level: "info", "dragActiveWindow → \(spaceID)")
        targetSpaceID = spaceID
        // Cancel any pending restoration from a previous "chained" move
        restorationTask?.cancel()
        restorationTask = nil

        // Hide preview labels before any mouse manipulation. The later switchToSpace call
        // also posts SpaceSwitchRequested, but in the meantime the simulated mouse events
        // (move, down, drag) would otherwise show labels while the app window is being
        // grabbed for the drag-move. Post immediately so labels are hidden throughout.
        NotificationCenter.default.post(
            name: NSNotification.Name("SpaceSwitchRequested"), object: nil)

        let source = CGEventSource(stateID: .hidSystemState)

        // Session Initialization: Capture original mouse state for the initial move.
        if originalMousePoint == nil {
            isInstantDrag = forceInstant
            // Save starting location
            originalMousePoint = CGEvent(source: nil)?.location
            
            // Get Active Window Info to calculate grab point
            guard let activeWindowInfo = getActiveWindowInfo() else {
                originalMousePoint = nil
                return 
            }
            
            draggedWindowID = activeWindowInfo.id
            draggedWindowPID = activeWindowInfo.pid
            if let runningApp = NSRunningApplication(processIdentifier: activeWindowInfo.pid) {
                draggedWindowBundleID = runningApp.bundleIdentifier
                draggedWindowAppName = runningApp.localizedName
            }
            draggedWindowOriginalFrame = activeWindowInfo.frame
            
            let frame = activeWindowInfo.frame
            let grabX: CGFloat
            let grabY: CGFloat
            var shouldDragFirst = false
            
            if let sm = AppDelegate.shared.spaceManager {
                if let bundleID = draggedWindowBundleID,
                   let exception = sm.appGrabExceptions.first(where: { $0.bundleIdentifier == bundleID }) {
                    grabX = frame.origin.x + CGFloat(exception.grabOffsetX)
                    grabY = frame.origin.y + CGFloat(exception.grabOffsetY)
                    shouldDragFirst = exception.shouldDragBeforeSwitch
                    print("SpaceHelper: Using per-app grab exception (\(exception.grabOffsetX), \(exception.grabOffsetY)) for \(exception.appName) (\(bundleID)), dragBeforeSwitch=\(shouldDragFirst)")
                } else {
                    grabX = frame.origin.x + CGFloat(sm.grabOffsetX)
                    grabY = frame.origin.y + CGFloat(sm.grabOffsetY)
                }
            } else {
                grabX = frame.origin.x + 13
                grabY = frame.origin.y + 25
            }
            
            let grabPoint = CGPoint(x: grabX, y: grabY)
            
            // Move to grab point and Down
            if let moveEvent = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: grabPoint, mouseButton: .left) {
                moveEvent.flags = []
                moveEvent.post(tap: .cgSessionEventTap)
            }
            
            if shouldDragFirst {
                usleep(50000) // 50ms settle after move for drag-first path
            }
            
            if let downEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: grabPoint, mouseButton: .left) {
                downEvent.flags = []
                downEvent.post(tap: .cgSessionEventTap)
            }
            
            usleep(shouldDragFirst ? 50000 : 10000) // 50ms grip for drag-first, 10ms otherwise
            
            if shouldDragFirst {
                // Drag 5px to the right and then reverse it back before switching spaces
                let dragAmount: CGFloat = 5
                let dragPoint = CGPoint(x: grabPoint.x + dragAmount, y: grabPoint.y)
                if let dragEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: dragPoint, mouseButton: .left) {
                    dragEvent.flags = []
                    dragEvent.setIntegerValueField(.mouseEventDeltaX, value: Int64(dragAmount)) // kCGEventAssociatedMouseDeltaX
                    dragEvent.setIntegerValueField(.mouseEventDeltaY, value: 0) // kCGEventAssociatedMouseDeltaY
                    dragEvent.post(tap: .cgSessionEventTap)
                }
                usleep(30000) // 30ms settle
                
                if let dragBackEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: grabPoint, mouseButton: .left) {
                    dragBackEvent.flags = []
                    dragBackEvent.setIntegerValueField(.mouseEventDeltaX, value: Int64(-dragAmount)) // kCGEventAssociatedMouseDeltaX
                    dragBackEvent.setIntegerValueField(.mouseEventDeltaY, value: 0) // kCGEventAssociatedMouseDeltaY
                    dragBackEvent.post(tap: .cgSessionEventTap)
                }
                usleep(30000) // 30ms settle

                // If the window drifted from its original position after the drag-back,
                // warp the cursor to maintain the correct grab offset so the window
                // isn't "dragged behind" during the space switch.
                if let actual = getWindowInfo(id: activeWindowInfo.id) {
                    let dx = actual.frame.origin.x - frame.origin.x
                    let dy = actual.frame.origin.y - frame.origin.y
                    if abs(dx) >= 1 || abs(dy) >= 1 {
                        let correctedGrabPoint = CGPoint(x: grabPoint.x + dx, y: grabPoint.y + dy)
                        CGWarpMouseCursorPosition(correctedGrabPoint)
                    }
                }
            } else {
                // Standard windows with native titlebars automatically bind to the cursor on mouseDown.
                // We bypass drag simulation entirely to prevent unnecessary window shifting.
                let remainingTime = max(0, (forceInstant ? 20000 : 50000) - 10000)
                if remainingTime > 0 {
                    usleep(useconds_t(remainingTime))
                }
            }
        }
        
        // Trigger the space switch and track the movement.
        pendingMoveCount += 1
        switchToSpace(spaceID, forceInstant: forceInstant)
        
        // Schedule a safety fallback for cursor restoration.
        // Ensures the mouse is released after a timeout if the space change detection fails.
        scheduleRestoration(delay: 2.0)
    }
    
    /// Fast-forwards the restoration process because we detected a successful space change.
    static func signalSpaceSwitchComplete(arrivedAtSpaceID: String) {
        DiagnosticEventLog.shared.record(subsystem: "SpaceHelper", level: "info", "signalSpaceSwitchComplete(\(arrivedAtSpaceID))")
        guard originalMousePoint != nil else { return }
        
        let arrivedUUID = arrivedAtSpaceID.uppercased()
        let targetID = targetSpaceID?.uppercased() ?? ""
        
        // Prevent premature completion if we get notifications from other spaces.
        // We match either the raw Wallpaper UUID (for manual mode) or the active ManagedSpaceID (for automatic mode).
        let currentManagedSpaceIDs = getCurrentSpaceIDs().map { $0.uppercased() }
        let isMatch = (arrivedUUID == targetID) || currentManagedSpaceIDs.contains(targetID)
        
        guard isMatch else {
            print("SpaceHelper: Ignoring premature space change event to \(arrivedAtSpaceID) (waiting for \(targetSpaceID ?? ""))")
            return
        }
        
        print("SpaceHelper: Arrived at target space \(arrivedAtSpaceID). Completing move...")
        
        // Decrement pending moves
        pendingMoveCount = max(0, pendingMoveCount - 1)
        
        // Only trigger the "Drop & Restore" if all pending moves are accounted for.
        // We replace the 2.0s safety timer with a quick 0.15s settle-and-restore.
        if pendingMoveCount == 0 {
            let delay = isInstantDrag ? 0.01 : 0.15
            scheduleRestoration(delay: delay)
        }
    }
    
    /// Schedules an atomic cleanup task that drops the window and restores the cursor.
    /// Calling this automatically cancels any previously scheduled restoration job.
    private static func scheduleRestoration(delay: TimeInterval) {
        // Atomic Cancellation: This is the critical fix for "multi restoration" bugs.
        restorationTask?.cancel()
        
        let source = CGEventSource(stateID: .hidSystemState)
        let isInstant = isInstantDrag
        let task = DispatchWorkItem { [originalPoint = originalMousePoint] in
            guard let restorePoint = originalPoint else { 
                originalMousePoint = nil
                restorationTask = nil
                pendingMoveCount = 0
                return 
            }
            
            // Release the window (Mouse Up).
            if let upEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: CGEvent(source: nil)?.location ?? .zero, mouseButton: .left) {
                upEvent.flags = []
                upEvent.post(tap: .cgSessionEventTap)
            }

            // Restore window to its original position if it shifted during drag-before-switch.
            if let frame = draggedWindowOriginalFrame, let wid = draggedWindowID, let pid = draggedWindowPID {
                let appElement = AXUIElementCreateApplication(pid)
                var windowsRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                   let axWindows = windowsRef as? [AXUIElement] {
                    for axWindow in axWindows {
                        var cgWID: CGWindowID = 0
                        if _AXUIElementGetWindow(axWindow, &cgWID) == 0, cgWID == CGWindowID(wid) {
                            var point = frame.origin
                            if let positionRef = AXValueCreate(.cgPoint, &point) {
                                AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, positionRef)
                            }
                            break
                        }
                    }
                }
            }
            
            // Verify window move success after a small delay
            let winID = draggedWindowID
            let bundleID = draggedWindowBundleID
            let appName = draggedWindowAppName
            let expectedSpaceID = targetSpaceID
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let winID = winID, let bundleID = bundleID, let appName = appName {
                    verifyMoveSuccess(windowID: winID, expectedSpaceID: expectedSpaceID, bundleID: bundleID, appName: appName)
                }
            }
            
            // Restore the cursor position.
            usleep(isInstant ? 5000 : 50000) // 5ms for instant switches, 50ms otherwise
            if let restoreEvent = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: restorePoint, mouseButton: .left) {
                restoreEvent.flags = []
                restoreEvent.post(tap: .cgSessionEventTap)
            }
            
            // Reset session state.
            originalMousePoint = nil
            restorationTask = nil
            pendingMoveCount = 0
            targetSpaceID = nil
            draggedWindowID = nil
            draggedWindowPID = nil
            draggedWindowBundleID = nil
            draggedWindowAppName = nil
            draggedWindowOriginalFrame = nil
        }
        
        restorationTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }
    
    private static func verifyMoveSuccess(windowID: Int, expectedSpaceID: String?, bundleID: String, appName: String) {
        // Query visible windows on the screen
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        
        let isStillVisible = windowList.contains { window in
            if let id = window[kCGWindowNumber as String] as? Int, id == windowID {
                return true
            }
            return false
        }
        
        if !isStillVisible {
            if let expectedSpaceID = expectedSpaceID,
               getWindowCurrentSpaces(windowID: windowID).contains(expectedSpaceID) {
                print("SpaceHelper: Window move succeeded for \(appName) (ID: \(windowID)); window is assigned to Space \(expectedSpaceID)")
                return
            }

            DiagnosticEventLog.shared.record(subsystem: "SpaceHelper", level: "error", "Window move FAILED for \(appName) (ID: \(windowID))")
            print("SpaceHelper: Window move failed for \(appName) (ID: \(windowID), BundleID: \(bundleID))")
            
            // Trigger failure HUD notification
            DispatchQueue.main.async {
                handleMoveFailure(bundleID: bundleID, appName: appName)
            }
        } else {
            print("SpaceHelper: Window move succeeded for \(appName) (ID: \(windowID))")
        }
    }
    
    private static func handleMoveFailure(bundleID: String, appName: String) {
        guard let sm = AppDelegate.shared.spaceManager else { return }
        
        let hasException = sm.appGrabExceptions.contains(where: { $0.bundleIdentifier == bundleID })
        
        let message = String(format: String(localized: "Moving window failed for %@"), appName)
        let buttonTitle = hasException ? String(localized: "Edit Exception") : String(localized: "Add Exception")
        
        HUDWindowController.shared.show(
            message: message,
            systemImage: "exclamationmark.triangle.fill",
            iconColor: .orange,
            buttonTitle: buttonTitle
        ) {
            DispatchQueue.main.async {
                if !hasException {
                    // Automatically add the exception with default grab values
                    let newException = AppGrabException(
                        bundleIdentifier: bundleID,
                        appName: appName,
                        grabOffsetX: sm.grabOffsetX,
                        grabOffsetY: sm.grabOffsetY
                    )
                    withAnimation {
                        sm.appGrabExceptions.append(newException)
                    }
                }
                
                // Set autoEditBundleID to open the editor sheet
                sm.autoEditBundleID = bundleID
                
                // Open Settings settings switch tab
                AppDelegate.shared.statusBarController?.openSettingsWindow(tab: .sswitch)
            }
        }
    }
}
