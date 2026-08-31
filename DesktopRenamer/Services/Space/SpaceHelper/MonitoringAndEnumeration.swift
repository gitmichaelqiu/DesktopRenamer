import AppKit
import CoreGraphics
import Foundation

extension SpaceHelper {

    static func startMonitoring(onChange: @escaping (String, Bool, Int, String) -> Void) {
        // Make startup idempotent. The monitor is intentionally restarted after
        // system wake, and duplicate observers can otherwise multiply CGS reads.
        stopMonitoring()
        onSpaceChange = onChange

        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { _ in
            noteActiveSpaceDidChange()
            detectSpaceChange()
        }
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { _ in detectSpaceChange() }

        // Monitor events to detect user-initiated space switches.
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .leftMouseDown, .rightMouseDown,
        ]) { event in
            detectSpaceChange()
            return event
        }

        detectSpaceChange()
    }

    static func stopMonitoring() {
        spaceDetectionGeneration += 1
        programmaticSwitchCompletionWorkItem?.cancel()
        programmaticSwitchCompletionWorkItem = nil
        programmaticSwitchTimeoutWorkItem?.cancel()
        programmaticSwitchTimeoutWorkItem = nil
        fullscreenGestureRetryWorkItem?.cancel()
        fullscreenGestureRetryWorkItem = nil
        programmaticSwitchPromotionWorkItem?.cancel()
        programmaticSwitchPromotionWorkItem = nil
        programmaticSwitchPromotionRequest = nil
        programmaticSwitchPromotionGeneration = nil
        switchTransactionCoordinator.reset()
        isSwitching = false
        programmaticSwitchDestinationObserved = false
        programmaticSwitchNotificationObserved = false
        lastProgrammaticSwitchTime = 0
        lastProgrammaticTargetSpaceID = nil
        lastProgrammaticSwitchUsedSLS = false
        if let observer = spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            spaceChangeObserver = nil
        }
        if let observer = appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appActivationObserver = nil
        }
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        onSpaceChange = nil
    }

    private static func getActiveDisplay() -> NSScreen? {
        if let frontApp = NSWorkspace.shared.frontmostApplication,
            frontApp.bundleIdentifier != "com.apple.finder"
        {
            let options = CGWindowListOption(
                arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
            let windowList =
                CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []

            for window in windowList {
                if let pid = window[kCGWindowOwnerPID as String] as? Int,
                    pid == frontApp.processIdentifier,
                    let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                    let bounds = window[kCGWindowBounds as String] as? [String: Any],
                    let x = bounds["X"] as? CGFloat, let y = bounds["Y"] as? CGFloat,
                    let w = bounds["Width"] as? CGFloat, let h = bounds["Height"] as? CGFloat
                {
                    let center = CGPoint(x: x + w / 2, y: y + h / 2)
                    for screen in NSScreen.screens {
                        if isPoint(center, inside: screen.frame) { return screen }
                    }
                }
            }
        }
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
    }

    static func getRawSpaceUUID(completion: @escaping (String, Bool, Int, String) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard let activeScreen = getActiveDisplay() else {
                completion("", false, 0, "Unknown")
                return
            }
            let screenID =
                activeScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? NSNumber ?? 0
            
            var displayIdentifier = "\(activeScreen.localizedName) (\(screenID))"
            if let uuidRef = CGDisplayCreateUUIDFromDisplayID(screenID.uint32Value) {
                let uuid = uuidRef.takeRetainedValue()
                if let uuidStr = CFUUIDCreateString(nil, uuid) as String? {
                    displayIdentifier = uuidStr.uppercased()
                }
            }

            let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
            let windowList =
                CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []

            var uuid = ""
            var ncCnt = 0
            var hasFinderDesktop = false
            for window in windowList {
                guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                    let x = bounds["X"] as? CGFloat, let y = bounds["Y"] as? CGFloat,
                    let w = bounds["Width"] as? CGFloat, let h = bounds["Height"] as? CGFloat
                else { continue }

                if isPoint(CGPoint(x: x + w / 2, y: y + h / 2), inside: activeScreen.frame),
                    let owner = window[kCGWindowOwnerName as String] as? String
                {
                    if owner == "Dock", let name = window[kCGWindowName as String] as? String,
                        name.starts(with: "Wallpaper-")
                    {
                        uuid = String(name.dropFirst("Wallpaper-".count))
                        if uuid == "" { uuid = "MAIN" }
                    }
                    if owner == "Notification Center" { ncCnt += 1 }
                    if owner == "Finder", let layer = window[kCGWindowLayer as String] as? Int,
                        layer < 0
                    {
                        hasFinderDesktop = true
                    }
                }
            }
            completion(uuid, hasFinderDesktop, ncCnt, displayIdentifier)
        }
    }

    static func getAllDisplayUUIDs() -> [String] {
        return NSScreen.screens.compactMap { screen -> String? in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
            return CFUUIDCreateString(nil, uuid) as String
        }
    }

    static func normalizeDisplayID(_ id: String, mainUUID: String?) -> String {
        let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let uppercased = cleanId.uppercased()
        if cleanId.isEmpty || uppercased == "MAIN" || uppercased == "UNKNOWN" {
            return mainUUID?.uppercased() ?? "MAIN"
        }

        // CGS may report a display by its numeric screen identifier while
        // NSScreen and the persisted model use the display UUID. Canonicalize
        // that representation before assigning spaces or labels.
        if let screenNumber = UInt32(cleanId),
           NSScreen.screens.contains(where: {
               ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == screenNumber
           }),
           let uuidRef = CGDisplayCreateUUIDFromDisplayID(screenNumber) {
            return (CFUUIDCreateString(nil, uuidRef.takeRetainedValue()) as String).uppercased()
        }
        return cleanId.uppercased()
    }

    static func getSystemState(onDisplayID specificDisplayID: String? = nil) -> (
        spaces: [DesktopSpace], currentUUID: String, displayID: String
    )? {
        let conn = _CGSDefaultConnection()
        guard let displays = CGSCopyManagedDisplaySpaces(conn) as? [NSDictionary],
            let activeDisplayRaw = CGSCopyActiveMenuBarDisplayIdentifier(conn) as? String
        else {
            return nil
        }

        let screenUUIDs = getAllDisplayUUIDs()
        let mainScreenUUID = screenUUIDs.first
        
        let activeDisplay = normalizeDisplayID(activeDisplayRaw, mainUUID: mainScreenUUID)
        var targetDisplayID = specificDisplayID ?? activeDisplay
        var detectedSpaces: [DesktopSpace] = []
        var currentSpaceID = "FULLSCREEN"
        
        // Find if target display is actually present in CGS displays (handling normalization)
        let foundDisplay = displays.first { d in
            let dID = d["Display Identifier"] as? String ?? ""
            return normalizeDisplayID(dID, mainUUID: mainScreenUUID) == activeDisplay
        }
        
        if foundDisplay == nil {
            // If active display not found, fallback to Main
            targetDisplayID = mainScreenUUID ?? activeDisplay
        }

        var globalDesktopCounter = 0

        // SORT: Ensure displays are processed in the order macOS assigns shortcuts (Main then others).
        let sortedDisplays = displays.sorted { d1, d2 in
            guard let id1raw = d1["Display Identifier"] as? String,
                let id2raw = d2["Display Identifier"] as? String
            else { return false }
            
            let id1 = normalizeDisplayID(id1raw, mainUUID: mainScreenUUID)
            let id2 = normalizeDisplayID(id2raw, mainUUID: mainScreenUUID)
            
            let idx1 = screenUUIDs.firstIndex(of: id1) ?? Int.max
            let idx2 = screenUUIDs.firstIndex(of: id2) ?? Int.max
            return idx1 < idx2
        }

        for display in sortedDisplays {
            guard let displayIDRaw = display["Display Identifier"] as? String,
                let spaces = display["Spaces"] as? [[String: Any]]
            else { continue }
            
            let displayID = normalizeDisplayID(displayIDRaw, mainUUID: mainScreenUUID)

            var regularIndex = 0
            for space in spaces {
                guard let managedID = space["ManagedSpaceID"] as? Int else { continue }
                let idString = String(managedID)
                let isFullscreen = space["TileLayoutManager"] != nil

                var appName: String? = nil
                var appPath: String? = nil
                var globalShortcutNum: Int? = nil

                if isFullscreen {
                    if let p = space["pid"] as? Int32 ?? space["owner pid"] as? Int32 {
                        if let runningApp = NSRunningApplication(processIdentifier: p) {
                            appName = runningApp.localizedName
                            appPath = runningApp.bundleURL?.path
                        }
                    }
                } else {
                    globalDesktopCounter += 1
                    globalShortcutNum = globalDesktopCounter
                }

                regularIndex += 1
                detectedSpaces.append(
                    DesktopSpace(
                        id: idString,
                        customName: "",
                        num: regularIndex,
                        displayID: displayID,
                        isFullscreen: isFullscreen,
                        appName: appName,
                        appPath: appPath,
                        globalShortcutNum: globalShortcutNum
                    ))

                if let currentDict = display["Current Space"] as? [String: Any],
                    let currentID = currentDict["ManagedSpaceID"] as? Int, currentID == managedID
                {
                    if displayID == targetDisplayID {
                        currentSpaceID = idString
                    }
                }
            }
        }
        return (detectedSpaces, currentSpaceID, targetDisplayID)
    }

    static func getVisibleSystemSpaceIDs() -> Set<String> {
        let conn = _CGSDefaultConnection()
        guard let displays = CGSCopyManagedDisplaySpaces(conn) as? [NSDictionary] else { return [] }
        var visibleIDs = Set<String>()
        for display in displays {
            if let currentDict = display["Current Space"] as? [String: Any],
                let currentID = currentDict["ManagedSpaceID"] as? Int
            {
                visibleIDs.insert(String(currentID))
            }
        }
        return visibleIDs
    }
}

