import AppKit
import CoreGraphics
import Foundation

extension SpaceHelper {

    // MARK: - Window Enumeration

    /// Filters a CGWindowList dictionary to user-facing top-level windows.
    /// Accessibility-confirmed windows are trusted even when their title is
    /// empty. CG-only records need stronger evidence so helper windows do not
    /// leak into the launcher.
    private static func isValidWindow(
        _ window: [String: Any],
        ourPID: Int32,
        activationPolicy: NSApplication.ActivationPolicy,
        isAXWindow: Bool,
        minSize: CGFloat = 50
    ) -> Bool {
        guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
              let pid = window[kCGWindowOwnerPID as String] as? Int, pid != Int(ourPID),
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let w = bounds["Width"] as? CGFloat, let h = bounds["Height"] as? CGFloat,
              w >= minSize, h >= minSize
        else { return false }
        // Core Graphics documents alpha as 0.0...1.0. Nearly transparent
        // records are generally overlays or helper surfaces.
        if let alpha = window[kCGWindowAlpha as String] as? Double, alpha <= 0.1 { return false }

        // Accessibility gives us the strongest signal for accessory apps and
        // for untitled/minimized windows. Without it, only regular apps with
        // a meaningful title are safe to expose as launcher targets.
        if !isAXWindow {
            guard activationPolicy == .regular,
                  let title = window[kCGWindowName as String] as? String,
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return false }

            // A non-shared CG surface is commonly a private helper window.
            // Keep AX-confirmed windows above, since secure user windows can
            // legitimately opt out of screen sharing.
            if let sharing = window[kCGWindowSharingState as String] as? Int, sharing == 0 {
                return false
            }
        }
        return true
    }

    private static let userWindowAXRoles: Set<String> = [
        "AXWindow", "AXDialog", "AXSheet", "AXDrawer", "AXPopover"
    ]

    private struct EnumeratedWindow {
        let id: Int
        let pid: Int32
        let dictionary: [String: Any]
        let spaceIDs: [String]
    }

    static func getWindowRecordsForAllSpaces(spaces: [DesktopSpace]) -> [SpaceAPIWindow] {
        getWindowRecordsForAllSpacesIfAvailable(spaces: spaces) ?? []
    }

    private static func getWindowRecordsForAllSpacesIfAvailable(spaces: [DesktopSpace]) -> [SpaceAPIWindow]? {
        let conn = _CGSDefaultConnection()
        let ourPID = ProcessInfo.processInfo.processIdentifier

        // Build PID → app bundle path cache from running applications. Include
        // accessory applications as well as regular applications because an
        // accessory app can still own user-facing windows.
        var pidToAppPath: [Int32: String] = [:]
        var pidToActivationPolicy: [Int32: NSApplication.ActivationPolicy] = [:]
        var axWindowIDs = Set<Int>()
        var minimizedAXWindowIDs = Set<Int>()
        var axWindowEnumerationSucceededPIDs = Set<Int32>()
        for app in NSWorkspace.shared.runningApplications {
            if app.activationPolicy != .prohibited, let path = app.bundleURL?.path {
                pidToAppPath[app.processIdentifier] = path
                pidToActivationPolicy[app.processIdentifier] = app.activationPolicy

                // Get window IDs directly from the app's Accessibility hierarchy
                // for validation and per-window minimized state.
                let appElement = AXUIElementCreateApplication(app.processIdentifier)

                let extractWID = { (element: AXUIElement, requireWindowRole: Bool) in
                    if requireWindowRole {
                        var roleRef: CFTypeRef?
                        guard AXUIElementCopyAttributeValue(
                            element,
                            kAXRoleAttribute as CFString,
                            &roleRef
                        ) == .success,
                        let role = roleRef as? String,
                        userWindowAXRoles.contains(role) else { return }
                    }

                    var cgWID: CGWindowID = 0
                    if _AXUIElementGetWindow(element, &cgWID) == 0, cgWID != 0 {
                        let wid = Int(cgWID)
                        axWindowIDs.insert(wid)
                        // Check per-window AXMinimized attribute (boolean)
                        var minimizedRef: CFTypeRef?
                        if AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
                           let isMin = minimizedRef as? Bool, isMin {
                            minimizedAXWindowIDs.insert(wid)
                        }
                    }
                }

                // 1. Check standard AXWindows attribute (open windows)
                var windowsRef: CFTypeRef?
                var didEnumerateWindows = false
                if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                   let axWindows = windowsRef as? [AXUIElement] {
                    axWindowEnumerationSucceededPIDs.insert(app.processIdentifier)
                    axWindows.forEach { extractWID($0, false) }
                    didEnumerateWindows = true
                }

                // 2. Some applications expose their windows as children
                // instead of through AXWindows (e.g., Preview). Use this as
                // a fallback for every app, not only known bundle IDs.
                if !didEnumerateWindows || app.bundleIdentifier == "com.apple.Preview" {
                    var childrenRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(appElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                       let axChildren = childrenRef as? [AXUIElement] {
                        axWindowEnumerationSucceededPIDs.insert(app.processIdentifier)
                        axChildren.forEach { extractWID($0, true) }
                    }
                }
            }
        }

        // Get ALL windows, not just on-screen, to include off-screen spaces.
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements)
        guard let allWindows = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as? [[String: Any]]
        else { return nil }

        // Collect valid windows with their IDs.
        var validWindows: [(wid: Int, pid: Int32, dict: [String: Any])] = []
        for window in allWindows {
            guard let wid = window[kCGWindowNumber as String] as? Int,
                  let pid = window[kCGWindowOwnerPID as String] as? Int,
                  let activationPolicy = pidToActivationPolicy[Int32(pid)],
                  isValidWindow(
                      window,
                      ourPID: ourPID,
                      activationPolicy: activationPolicy,
                      isAXWindow: axWindowIDs.contains(wid)
                  )
            else { continue }
            validWindows.append((wid: wid, pid: Int32(pid), dict: window))
        }

        // Known space IDs.
        let knownSpaceIDs = Set(spaces.compactMap { Int($0.id) })
        
        // Get active space IDs
        var activeSpaceIDs = Set<Int>()
        if let displays = CGSCopyManagedDisplaySpaces(conn) as? [NSDictionary] {
            for display in displays {
                if let currentDict = display["Current Space"] as? [String: Any],
                   let currentID = currentDict["ManagedSpaceID"] as? Int {
                    activeSpaceIDs.insert(currentID)
                }
            }
        }

        var windowsBySpaceID: [String: [EnumeratedWindow]] = [:]
        var windowsWithoutSpace: [(wid: Int, pid: Int32, dict: [String: Any])] = []
        
        // Query each window individually for its space assignment.
        for (wid, pid, dict) in validWindows {
            let widArray = [wid as NSNumber] as CFArray
            guard let result = CGSCopySpacesForWindows(conn, 7, widArray),
                  let spaceIDs = result as? [NSNumber],
                  !spaceIDs.isEmpty
            else {
                windowsWithoutSpace.append((wid: wid, pid: pid, dict: dict))
                continue
            }

            let knownAssignedSpaceIDs = spaceIDs.map(\.intValue).filter { knownSpaceIDs.contains($0) }
            guard !knownAssignedSpaceIDs.isEmpty else {
                windowsWithoutSpace.append((wid: wid, pid: pid, dict: dict))
                continue
            }
            
            // AX can reject stale WindowServer entries, but only when the
            // application actually answered the AXWindows query. An untrusted
            // client or an app that does not expose that attribute must not
            // make otherwise valid CGWindow records disappear.
            if knownAssignedSpaceIDs.contains(where: activeSpaceIDs.contains),
               axWindowEnumerationSucceededPIDs.contains(pid),
               !axWindowIDs.contains(wid) {
                continue
            }

            // Keep one launcher/API row per window, while preserving all
            // memberships for windows configured to appear in multiple Spaces.
            let primarySpaceID = knownAssignedSpaceIDs.first(where: activeSpaceIDs.contains)
                ?? knownAssignedSpaceIDs[0]
            windowsBySpaceID[String(primarySpaceID), default: []].append(
                EnumeratedWindow(
                    id: wid,
                    pid: pid,
                    dictionary: dict,
                    spaceIDs: knownAssignedSpaceIDs.map(String.init)
                )
            )
        }

        // Fallback unresolved candidates individually. This can safely recover
        // onscreen windows and AX-known minimized windows on the current Space,
        // but it must not guess a background Space for a hidden/offscreen
        // window when the private assignment API is unavailable.
        if !windowsWithoutSpace.isEmpty {
            guard let displays = CGSCopyManagedDisplaySpaces(conn) as? [NSDictionary] else {
                return windowsBySpaceID.isEmpty ? nil : makeWindowRecords(
                    spaces: spaces,
                    windowsBySpaceID: windowsBySpaceID,
                    pidToAppPath: pidToAppPath,
                    minimizedAXWindowIDs: minimizedAXWindowIDs
                )
            }
            let screenUUIDs = getAllDisplayUUIDs()
            let mainUUID = screenUUIDs.first
            var currentSpaceForDisplay: [String: String] = [:]
            var fullscreenPIDToSpace: [Int32: String] = [:]

            for display in displays {
                guard let displayIDRaw = display["Display Identifier"] as? String,
                      let spaces = display["Spaces"] as? [[String: Any]]
                else { continue }
                let displayID = normalizeDisplayID(displayIDRaw, mainUUID: mainUUID)

                if let currentDict = display["Current Space"] as? [String: Any],
                   let currentID = currentDict["ManagedSpaceID"] as? Int {
                    currentSpaceForDisplay[displayID] = String(currentID)
                }

                for space in spaces {
                    guard let managedID = space["ManagedSpaceID"] as? Int else { continue }
                    if space["TileLayoutManager"] != nil {
                        let sid = String(managedID)
                        if let pid = getOwnerPID(for: sid) {
                            fullscreenPIDToSpace[pid] = sid
                        }
                    }
                }
            }

            for (wid, pid, window) in windowsWithoutSpace {
                let isOnScreen = (window[kCGWindowIsOnscreen as String] as? Bool) == true
                guard isOnScreen || axWindowIDs.contains(wid),
                      let bounds = window[kCGWindowBounds as String] as? [String: Any],
                      let x = bounds["X"] as? CGFloat, let y = bounds["Y"] as? CGFloat,
                      let w = bounds["Width"] as? CGFloat, let h = bounds["Height"] as? CGFloat
                else { continue }

                let frame = CGRect(x: x, y: y, width: w, height: h)
                guard let displayID = getWindowDisplayID(for: frame) else { continue }

                let spaceID: String
                if let fsSpace = fullscreenPIDToSpace[Int32(pid)] {
                    spaceID = fsSpace
                } else if let cs = currentSpaceForDisplay[displayID] {
                    spaceID = cs
                } else {
                    continue
                }

                guard knownSpaceIDs.contains(Int(spaceID) ?? -1) else { continue }
                windowsBySpaceID[spaceID, default: []].append(
                    EnumeratedWindow(
                        id: wid,
                        pid: pid,
                        dictionary: window,
                        spaceIDs: [spaceID]
                    )
                )
            }
        }

        return makeWindowRecords(
            spaces: spaces,
            windowsBySpaceID: windowsBySpaceID,
            pidToAppPath: pidToAppPath,
            minimizedAXWindowIDs: minimizedAXWindowIDs
        )
    }

    private static func makeWindowRecords(
        spaces: [DesktopSpace],
        windowsBySpaceID: [String: [EnumeratedWindow]],
        pidToAppPath: [Int32: String],
        minimizedAXWindowIDs: Set<Int>
    ) -> [SpaceAPIWindow] {
        spaces
            .sorted {
                if $0.displayID != $1.displayID { return $0.displayID < $1.displayID }
                return $0.num < $1.num
            }
            .flatMap { space in
                (windowsBySpaceID[space.id] ?? []).compactMap { window -> SpaceAPIWindow? in
                    guard let appPath = pidToAppPath[window.pid] else { return nil }

                    return SpaceAPIWindow(
                        id: window.id,
                        pid: window.pid,
                        ownerName: window.dictionary[kCGWindowOwnerName as String] as? String ?? "",
                        appPath: appPath,
                        title: window.dictionary[kCGWindowName as String] as? String,
                        spaceID: space.id,
                        spaceIDs: window.spaceIDs,
                        isMinimized: minimizedAXWindowIDs.contains(window.id),
                        // macOS exposes hidden state on the owning application,
                        // not as a per-window attribute.
                        isHidden: NSRunningApplication(processIdentifier: window.pid)?.isHidden ?? false
                    )
                }
            }
    }

    /// Returns the historical delimiter-based representation for existing clients.
    /// New integrations should use getWindowRecordsForAllSpaces instead.
    static func getWindowsForAllSpaces(spaces: [DesktopSpace], spaceNames: [String: String]) -> String {
        guard let records = getWindowRecordsForAllSpacesIfAvailable(spaces: spaces) else { return "" }
        var screenMap: [String: String] = [:]
        for screen in NSScreen.screens {
            if let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
               let uuidRef = CGDisplayCreateUUIDFromDisplayID(id) {
                let uuid = uuidRef.takeRetainedValue()
                let uuidString = (CFUUIDCreateString(nil, uuid) as String).uppercased()
                screenMap[uuidString] = screen.localizedName
            }
        }
        let sortedSpaces = spaces.sorted {
            if $0.displayID != $1.displayID { return $0.displayID < $1.displayID }
            return $0.num < $1.num
        }
        let windowsBySpaceID = Dictionary(grouping: records, by: \.spaceID)

        var output = ""
        for space in sortedSpaces {
            output += SpaceAPILegacyFormatter.spaceLine(
                id: space.id,
                name: spaceNames[space.id] ?? "",
                displayName: getDisplayName(for: space.displayID, screenMap: screenMap),
                number: space.num,
                isFullscreen: space.isFullscreen,
                appPath: space.appPath
            )
            for window in windowsBySpaceID[space.id] ?? [] {
                output += SpaceAPILegacyFormatter.windowLine(
                    id: window.id,
                    pid: window.pid,
                    ownerName: window.ownerName,
                    appPath: window.appPath,
                    title: window.title,
                    isMinimized: window.isMinimized,
                    isHidden: window.isHidden
                )
            }
        }
        return output
    }
}
