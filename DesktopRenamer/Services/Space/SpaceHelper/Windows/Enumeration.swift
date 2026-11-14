import AppKit
import CoreGraphics
import Foundation

extension SpaceHelper {

    // MARK: - Window Enumeration

    /// Filters plausible CGWindow candidates using their title and AX status.
    /// Accessibility-confirmed windows are trusted even when their title is
    /// empty. CG-only records need stronger evidence so helper windows do not
    /// leak into the launcher.
    private static func isValidWindow(
        _ window: [String: Any],
        activationPolicy: NSApplication.ActivationPolicy,
        isAXWindow: Bool
    ) -> Bool {
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

    private static func isPotentialWindowSurface(
        _ window: [String: Any],
        ourPID: Int32,
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

    private struct WindowCandidate {
        let id: Int
        let pid: Int32
        let dictionary: [String: Any]
        let activationPolicy: NSApplication.ActivationPolicy
    }

    private static let accessibilityMessageTimeout: Float = 0.25

    static func getWindowRecordsForAllSpaces(spaces: [DesktopSpace]) -> [SpaceAPIWindow] {
        getWindowRecordsForAllSpacesIfAvailable(spaces: spaces) ?? []
    }

    private static func getWindowRecordsForAllSpacesIfAvailable(spaces: [DesktopSpace]) -> [SpaceAPIWindow]? {
        let enumerationStartedAt = ProcessInfo.processInfo.systemUptime
        var runningApplicationCount = 0
        var candidateApplicationCount = 0
        var candidateWindowCount = 0
        var validWindowCount = 0
        var spaceFallbackCandidateCount = 0
        var timedOutAccessibilityApplicationCount = 0
        var timedOutMinimizedStateApplicationCount = 0
        var applicationMetadataDuration: TimeInterval = 0
        var coreGraphicsDiscoveryDuration: TimeInterval = 0
        var accessibilityDuration: TimeInterval = 0
        var spaceAssignmentDuration: TimeInterval = 0
        var recordAssemblyDuration: TimeInterval = 0

        defer {
            let totalDuration = ProcessInfo.processInfo.systemUptime - enumerationStartedAt
            DiagnosticEventLog.shared.recordDuringCollection(
                subsystem: "SpaceAPI",
                level: "debug",
                "getWindows enumeration: total=\(String(format: "%.3f", totalDuration))s, " +
                    "metadata=\(String(format: "%.3f", applicationMetadataDuration))s, " +
                    "coreGraphics=\(String(format: "%.3f", coreGraphicsDiscoveryDuration))s, " +
                    "accessibility=\(String(format: "%.3f", accessibilityDuration))s, " +
                    "spaceAssignment=\(String(format: "%.3f", spaceAssignmentDuration))s, " +
                    "recordAssembly=\(String(format: "%.3f", recordAssemblyDuration))s, " +
                    "runningApps=\(runningApplicationCount), candidateApps=\(candidateApplicationCount), " +
                    "candidateWindows=\(candidateWindowCount), validWindows=\(validWindowCount), " +
                    "spaceFallbackCandidates=\(spaceFallbackCandidateCount), " +
                    "timedOutAXApps=\(timedOutAccessibilityApplicationCount), " +
                    "timedOutMinimizedStateApps=\(timedOutMinimizedStateApplicationCount)"
            )
        }

        let conn = _CGSDefaultConnection()
        let ourPID = ProcessInfo.processInfo.processIdentifier

        // Build PID → app bundle path cache from running applications. Include
        // accessory applications as well as regular applications because an
        // accessory app can still own user-facing windows.
        let runningApplications = NSWorkspace.shared.runningApplications
        runningApplicationCount = runningApplications.count
        var pidToAppPath: [Int32: String] = [:]
        var pidToAppName: [Int32: String] = [:]
        var pidToActivationPolicy: [Int32: NSApplication.ActivationPolicy] = [:]
        for app in runningApplications {
            if app.activationPolicy != .prohibited, let path = app.bundleURL?.path {
                let pid = app.processIdentifier
                pidToAppPath[pid] = path
                if let name = app.localizedName, !name.isEmpty {
                    pidToAppName[pid] = name
                }
                pidToActivationPolicy[pid] = app.activationPolicy
            }
        }
        applicationMetadataDuration = ProcessInfo.processInfo.systemUptime - enumerationStartedAt

        // Get ALL windows, not just on-screen, to include off-screen spaces.
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements)
        let coreGraphicsDiscoveryStartedAt = ProcessInfo.processInfo.systemUptime
        guard let allWindows = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as? [[String: Any]]
        else {
            coreGraphicsDiscoveryDuration = ProcessInfo.processInfo.systemUptime - coreGraphicsDiscoveryStartedAt
            return nil
        }

        // Accessibility is only needed for apps that own a plausible window.
        // Querying every running app makes this request wait on unrelated
        // background processes that cannot contribute a window to the result.
        let candidateWindows = allWindows.compactMap { window -> WindowCandidate? in
            guard let wid = window[kCGWindowNumber as String] as? Int,
                  let rawPID = window[kCGWindowOwnerPID as String] as? Int,
                  let pid = Int32(exactly: rawPID),
                  let activationPolicy = pidToActivationPolicy[pid],
                  isPotentialWindowSurface(window, ourPID: ourPID)
            else { return nil }

            return WindowCandidate(
                id: wid,
                pid: pid,
                dictionary: window,
                activationPolicy: activationPolicy
            )
        }
        let candidateWindowIDs = Set(candidateWindows.map(\.id))
        let candidatePIDs = Set(candidateWindows.map(\.pid))
        candidateWindowCount = candidateWindows.count
        candidateApplicationCount = candidatePIDs.count
        coreGraphicsDiscoveryDuration = ProcessInfo.processInfo.systemUptime - coreGraphicsDiscoveryStartedAt

        var axWindowIDs = Set<Int>()
        var minimizedAXWindowIDs = Set<Int>()
        var axWindowEnumerationSucceededPIDs = Set<Int32>()

        let accessibilityStartedAt = ProcessInfo.processInfo.systemUptime
        for app in runningApplications where candidatePIDs.contains(app.processIdentifier) {
            let pid = app.processIdentifier

            // An unresponsive app must not hold the complete SpaceAPI window
            // request beyond Raycast's short read timeout.
            let appElement = AXUIElementCreateApplication(pid)
            _ = AXUIElementSetMessagingTimeout(appElement, Self.accessibilityMessageTimeout)

            var didAXMessagingTimeOut = false
            var didMinimizedStateMessagingTimeOut = false
            let extractWID = { (element: AXUIElement, requireWindowRole: Bool) in
                guard !didAXMessagingTimeOut else { return }

                if requireWindowRole {
                    _ = AXUIElementSetMessagingTimeout(element, Self.accessibilityMessageTimeout)
                    var roleRef: CFTypeRef?
                    let roleResult = AXUIElementCopyAttributeValue(
                        element,
                        kAXRoleAttribute as CFString,
                        &roleRef
                    )
                    guard roleResult == .success,
                          let role = roleRef as? String,
                          userWindowAXRoles.contains(role) else {
                        if roleResult == .cannotComplete {
                            didAXMessagingTimeOut = true
                        }
                        return
                    }
                }

                var cgWID: CGWindowID = 0
                guard _AXUIElementGetWindow(element, &cgWID) == 0, cgWID != 0 else { return }
                let wid = Int(cgWID)
                guard candidateWindowIDs.contains(wid) else { return }

                axWindowIDs.insert(wid)
                guard !didMinimizedStateMessagingTimeOut else { return }

                _ = AXUIElementSetMessagingTimeout(element, Self.accessibilityMessageTimeout)
                var minimizedRef: CFTypeRef?
                let minimizedResult = AXUIElementCopyAttributeValue(
                    element,
                    kAXMinimizedAttribute as CFString,
                    &minimizedRef
                )
                if minimizedResult == .success,
                   let isMinimized = minimizedRef as? Bool,
                   isMinimized {
                    minimizedAXWindowIDs.insert(wid)
                } else if minimizedResult == .cannotComplete {
                    didMinimizedStateMessagingTimeOut = true
                }
            }

            // 1. Check standard AXWindows attribute (open windows).
            var windowsRef: CFTypeRef?
            var didEnumerateWindows = false
            let windowsResult = AXUIElementCopyAttributeValue(
                appElement,
                kAXWindowsAttribute as CFString,
                &windowsRef
            )
            if windowsResult == .success, let axWindows = windowsRef as? [AXUIElement] {
                axWindowEnumerationSucceededPIDs.insert(pid)
                axWindows.forEach { extractWID($0, false) }
                didEnumerateWindows = true
            } else if windowsResult == .cannotComplete {
                didAXMessagingTimeOut = true
            }

            // 2. Some applications expose their windows as children instead
            // of through AXWindows (e.g., Preview). Use this as a fallback
            // for every app, not only known bundle IDs.
            if (!didEnumerateWindows || app.bundleIdentifier == "com.apple.Preview"),
               !didAXMessagingTimeOut {
                var childrenRef: CFTypeRef?
                let childrenResult = AXUIElementCopyAttributeValue(
                    appElement,
                    kAXChildrenAttribute as CFString,
                    &childrenRef
                )
                if childrenResult == .success, let axChildren = childrenRef as? [AXUIElement] {
                    axChildren.forEach { extractWID($0, true) }
                    if !didAXMessagingTimeOut {
                        axWindowEnumerationSucceededPIDs.insert(pid)
                    }
                } else if childrenResult == .cannotComplete {
                    didAXMessagingTimeOut = true
                }
            }

            if didAXMessagingTimeOut {
                timedOutAccessibilityApplicationCount += 1
            }
            if didMinimizedStateMessagingTimeOut {
                timedOutMinimizedStateApplicationCount += 1
            }
        }
        accessibilityDuration = ProcessInfo.processInfo.systemUptime - accessibilityStartedAt

        // Collect valid windows after Accessibility IDs are known.
        let validWindows = candidateWindows.filter { window in
            isValidWindow(
                window.dictionary,
                activationPolicy: window.activationPolicy,
                isAXWindow: axWindowIDs.contains(window.id)
            )
        }
        validWindowCount = validWindows.count

        // Known space IDs.
        let knownSpaceIDs = Set(spaces.compactMap { Int($0.id) })

        // Get active space IDs
        let spaceAssignmentStartedAt = ProcessInfo.processInfo.systemUptime
        var activeSpaceIDs = Set<Int>()
        if let displays = CGSCopyManagedDisplaySpaces(conn) as? [NSDictionary] {
            for display in displays {
                if let currentDict = display["Current Space"] as? [String: Any],
                   let currentID = managedIntegerValue(currentDict["ManagedSpaceID"]) {
                    activeSpaceIDs.insert(currentID)
                }
            }
        }

        var windowsBySpaceID: [String: [EnumeratedWindow]] = [:]
        var windowsWithoutSpace: [(wid: Int, pid: Int32, dict: [String: Any])] = []

        // Query each window individually for its space assignment.
        for window in validWindows {
            let wid = window.id
            let pid = window.pid
            let dict = window.dictionary
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
                guard !windowsBySpaceID.isEmpty else { return nil }
                spaceFallbackCandidateCount = windowsWithoutSpace.count
                spaceAssignmentDuration = ProcessInfo.processInfo.systemUptime - spaceAssignmentStartedAt

                let recordAssemblyStartedAt = ProcessInfo.processInfo.systemUptime
                let records = makeWindowRecords(
                    spaces: spaces,
                    windowsBySpaceID: windowsBySpaceID,
                    pidToAppPath: pidToAppPath,
                    pidToAppName: pidToAppName,
                    minimizedAXWindowIDs: minimizedAXWindowIDs
                )
                recordAssemblyDuration = ProcessInfo.processInfo.systemUptime - recordAssemblyStartedAt
                return records
            }
            spaceFallbackCandidateCount = windowsWithoutSpace.count
            let mainUUID = getMainDisplayUUID()
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
                    guard let managedID = managedIntegerValue(space["ManagedSpaceID"]) else { continue }
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

        spaceAssignmentDuration = ProcessInfo.processInfo.systemUptime - spaceAssignmentStartedAt

        let recordAssemblyStartedAt = ProcessInfo.processInfo.systemUptime
        let records = makeWindowRecords(
            spaces: spaces,
            windowsBySpaceID: windowsBySpaceID,
            pidToAppPath: pidToAppPath,
            pidToAppName: pidToAppName,
            minimizedAXWindowIDs: minimizedAXWindowIDs
        )
        recordAssemblyDuration = ProcessInfo.processInfo.systemUptime - recordAssemblyStartedAt
        return records
    }

    private static func makeWindowRecords(
        spaces: [DesktopSpace],
        windowsBySpaceID: [String: [EnumeratedWindow]],
        pidToAppPath: [Int32: String],
        pidToAppName: [Int32: String],
        minimizedAXWindowIDs: Set<Int>
    ) -> [SpaceAPIWindow] {
        let windowPIDs = Set(windowsBySpaceID.values.flatMap { $0.map(\.pid) })
        var pidToIsHidden: [Int32: Bool] = [:]
        for pid in windowPIDs {
            pidToIsHidden[pid] = NSRunningApplication(processIdentifier: pid)?.isHidden ?? false
        }

        return spaces
            .sorted {
                if $0.displayID != $1.displayID { return $0.displayID < $1.displayID }
                return $0.num < $1.num
            }
            .flatMap { space in
                (windowsBySpaceID[space.id] ?? []).compactMap { window -> SpaceAPIWindow? in
                    guard let appPath = pidToAppPath[window.pid] else { return nil }

                    let rawOwnerName = window.dictionary[kCGWindowOwnerName as String] as? String
                    let ownerName: String
                    if let rawOwnerName,
                       !rawOwnerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ownerName = rawOwnerName
                    } else {
                        ownerName = pidToAppName[window.pid] ?? ""
                    }
                    let rawTitle = window.dictionary[kCGWindowName as String] as? String
                    let title = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? rawTitle
                        : (ownerName.isEmpty ? nil : ownerName)

                    return SpaceAPIWindow(
                        id: window.id,
                        pid: window.pid,
                        ownerName: ownerName,
                        appPath: appPath,
                        title: title,
                        spaceID: space.id,
                        spaceIDs: window.spaceIDs,
                        isMinimized: minimizedAXWindowIDs.contains(window.id),
                        // macOS exposes hidden state on the owning application,
                        // not as a per-window attribute.
                        isHidden: pidToIsHidden[window.pid] ?? false
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