extension SpaceHelper {

    // MARK: - Window Enumeration

    /// Filters a CGWindowList dictionary to real, visible app windows.
    /// Excludes: non-layer-0, empty titles, tiny windows, invisible windows, and our own process.
    private static func isValidWindow(
        _ window: [String: Any], ourPID: Int32, minSize: CGFloat = 50
    ) -> Bool {
        guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
              let title = window[kCGWindowName as String] as? String, !title.isEmpty,
              let pid = window[kCGWindowOwnerPID as String] as? Int, pid != Int(ourPID),
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let w = bounds["Width"] as? CGFloat, let h = bounds["Height"] as? CGFloat,
              w >= minSize, h >= minSize
        else { return false }
        // Reject invisible windows when the key is present.
        if let alpha = window[kCGWindowAlpha as String] as? Double, alpha < 0 { return false }
        // Reject windows with sharing state "none" (hidden helper windows like WeChat background).
        if let sharing = window[kCGWindowSharingState as String] as? Int, sharing == 0 { return false }
        return true
    }

    static func getWindowRecordsForAllSpaces(spaces: [DesktopSpace]) -> [SpaceAPIWindow] {
        let conn = _CGSDefaultConnection()
        let ourPID = ProcessInfo.processInfo.processIdentifier

        // Build PID → app bundle path cache from running applications.
        // Only include apps with .regular activation policy (shown in Dock).
        // This excludes background agents like Ollama, menu bar-only apps, etc.
        var pidToAppPath: [Int32: String] = [:]
        var axWindowIDs = Set<Int>()
        var minimizedAXWindowIDs = Set<Int>()
        for app in NSWorkspace.shared.runningApplications {
            if app.activationPolicy == .regular, let path = app.bundleURL?.path {
                pidToAppPath[app.processIdentifier] = path

                // Get all valid window IDs directly from the app's Accessibility hierarchy.
                // This definitively eliminates closed/ghost windows that CGWindowList retains.
                let appElement = AXUIElementCreateApplication(app.processIdentifier)

                let extractWID = { (element: AXUIElement) in
                    var cgWID: CGWindowID = 0
                    if _AXUIElementGetWindow(element, &cgWID) == 0 {
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
                if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                   let axWindows = windowsRef as? [AXUIElement] {
                    axWindows.forEach(extractWID)
                }

                // 2. Check AXChildren for non-standard apps (e.g., Preview)
                if app.bundleIdentifier == "com.apple.Preview" {
                    var childrenRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(appElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                       let axChildren = childrenRef as? [AXUIElement] {
                        axChildren.forEach(extractWID)
                    }
                }
            }
        }

        // Get ALL windows, not just on-screen, to include off-screen spaces.
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements)
        guard let allWindows = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as? [[String: Any]]
        else { return [] }

        // Collect valid windows with their IDs.
        var validWindows: [(wid: Int, dict: [String: Any])] = []
        for window in allWindows {
            guard isValidWindow(window, ourPID: ourPID),
                  let wid = window[kCGWindowNumber as String] as? Int,
                  let pid = window[kCGWindowOwnerPID as String] as? Int,
                  pidToAppPath[Int32(pid)] != nil  // skip windows without bundle path
            else { continue }
            validWindows.append((wid: wid, dict: window))
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

        var windowsBySpaceID: [String: [[String: Any]]] = [:]
        
        // Query each window individually for its space assignment.
        for (wid, dict) in validWindows {
            let widArray = [wid as NSNumber] as CFArray
            guard let result = CGSCopySpacesForWindows(conn, 7, widArray),
                  let spaceIDs = result as? [NSNumber],
                  let firstSpace = spaceIDs.first
            else { continue }

            let spaceID = firstSpace.intValue
            guard knownSpaceIDs.contains(spaceID) else { continue }
            
            // AX Validation: If the window is on an ACTIVE space, it MUST be in axWindowIDs.
            // If it's on an inactive space, AX can't see it anyway, so we allow it.
            if activeSpaceIDs.contains(spaceID) {
                guard axWindowIDs.contains(wid) else { continue }
            }
            
            windowsBySpaceID[String(spaceID), default: []].append(dict)
        }

        // Fallback: assign windows to current space per display if CGS API unavailable or empty.
        if windowsBySpaceID.isEmpty {
            // Build current-space-per-display map and fullscreen PID→space map.
            guard let displays = CGSCopyManagedDisplaySpaces(conn) as? [NSDictionary] else { return [] }
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

            // Only on-screen windows for fallback.
            let onScreenOptions = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
            let onScreenWindows = CGWindowListCopyWindowInfo(onScreenOptions, kCGNullWindowID)
                as? [[String: Any]] ?? []

            for window in onScreenWindows {
                guard isValidWindow(window, ourPID: ourPID),
                      let wid = window[kCGWindowNumber as String] as? Int,
                      axWindowIDs.contains(wid),
                      let pid = window[kCGWindowOwnerPID as String] as? Int,
                      pidToAppPath[Int32(pid)] != nil,
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
                windowsBySpaceID[spaceID, default: []].append(window)
            }
        }

        return spaces
            .sorted {
                if $0.displayID != $1.displayID { return $0.displayID < $1.displayID }
                return $0.num < $1.num
            }
            .flatMap { space in
                (windowsBySpaceID[space.id] ?? []).compactMap { window -> SpaceAPIWindow? in
                    guard let wid = window[kCGWindowNumber as String] as? Int,
                          let pid = window[kCGWindowOwnerPID as String] as? Int,
                          let appPath = pidToAppPath[Int32(pid)] else { return nil }

                    return SpaceAPIWindow(
                        id: wid,
                        pid: Int32(pid),
                        ownerName: window[kCGWindowOwnerName as String] as? String ?? "",
                        appPath: appPath,
                        title: window[kCGWindowName as String] as? String,
                        spaceID: space.id,
                        isMinimized: minimizedAXWindowIDs.contains(wid),
                        isHidden: NSRunningApplication(processIdentifier: Int32(pid))?.isHidden ?? false
                    )
                }
            }
    }

    /// Returns the historical delimiter-based representation for existing clients.
    /// New integrations should use getWindowRecordsForAllSpaces instead.
    static func getWindowsForAllSpaces(spaces: [DesktopSpace], spaceNames: [String: String]) -> String {
        let records = getWindowRecordsForAllSpaces(spaces: spaces)
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
            for window in records where window.spaceID == space.id {
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
