import AppKit
import CoreGraphics

extension SpaceHelper {

    /// Returns the display UUID that a specific space belongs to.
    static func getDisplayID(for spaceID: String) -> String? {
        let conn = _CGSDefaultConnection()
        guard let displays = CGSCopyManagedDisplaySpaces(conn) as? [NSDictionary] else {
            return nil
        }
        
        let mainScreenUUID = mainDisplayUUID()

        for display in displays {
            if let rawID = display["Display Identifier"] as? String,
               let spaces = display["Spaces"] as? [[String: Any]] {
                let displayID = normalizeDisplayID(rawID, mainUUID: mainScreenUUID)
                for space in spaces {
                    if let managedID = space["ManagedSpaceID"] as? Int, String(managedID) == spaceID {
                        return displayID
                    }
                }
            }
        }
        return nil
    }

    /// Returns the bounds of a display given its UUID or CGS numeric identifier.
    static func getDisplayRect(for uuid: String) -> CGRect? {
        for screen in NSScreen.screens {
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
            if let uuidRef = CGDisplayCreateUUIDFromDisplayID(id) {
                let screenUUID = (CFUUIDCreateString(nil, uuidRef.takeRetainedValue()) as String).uppercased()
                if screenUUID == uuid.uppercased() {
                    return CGDisplayBounds(id)
                }
            }
            // Fallback: CGS numeric identifier (e.g. "2")
            if "\(id)" == uuid {
                return CGDisplayBounds(id)
            }
        }
        return nil
    }

    /// Returns the ManagedSpaceIDs of the currently visible spaces (one per display).
    static func getCurrentSpaceIDs() -> [String] {
        let conn = _CGSDefaultConnection()
        guard let displays = CGSCopyManagedDisplaySpaces(conn) as? [NSDictionary] else { return [] }
        var ids: [String] = []
        for display in displays {
            if let currentDict = display["Current Space"] as? [String: Any],
               let managedID = currentDict["ManagedSpaceID"] as? Int {
                ids.append(String(managedID))
            }
        }
        return ids
    }

    /// Returns a formatted description of the raw display spaces managed by macOS.
    static func getRawCGSDisplaySpacesDescription() -> String {
        let conn = _CGSDefaultConnection()
        guard let displays = CGSCopyManagedDisplaySpaces(conn) as? [NSDictionary] else {
            return "  CGSCopyManagedDisplaySpaces: nil or unavailable\n"
        }
        var s = ""
        for (idx, display) in displays.enumerated() {
            let displayID = display["Display Identifier"] as? String ?? "Unknown"
            s += "  Display [\(idx)] ID=\(displayID):\n"
            if let currentSpace = display["Current Space"] as? [String: Any],
               let currentID = currentSpace["ManagedSpaceID"] as? Int {
                s += "    Current Space ManagedSpaceID: \(currentID)\n"
            }
            if let spaces = display["Spaces"] as? [[String: Any]] {
                s += "    Spaces:\n"
                for space in spaces {
                    if let spaceID = space["ManagedSpaceID"] as? Int {
                        let isFS = space["TileLayoutManager"] != nil
                        let spaceType = space["Space Type"] as? Int ?? -1
                        let pid = space["pid"] as? Int32 ?? space["owner pid"] as? Int32 ?? 0
                        s += "      - ManagedSpaceID: \(spaceID) (Type: \(spaceType), isFullscreen: \(isFS ? 1 : 0), PID: \(pid))\n"
                    }
                }
            }
        }
        return s
    }

    static func getDisplayName(for uuidString: String, screenMap: [String: String]) -> String {
        // Reviewer recommendation: Use case-insensitive comparison for robustness.
        if let name = screenMap[uuidString.uppercased()] {
            return name
        }
        return "Display"
    }

    static func detectSpaceChange() {
        DiagnosticEventLog.shared.record(subsystem: "SpaceHelper", level: "info", "detectSpaceChange")
        // Record switch completion time for self-calibrating velocity.
        endGestureTiming()

        getRawSpaceUUID { spaceUUID, isDesktop, ncCnt, displayID in
            onSpaceChange?(spaceUUID, isDesktop, ncCnt, displayID)
        }
    }

    static func getCursorDisplayID() -> String? {
        let mouseLocation = NSEvent.mouseLocation
        guard
            let screen = NSScreen.screens.first(where: {
                NSMouseInRect(mouseLocation, $0.frame, false)
            })
        else { return nil }

        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? CGDirectDisplayID
        else { return nil }
        guard let uuidRef = CGDisplayCreateUUIDFromDisplayID(id) else { return nil }
        let uuid = uuidRef.takeRetainedValue()
        return (CFUUIDCreateString(nil, uuid) as String).uppercased()
    }

    static func getWindowDisplayID(for frame: CGRect) -> String? {
        // Calculate center of the window
        // Note: Window server uses top-left origin for frames from CGWindowListCopyWindowInfo
        let center = CGPoint(x: frame.origin.x + frame.width / 2, y: frame.origin.y + frame.height / 2)
        
        // Find screen using CGWindowList coordinates (top-left origin, Y increases downwards)
        // We find the screen whose frame contains this point in CG coordinates
        for screen in NSScreen.screens {
            // Convert screen frame to CG coordinates (top-left)
            // Primary screen is at 0,0. Others relative.
            let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
            let cgFrame = CGDisplayBounds(screenID)
            
            if cgFrame.contains(center) {
                guard let uuidRef = CGDisplayCreateUUIDFromDisplayID(screenID) else { continue }
                let uuid = uuidRef.takeRetainedValue()
                return (CFUUIDCreateString(nil, uuid) as String).uppercased()
            }
        }
        
        return nil
    }

