import AppKit
import CoreGraphics
import Foundation

extension SpaceHelper {

    static func startMonitoring(
        onChange: @escaping (String, Bool, Int, String) -> Void,
        onAuthoritativeChange: (([String: String]) -> Void)? = nil
    ) {
        // Make startup idempotent. The monitor is intentionally restarted after
        // system wake, and duplicate observers can otherwise multiply CGS reads.
        stopMonitoring()
        onSpaceChange = onChange
        onAuthoritativeSpaceChange = onAuthoritativeChange

        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { _ in
            let currentSpaceIDsByDisplay = getCurrentSpaceIDsByDisplay()
            let traceID = debugTraceID()
            debugTrace(
                traceID,
                "activeSpaceDidChange authoritativeSnapshot=\(debugFormatSpaceMap(currentSpaceIDsByDisplay)), managerSwitching=\(isSwitching), managerTarget=\(activeProgrammaticSwitchTargetSpaceID ?? "nil"), display=\(programmaticSwitchDisplayID ?? "nil")"
            )
            noteActiveSpaceDidChange(currentSpaceIDsByDisplay)
            onAuthoritativeSpaceChange?(currentSpaceIDsByDisplay)
            detectSpaceChange()
        }
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { notification in
            let activatedApplication = notification.userInfo?[
                NSWorkspace.applicationUserInfoKey
            ] as? NSRunningApplication ?? notification.object as? NSRunningApplication
            guard activatedApplication?.processIdentifier
                    != ProcessInfo.processInfo.processIdentifier else {
                return
            }
            detectSpaceChange()
        }

        // Monitor events to detect user-initiated space switches.
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .leftMouseDown, .rightMouseDown,
        ]) { event in
            // Clicking an active label can activate DesktopRenamer, but it is
            // not a user-initiated Space change. Scanning here can reconcile
            // the wrong display while WindowServer is processing that
            // activation and make the label manager order another label in.
            if event.window is SpaceLabelWindow {
                return event
            }
            detectSpaceChange()
            return event
        }

        detectSpaceChange()
    }

    static func stopMonitoring() {
        spaceDetectionGeneration += 1
        cancelPendingRawSpaceUUIDScan()
        programmaticSwitchCompletionWorkItem?.cancel()
        programmaticSwitchCompletionWorkItem = nil
        programmaticSwitchTimeoutWorkItem?.cancel()
        programmaticSwitchTimeoutWorkItem = nil
        syntheticGestureRetryWorkItem?.cancel()
        syntheticGestureRetryWorkItem = nil
        programmaticSwitchPromotionWorkItem?.cancel()
        programmaticSwitchPromotionWorkItem = nil
        programmaticSwitchPromotionRequest = nil
        programmaticSwitchPromotionGeneration = nil
        switchTransactionCoordinator.reset()
        isSwitching = false
        programmaticSwitchDestinationObserved = false
        programmaticSwitchNotificationObserved = false
        programmaticSwitchUsesExtendedSettle = false
        programmaticSwitchFastFollowUpRequested = false
        lastProgrammaticSwitchTime = 0
        lastProgrammaticTargetSpaceID = nil
        programmaticSwitchDisplayID = nil
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
        onAuthoritativeSpaceChange = nil
    }

    private struct RawSpaceScreen {
        let screenID: CGDirectDisplayID
        let frame: CGRect
        let localizedName: String
    }

    private struct RawSpaceScanContext {
        let screens: [RawSpaceScreen]
        let primaryScreenMaxY: CGFloat
        let frontmostProcessID: Int32?
        let mouseLocation: CGPoint
    }

    private struct RawSpaceScanResult {
        let uuid: String
        let hasFinderDesktop: Bool
        let notificationCount: Int
        let displayIdentifier: String
    }

    private static func makeRawSpaceScanContext() -> RawSpaceScanContext? {
        let screens = NSScreen.screens.compactMap { screen -> RawSpaceScreen? in
            guard let screenID = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? CGDirectDisplayID else {
                return nil
            }
            return RawSpaceScreen(
                screenID: screenID,
                frame: screen.frame,
                localizedName: screen.localizedName
            )
        }
        guard !screens.isEmpty else { return nil }

        let primaryScreenMaxY = NSScreen.screens.first(where: {
            $0.frame.origin.x == 0 && $0.frame.origin.y == 0
        })?.frame.maxY ?? screens[0].frame.maxY

        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let frontmostProcessID: Int32?
        if frontmostApplication?.bundleIdentifier == "com.apple.finder" {
            frontmostProcessID = nil
        } else {
            frontmostProcessID = frontmostApplication?.processIdentifier
        }

        return RawSpaceScanContext(
            screens: screens,
            primaryScreenMaxY: primaryScreenMaxY,
            frontmostProcessID: frontmostProcessID,
            mouseLocation: NSEvent.mouseLocation
        )
    }

    private static func isPoint(
        _ point: CGPoint,
        inside screenFrame: CGRect,
        primaryScreenMaxY: CGFloat
    ) -> Bool {
        let flippedY = primaryScreenMaxY - point.y
        return screenFrame.contains(CGPoint(x: point.x, y: flippedY))
    }

    private static func scanRawSpace(_ context: RawSpaceScanContext) -> RawSpaceScanResult? {
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
        let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
            as? [[String: Any]] ?? []

        var activeScreen: RawSpaceScreen?
        if let frontmostProcessID = context.frontmostProcessID {
            for window in windowList {
                guard let pid = window[kCGWindowOwnerPID as String] as? Int,
                      pid == Int(frontmostProcessID),
                      let layer = window[kCGWindowLayer as String] as? Int,
                      layer == 0,
                      let bounds = window[kCGWindowBounds as String] as? [String: Any],
                      let x = bounds["X"] as? CGFloat,
                      let y = bounds["Y"] as? CGFloat,
                      let width = bounds["Width"] as? CGFloat,
                      let height = bounds["Height"] as? CGFloat else {
                    continue
                }

                let center = CGPoint(x: x + width / 2, y: y + height / 2)
                activeScreen = context.screens.first(where: {
                    isPoint(
                        center,
                        inside: $0.frame,
                        primaryScreenMaxY: context.primaryScreenMaxY
                    )
                })
                if activeScreen != nil { break }
            }
        }

        if activeScreen == nil {
            activeScreen = context.screens.first(where: {
                isPoint(
                    context.mouseLocation,
                    inside: $0.frame,
                    primaryScreenMaxY: context.primaryScreenMaxY
                )
            })
        }

        guard let activeScreen else {
            return RawSpaceScanResult(
                uuid: "",
                hasFinderDesktop: false,
                notificationCount: 0,
                displayIdentifier: "Unknown"
            )
        }

        let displayIdentifier = activeScreen.localizedName
            + " ("
            + String(activeScreen.screenID)
            + ")"
        var resolvedDisplayIdentifier = displayIdentifier
        if let uuidRef = CGDisplayCreateUUIDFromDisplayID(activeScreen.screenID) {
            let uuid = uuidRef.takeRetainedValue()
            if let uuidString = CFUUIDCreateString(nil, uuid) as String? {
                resolvedDisplayIdentifier = uuidString.uppercased()
            }
        }

        var uuid = ""
        var notificationCount = 0
        var hasFinderDesktop = false
        for window in windowList {
            guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? CGFloat,
                  let y = bounds["Y"] as? CGFloat,
                  let width = bounds["Width"] as? CGFloat,
                  let height = bounds["Height"] as? CGFloat,
                  isPoint(
                      CGPoint(x: x + width / 2, y: y + height / 2),
                      inside: activeScreen.frame,
                      primaryScreenMaxY: context.primaryScreenMaxY
                  ),
                  let owner = window[kCGWindowOwnerName as String] as? String else {
                continue
            }

            if owner == "Dock",
               let name = window[kCGWindowName as String] as? String,
               name.starts(with: "Wallpaper-") {
                uuid = String(name.dropFirst("Wallpaper-".count))
                if uuid.isEmpty { uuid = "MAIN" }
            }
            if owner == "Notification Center" {
                notificationCount += 1
            }
            if owner == "Finder",
               let layer = window[kCGWindowLayer as String] as? Int,
               layer < 0 {
                hasFinderDesktop = true
            }
        }

        return RawSpaceScanResult(
            uuid: uuid,
            hasFinderDesktop: hasFinderDesktop,
            notificationCount: notificationCount,
            displayIdentifier: resolvedDisplayIdentifier
        )
    }

    static func getRawSpaceUUID(completion: @escaping (String, Bool, Int, String) -> Void) {
        // Snapshot AppKit state and schedule the scan from the main queue.
        // Callers are normally already on main, but this also prevents a
        // background caller from racing the monitor lifecycle state.
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                getRawSpaceUUID(completion: completion)
            }
            return
        }

        rawSpaceUUIDStateLock.lock()
        rawSpaceUUIDWorkItem?.cancel()
        rawSpaceUUIDGeneration += 1
        let generation = rawSpaceUUIDGeneration
        let traceID = debugTraceID()
        debugTrace(
            traceID,
            "rawSpaceScan scheduled rawGeneration=\(generation), detectionGeneration=\(spaceDetectionGeneration)"
        )

        let workItem = DispatchWorkItem {
            rawSpaceUUIDStateLock.lock()
            guard generation == rawSpaceUUIDGeneration else {
                rawSpaceUUIDStateLock.unlock()
                debugTrace(
                    traceID,
                    "rawSpaceScan canceled before context rawGeneration=\(generation), currentRawGeneration=\(rawSpaceUUIDGeneration)"
                )
                return
            }
            // Clear this before invoking the callback. The callback may
            // immediately request another scan, which must remain registered.
            rawSpaceUUIDWorkItem = nil
            rawSpaceUUIDStateLock.unlock()

            guard let context = makeRawSpaceScanContext() else {
                guard isCurrentRawSpaceUUIDGeneration(generation) else { return }
                debugTrace(traceID, "rawSpaceScan has no context; publishing empty result")
                completion("", false, 0, "Unknown")
                return
            }

            // CGWindowListCopyWindowInfo is independent of AppKit state. Run
            // the potentially expensive enumeration away from the main queue,
            // then deliver the existing callback contract back on main.
            DispatchQueue.global(qos: .userInitiated).async {
                guard let result = scanRawSpace(context) else { return }
                DispatchQueue.main.async {
                    guard isCurrentRawSpaceUUIDGeneration(generation) else { return }
                    debugTrace(
                        traceID,
                        "rawSpaceScan completed rawGeneration=\(generation), raw=\(result.uuid), display=\(result.displayIdentifier), desktop=\(result.hasFinderDesktop), notifications=\(result.notificationCount)"
                    )
                    completion(
                        result.uuid,
                        result.hasFinderDesktop,
                        result.notificationCount,
                        result.displayIdentifier
                    )
                }
            }
        }

        rawSpaceUUIDWorkItem = workItem
        rawSpaceUUIDStateLock.unlock()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }

    /// Cancels a pending raw space scan without blocking the multitouch
    /// callback. The generation check also discards a scan that has already
    /// started but has not reached its completion callback.
    static func cancelPendingRawSpaceUUIDScan() {
        rawSpaceUUIDStateLock.lock()
        rawSpaceUUIDGeneration += 1
        let workItem = rawSpaceUUIDWorkItem
        rawSpaceUUIDWorkItem = nil
        rawSpaceUUIDStateLock.unlock()
        workItem?.cancel()
    }

    private static func isCurrentRawSpaceUUIDGeneration(_ generation: Int) -> Bool {
        rawSpaceUUIDStateLock.lock()
        defer { rawSpaceUUIDStateLock.unlock() }
        return generation == rawSpaceUUIDGeneration
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

    static func getSystemState(
        onDisplayID specificDisplayID: String? = nil,
        includeFullscreenAppMetadata: Bool = true
    ) -> (
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
                let rawPersistentID = space["uuid"] as? String
                let persistentID = rawPersistentID.flatMap {
                    let normalized = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                        .uppercased()
                    return normalized.isEmpty ? nil : normalized
                }

                var appName: String? = nil
                var appPath: String? = nil
                var globalShortcutNum: Int? = nil

                if isFullscreen, includeFullscreenAppMetadata {
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
                        globalShortcutNum: globalShortcutNum,
                        persistentID: persistentID
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
        Set(getCurrentSpaceIDsByDisplay().values)
    }
}
