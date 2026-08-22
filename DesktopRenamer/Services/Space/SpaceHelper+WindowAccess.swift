extension SpaceHelper {

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
    static func moveWindowToSpace(windowID: Int, fromSpaceID: Int, targetSpaceID: Int) {
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
           targetDisplay != sourceDisplay,
           let pid = windowPID, 
           let frame = windowFrame {
            print("SpaceHelper: Cross-monitor move detected (\(sourceDisplay) -> \(targetDisplay)). Repositioning window \(windowID).")
            repositionWindowToDisplay(windowID: windowID, pid: pid, frame: frame, sourceDisplayID: sourceDisplay, targetDisplayID: targetDisplay)
        }

        // Add to target space first for visual stability.
        CGSAddWindowsToSpaces(conn, windowArray, [targetSpaceID as NSNumber] as CFArray)

        // Then remove from source space.
        CGSRemoveWindowsFromSpaces(conn, windowArray, [fromSpaceID as NSNumber] as CFArray)
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