    static func getCurrentSpaceID(for displayID: String) -> String? {
        let conn = _CGSDefaultConnection()
        guard let displays = CGSCopyManagedDisplaySpaces(conn) as? [NSDictionary] else {
            return nil
        }
        
        let mainScreenUUID = mainDisplayUUID()

        for display in displays {
            if let rawID = display["Display Identifier"] as? String {
                let currentID = normalizeDisplayID(rawID, mainUUID: mainScreenUUID)
                if currentID == normalizeDisplayID(displayID, mainUUID: mainScreenUUID),
                   let currentDict = display["Current Space"] as? [String: Any],
                   let managedID = currentDict["ManagedSpaceID"] as? Int
                {
                    return String(managedID)
                }
            }
        }
        return nil
    }

    static func isPoint(_ point: CGPoint, inside screenFrame: CGRect) -> Bool {
        guard
            let primaryScreen = NSScreen.screens.first(where: {
                $0.frame.origin.x == 0 && $0.frame.origin.y == 0
            })
        else {
            return screenFrame.contains(point)
        }
        let flippedY = NSMaxY(primaryScreen.frame) - point.y
        return screenFrame.contains(CGPoint(x: point.x, y: flippedY))
    }

    static func getAppWindowFrame(bundleIdentifier: String) -> CGRect? {
        guard let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return nil
        }
        let pid = runningApp.processIdentifier
        
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        
        for window in windowList {
            if let windowPid = window[kCGWindowOwnerPID as String] as? Int,
               windowPid == pid,
               let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
               let bounds = window[kCGWindowBounds as String] as? [String: Any],
               let x = bounds["X"] as? CGFloat, let y = bounds["Y"] as? CGFloat,
               let w = bounds["Width"] as? CGFloat, let h = bounds["Height"] as? CGFloat,
               w >= minActiveWindowWidth, h >= minActiveWindowHeight {
                   return CGRect(x: x, y: y, width: w, height: h)
               }
        }
        return nil
    }

    static func isPositionDraggable(at point: CGPoint) -> (isDraggable: Bool, role: String) {
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element)
        
        guard result == .success, let axElement = element else {
            return (false, "Unknown")
        }
        
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &roleRef)
        let role = (roleRef as? String) ?? "Unknown"
        
        // Draggable roles include window background, title bar, toolbar, empty areas, etc.
        // Interactive components like buttons, text inputs, sliders, lists, scroll areas, web views are not draggable.
        let nonDraggableRoles = [
            "AXButton", "AXTextField", "AXTextArea", "AXScrollBar",
            "AXSlider", "AXWebArea", "AXPopUpButton", "AXCheckBox",
            "AXRadioButton", "AXComboBox", "AXList", "AXTable",
            "AXOutline", "AXBrowser", "AXMenuButton"
        ]
        
        let draggableRoles = [
            "AXWindow", "AXTitleBar", "AXToolbar", "AXHeaderArea", "AXSpacer"
        ]
        
        let isDraggable: Bool
        if nonDraggableRoles.contains(role) {
            isDraggable = false
        } else if draggableRoles.contains(role) {
            isDraggable = true
        } else if role == "AXStaticText" || role == "AXGroup" {
            var parentRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axElement, "AXParent" as CFString, &parentRef) == .success,
               let parentVal = parentRef,
               CFGetTypeID(parentVal) == AXUIElementGetTypeID() {
                let parentElement = unsafeBitCast(parentVal, to: AXUIElement.self)
                var parentRoleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(parentElement, kAXRoleAttribute as CFString, &parentRoleRef) == .success,
                   let parentRole = parentRoleRef as? String {
                    isDraggable = draggableRoles.contains(parentRole) || parentRole == "AXGroup"
                } else {
                    isDraggable = true
                }
            } else {
                isDraggable = true
            }
        } else {
            isDraggable = true
        }
        
        return (isDraggable, role)
    }

    static func getGrabPositionStatus(forBundleID bundleID: String, x: Double, y: Double) -> (status: String, isLikelyWorking: Bool) {
        let isGranted = AXIsProcessTrusted()
        if !isGranted {
            return (String(localized: "Accessibility permission not granted"), false)
        }
        
        guard let frame = getAppWindowFrame(bundleIdentifier: bundleID) else {
            return (String(localized: "No visible window found"), false)
        }
        
        let point = CGPoint(x: frame.origin.x + CGFloat(x), y: frame.origin.y + CGFloat(y))
        let (isDraggable, role) = isPositionDraggable(at: point)
        
        if !isDraggable {
            return (String(format: String(localized: "Cursor is on an interactive control (%@)"), role), false)
        }
        
        if y > 60 {
            return (String(localized: "Cursor is too low (likely inside window content area)"), false)
        }
        
        return (String(format: String(localized: "Likely working: Draggable (%@)"), role), true)
    }
}
