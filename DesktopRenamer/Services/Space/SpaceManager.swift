import Foundation
import AppKit
import SwiftUI
import WidgetKit

class SpaceManager: ObservableObject {
    // App group ID for sharing data with the widget extension
    static let appGroupId = "group.com.michaelqiu.DesktopRenamer"
    
    static private let spacesKey = "com.michaelqiu.desktoprenamer.spaces"
    static private let nameCacheKey = "com.michaelqiu.desktoprenamer.namecache"
    static private let indexCacheKey = "com.michaelqiu.desktoprenamer.indexcache"
    static private let isAPIEnabledKey = "com.michaelqiu.desktoprenamer.isapienabled"
    static private let grabOffsetXKey = "com.michaelqiu.desktoprenamer.grabOffsetX"
    static private let grabOffsetYKey = "com.michaelqiu.desktoprenamer.grabOffsetY"
    static private let lockedSpaceIDsKey = "com.michaelqiu.desktoprenamer.lockedSpaceIDs"
    static private let movedWindowsOriginalSpacesKey = "com.michaelqiu.desktoprenamer.movedWindowsOriginalSpaces"
    static private let returnToOriginalAfterBatchMoveKey = "com.michaelqiu.desktoprenamer.returnToOriginalAfterBatchMove"
    static private let appGrabExceptionsKey = "com.michaelqiu.desktoprenamer.appGrabExceptions"
    
    @Published private(set) var currentSpaceUUID: String = ""
    @Published private(set) var currentRawSpaceUUID: String = ""
    @Published private(set) var currentDisplayID: String = "Main"
    @Published var autoEditBundleID: String? = nil
    
    // Tracks active space per display to ensure local switching context
    private(set) var currentSpaceByDisplay: [String: String] = [:]
    
    @Published var spaceNameDict: [DesktopSpace] = []
    
    // Convenience views for the current display
    var currentDisplaySpaces: [DesktopSpace] {
        spaceNameDict
            .filter { $0.displayID == currentDisplayID }
            .sorted { $0.num < $1.num }
    }
    
    private var nameCache: [String: String] = [:]
    private var indexCache: [String: String] = [:]
    
    @Published var currentNcCount: Int = 0
    @Published var currentIsDesktop: Bool = false
    
    // Widget Debouncer
    private var widgetUpdateWorkItem: DispatchWorkItem?
    
    // Stabilization state for system wake events
    private var lastWakeTime: Date = .distantPast
    private let wakeCoolingDuration: TimeInterval = 15.0

    // Retry state for space change detection (Cmd+Tab switches can fire notifications
    // before CGS state stabilizes, causing stale labels)
    private var spaceChangeRetryCount: Int = 0
    private let maxSpaceChangeRetries: Int = 5
    private var spaceChangeRetryWorkItem: DispatchWorkItem?
    
    // Display Cache
    private var connectedDisplayUUIDs: Set<String> = []

    // Periodic space layout check to detect new spaces created in Mission Control
    // without an explicit space switch event.
    private var spaceLayoutCheckTimer: Timer?
    private let spaceLayoutCheckInterval: TimeInterval = 5.0
    
    // Space locking state and configurations

    // Prevents unbounded recursive retry in moveActiveWindowToSpace when
    // AXFullScreen=false is silently ignored by the target app.
    private var fullscreenExitRetrying: Set<String> = []

    @Published var lockedSpaceIDs: Set<String> = []
    @Published var movedWindowsOriginalSpaces: [Int: (originalSpaceUUID: String, currentSpaceUUID: String, pid: Int32)] = [:]
    var lastManualSwitchTime: TimeInterval = 0
    private var lastManualSwitchTargetUUID: String? = nil
    
    @Published var returnToOriginalAfterBatchMove: Bool {
        didSet {
            UserDefaults.standard.set(returnToOriginalAfterBatchMove, forKey: SpaceManager.returnToOriginalAfterBatchMoveKey)
        }
    }
    
    @Published var grabOffsetX: Double {
        didSet {
            UserDefaults.standard.set(grabOffsetX, forKey: SpaceManager.grabOffsetXKey)
        }
    }
    
    @Published var grabOffsetY: Double {
        didSet {
            UserDefaults.standard.set(grabOffsetY, forKey: SpaceManager.grabOffsetYKey)
        }
    }
    
    @Published var appGrabExceptions: [AppGrabException] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(appGrabExceptions) {
                UserDefaults.standard.set(data, forKey: SpaceManager.appGrabExceptionsKey)
            }
        }
    }
    
    static var isAPIEnabled: Bool {
        get { UserDefaults.standard.object(forKey: isAPIEnabledKey) == nil ? true : UserDefaults.standard.bool(forKey: isAPIEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: isAPIEnabledKey) }
    }
    
    public var spaceAPI: SpaceAPI?
    
    init() {
        self.returnToOriginalAfterBatchMove = UserDefaults.standard.object(forKey: SpaceManager.returnToOriginalAfterBatchMoveKey) == nil ? true : UserDefaults.standard.bool(forKey: SpaceManager.returnToOriginalAfterBatchMoveKey)

        if let savedLocked = UserDefaults.standard.stringArray(forKey: SpaceManager.lockedSpaceIDsKey) {
            self.lockedSpaceIDs = Set(savedLocked)
        }
        
        self.grabOffsetX = UserDefaults.standard.object(forKey: SpaceManager.grabOffsetXKey) == nil ? 13.0 : UserDefaults.standard.double(forKey: SpaceManager.grabOffsetXKey)
        self.grabOffsetY = UserDefaults.standard.object(forKey: SpaceManager.grabOffsetYKey) == nil ? 25.0 : UserDefaults.standard.double(forKey: SpaceManager.grabOffsetYKey)
        
        if let data = UserDefaults.standard.data(forKey: SpaceManager.appGrabExceptionsKey),
           let exceptions = try? JSONDecoder().decode([AppGrabException].self, from: data) {
            self.appGrabExceptions = exceptions
        } else {
            self.appGrabExceptions = []
        }
        
        loadSavedData()
        self.spaceAPI = SpaceAPI(spaceManager: self)
        

        if SpaceManager.isAPIEnabled {
            self.spaceAPI?.setupListener()
            DistributedNotificationCenter.default().postNotificationName(SpaceAPI.apiToggleNotification, object: nil, userInfo: ["isEnabled": true], deliverImmediately: true)
        }
        
        SpaceHelper.startMonitoring { [weak self] rawUUID, isDesktop, ncCnt, displayID in
            self?.handleSpaceChange(rawUUID, isDesktop: isDesktop, ncCount: ncCnt, displayID: displayID, source: "Monitor")
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersDidChange), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        
        refreshConnectedDisplays()
        startPeriodicSpaceLayoutCheck()
    }
    
    func toggleLockSpace(_ spaceID: String) {
        if lockedSpaceIDs.contains(spaceID) {
            lockedSpaceIDs.remove(spaceID)
        } else {
            lockedSpaceIDs.insert(spaceID)
        }
        UserDefaults.standard.set(Array(lockedSpaceIDs), forKey: SpaceManager.lockedSpaceIDsKey)
        objectWillChange.send()
    }

    func toggleLockAllSpaces() {
        let allNonFullscreen = spaceNameDict.filter { !$0.isFullscreen }.map { $0.id }
        let allLocked = allNonFullscreen.allSatisfy { lockedSpaceIDs.contains($0) }
        if allLocked {
            for id in allNonFullscreen { lockedSpaceIDs.remove(id) }
        } else {
            for id in allNonFullscreen { lockedSpaceIDs.insert(id) }
        }
        UserDefaults.standard.set(Array(lockedSpaceIDs), forKey: SpaceManager.lockedSpaceIDsKey)
        objectWillChange.send()
    }

    func cleanMovedWindows() {
        movedWindowsOriginalSpaces.removeAll()
    }
    
    deinit {
        // Timer invalidation is not thread-safe; deinit can run on any thread.
        if let timer = spaceLayoutCheckTimer {
            DispatchQueue.main.async {
                timer.invalidate()
            }
        }
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func systemDidWake() {
        self.lastWakeTime = Date()
        print("SpaceManager: System wake detected. Entering \(wakeCoolingDuration)s cooling period...")
        
        // Schedule a deep refresh once the cooling period ends to capture final stable arrangement
        DispatchQueue.main.asyncAfter(deadline: .now() + wakeCoolingDuration + 1.0) { [weak self] in
            print("SpaceManager: Cooling period ended. Performing final post-wake refresh.")
            self?.refreshSpaceState()
            
            // Final safety seeding to catch any labels that failed during the transient phase
            DispatchQueue.main.async {
                AppDelegate.shared.statusBarController?.labelManager.seedAllLabels()
            }
        }
    }
    
    @objc private func screenParametersDidChange() {
        print("SpaceManager: Screen parameters changed. Refreshing spaces and labels...")
        refreshConnectedDisplays()
        refreshSpaceState()
        
        // When a monitor is connected/disconnected, re-seed all labels to ensure new displays are covered
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            AppDelegate.shared.statusBarController?.labelManager.seedAllLabels()
        }
    }
    
    private func refreshConnectedDisplays() {
        self.connectedDisplayUUIDs = Set(SpaceHelper.getAllDisplayUUIDs().map { $0.uppercased() })
        // print("SpaceManager: Refreshed connected displays: \(connectedDisplayUUIDs)")
    }
    
    func refreshSpaceState() {
        SpaceHelper.getRawSpaceUUID { [weak self] rawUUID, isDesktop, ncCnt, displayID in
            self?.handleSpaceChange(rawUUID, isDesktop: isDesktop, ncCount: ncCnt, displayID: displayID, source: "Refresh")
        }
    }
    
    private func handleSpaceChange(_ rawUUID: String, isDesktop: Bool, ncCount: Int, displayID: String, source: String) {
        DiagnosticEventLog.shared.record(subsystem: "SpaceManager", level: "info", "handleSpaceChange(display=\(displayID), source=\(source))")
        if SpaceHelper.isDragging {
            SpaceHelper.signalSpaceSwitchComplete(arrivedAtSpaceID: rawUUID)
        }
        
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.handleSpaceChange(rawUUID, isDesktop: isDesktop, ncCount: ncCount, displayID: displayID, source: source) }
            return
        }

        print("SpaceManager: handleSpaceChange(rawUUID: \(rawUUID), displayID: \(displayID), source: \(source))")

        
        var shouldUpdateWidget = false

        guard let cgsState = SpaceHelper.getSystemState() else {
                if source == "Monitor" { scheduleSpaceChangeRetry() }
                return
            }
            
            let now = Date().timeIntervalSince1970
            let isRecentManualSwitch = now - lastManualSwitchTime < 2.0
            
            if isRecentManualSwitch, let targetUUID = lastManualSwitchTargetUUID {
                if cgsState.currentUUID != targetUUID {
                    print("SpaceManager: Stale space \(cgsState.currentUUID) detected during active switch to \(targetUUID) (source: \(source)). Ignoring.")
                    if source == "Monitor" {
                        scheduleSpaceChangeRetry()
                    }
                    return
                }
            }
            
            // First, see which names are already taken by active UUIDs so we don't double-assign.
            var claimedNames: Set<String> = []
            let activeUUIDs = Set(cgsState.spaces.map { $0.id })
            
            for (uuid, name) in nameCache {
                if activeUUIDs.contains(uuid) && !name.isEmpty {
                    claimedNames.insert(name)
                }
            }
            
            var newSpaceList: [DesktopSpace] = []
            
            // Calculate desktop indices per display
            var displayDesktopCounters: [String: Int] = [:]
            var spaceDesktopIndices: [String: Int] = [:]

            for sysSpace in cgsState.spaces {
                if !sysSpace.isFullscreen {
                    let dID = sysSpace.displayID
                    let count = displayDesktopCounters[dID, default: 0] + 1
                    displayDesktopCounters[dID] = count
                    spaceDesktopIndices[sysSpace.id] = count
                }
            }
            
            // Build updated space list and attempt to load names from cache; fullscreen names are not cached.
            for sysSpace in cgsState.spaces {
                var finalSpace = sysSpace
                
                if finalSpace.isFullscreen {
                     // For fullscreen spaces, we do NOT load custom names.
                     // The name will be auto-generated in the numbering pass below.
                     finalSpace.customName = "" // Placeholder
                } else {
                    let dIndex = spaceDesktopIndices[sysSpace.id] ?? 1
                    let indexKey = "\(finalSpace.displayID)|Desktop|\(dIndex)"
                    let legacyIndexKey = "\(finalSpace.displayID)|\(finalSpace.num)"
                    
                    if let cachedName = nameCache[sysSpace.id], !cachedName.isEmpty {
                        finalSpace.customName = cachedName
                    } else {
                        if let fallbackName = indexCache[indexKey], !fallbackName.isEmpty {
                            if !claimedNames.contains(fallbackName) {
                                finalSpace.customName = fallbackName
                                nameCache[sysSpace.id] = fallbackName
                            }
                        } else if let fallbackName = indexCache[legacyIndexKey], !fallbackName.isEmpty {
                            if !claimedNames.contains(fallbackName) {
                                finalSpace.customName = fallbackName
                                nameCache[sysSpace.id] = fallbackName
                            }
                        } else if let existing = spaceNameDict.first(where: { $0.id == sysSpace.id }), !existing.customName.isEmpty {
                            finalSpace.customName = existing.customName
                            nameCache[sysSpace.id] = existing.customName
                            indexCache[indexKey] = existing.customName
                        }
                    }
                }
                newSpaceList.append(finalSpace)
            }
            
            // Assign names to fullscreen spaces based on their parent application.
            // Spaces are grouped by application name and numbered if multiple instances exist.
            var appGroups: [String: [Int]] = [:]
            
            for (index, space) in newSpaceList.enumerated() {
                if space.isFullscreen {
                    let name = space.appName ?? "Fullscreen"
                    appGroups[name, default: []].append(index)
                }
            }
            
            // Apply names: "Xcode", or "Xcode 1", "Xcode 2"
            for (appName, indices) in appGroups {
                let sortedIndices = indices.sorted { newSpaceList[$0].num < newSpaceList[$1].num }
                
                if sortedIndices.count == 1 {
                    newSpaceList[sortedIndices[0]].customName = appName
                } else {
                    for (i, index) in sortedIndices.enumerated() {
                        newSpaceList[index].customName = "\(appName) \(i + 1)"
                    }
                }
            }
            
            if self.spaceNameDict != newSpaceList {
                self.spaceNameDict = newSpaceList
                
                // Update index cache with currently detected spaces.
                // We do NOT aggressively clear the entire cache here to preserve names for displays
                // that might be temporarily undetected or in a transient state.
                var cacheCounters: [String: Int] = [:]
                for space in self.spaceNameDict where !space.isFullscreen {
                    let count = cacheCounters[space.displayID, default: 0] + 1
                    cacheCounters[space.displayID] = count

                    if !space.customName.isEmpty {
                        let key = "\(space.displayID)|Desktop|\(count)"
                        self.indexCache[key] = space.customName
                    }
                }
                
                saveData()
                shouldUpdateWidget = true
            }
            
            let previousUUID = self.currentSpaceUUID
            let targetUUID = cgsState.currentUUID

            if previousUUID != targetUUID {
                // Check if previousUUID is in lockedSpaceIDs and this switch is not manual
                if self.lockedSpaceIDs.contains(previousUUID) {
                    let now = Date().timeIntervalSince1970
                    let isOurAppManual = (now - self.lastManualSwitchTime < 2.0) && (targetUUID == self.lastManualSwitchTargetUUID)
                    let isTrackpadManual = now - GestureManager.lastTrackpadSwipeTime < 1.5
                    let isOurAppProgrammatic = (now - SpaceHelper.lastProgrammaticSwitchTime < 2.0) && (targetUUID == SpaceHelper.lastProgrammaticTargetSpaceID)
                    
                    let isManual = isOurAppManual || isTrackpadManual || isOurAppProgrammatic
                    
                    if !isManual {
                        print("SpaceManager: Locked space switch detected from \(previousUUID) to \(targetUUID) (AUTOMATIC)")
                        if let frontApp = NSWorkspace.shared.frontmostApplication {
                            let pid = frontApp.processIdentifier
                            let appName = frontApp.localizedName ?? "App"
                            print("SpaceManager: Automatic switch triggered by \(appName) (PID: \(pid))")
                            
                            // Wait 50ms for the Window Server to settle, then drag-move the active window back to the locked space!
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                if let activeWin = SpaceHelper.getActiveWindowInfo(forPID: pid) {
                                    print("SpaceManager: Physical drag-moving active window \(activeWin.id) to locked space \(previousUUID)")
                                    if let existing = self.movedWindowsOriginalSpaces[activeWin.id] {
                                        if existing.originalSpaceUUID == previousUUID {
                                            self.movedWindowsOriginalSpaces.removeValue(forKey: activeWin.id)
                                            print("SpaceManager: Window \(activeWin.id) returned to original space \(previousUUID). Clearing tracking.")
                                        } else {
                                            self.movedWindowsOriginalSpaces[activeWin.id] = (originalSpaceUUID: existing.originalSpaceUUID, currentSpaceUUID: previousUUID, pid: activeWin.pid)
                                        }
                                    } else {
                                        self.movedWindowsOriginalSpaces[activeWin.id] = (originalSpaceUUID: targetUUID, currentSpaceUUID: previousUUID, pid: activeWin.pid)
                                    }
                                    SpaceHelper.dragActiveWindow(to: previousUUID, forceInstant: true)
                                } else {
                                    print("SpaceManager: Failed to capture active window to drag. Reverting space only.")
                                    if let targetSpaceObj = self.spaceNameDict.first(where: { $0.id == previousUUID }) {
                                        self.switchToSpace(targetSpaceObj, forceInstant: true, isManual: false)
                                    }
                                }
                            }
                        }
                    }
                }
                
                self.currentSpaceUUID = targetUUID
                self.pruneStaleMovedWindows()
                shouldUpdateWidget = true
            }
            
            if self.currentDisplayID != cgsState.displayID {
                self.currentDisplayID = cgsState.displayID
            }
            if self.currentRawSpaceUUID != cgsState.currentUUID {
                self.currentRawSpaceUUID = cgsState.currentUUID
            }
            
            // Update desktop check based on fullscreen status of the matched space
            let isCurrentDesktop = !(self.spaceNameDict.first(where: { $0.id == self.currentSpaceUUID })?.isFullscreen ?? false)
            if self.currentIsDesktop != isCurrentDesktop {
                self.currentIsDesktop = isCurrentDesktop
                shouldUpdateWidget = true
            }
            
            // If no space change was detected from a monitor event, schedule
            // verification retries. Cmd+Tab can fire notifications before CGS
            // state stabilizes, causing stale labels when hideWhenSwitching is off.
            if previousUUID == self.currentSpaceUUID && source == "Monitor" {
                scheduleSpaceChangeRetry()
            } else {
                cancelSpaceChangeRetry()
            }

        if shouldUpdateWidget { scheduleWidgetUpdate() }
    }

    private func scheduleSpaceChangeRetry() {
        guard spaceChangeRetryCount < maxSpaceChangeRetries else { return }
        spaceChangeRetryWorkItem?.cancel()

        let delay = TimeInterval(0.3 + Double(spaceChangeRetryCount) * 0.2)
        spaceChangeRetryCount += 1

        let workItem = DispatchWorkItem { [weak self] in
            self?.performRetryDetection()
        }
        spaceChangeRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelSpaceChangeRetry() {
        spaceChangeRetryWorkItem?.cancel()
        spaceChangeRetryWorkItem = nil
        spaceChangeRetryCount = 0
    }

    private func performRetryDetection() {
        guard let cgsState = SpaceHelper.getSystemState() else {
            scheduleSpaceChangeRetry()
            return
        }

        let now = Date().timeIntervalSince1970
        let isRecentManualSwitch = now - lastManualSwitchTime < 2.0
        
        if isRecentManualSwitch {
            if let targetUUID = lastManualSwitchTargetUUID, cgsState.currentUUID == targetUUID {
                if currentSpaceUUID != targetUUID {
                    handleSpaceChange(targetUUID, isDesktop: true, ncCount: 0,
                                     displayID: cgsState.displayID, source: "Retry")
                }
                cancelSpaceChangeRetry()
            } else {
                // Still transitioning, reschedule retry to check again later without reverting
                scheduleSpaceChangeRetry()
            }
        } else {
            if currentSpaceUUID != cgsState.currentUUID {
                handleSpaceChange(cgsState.currentUUID, isDesktop: true, ncCount: 0,
                                 displayID: cgsState.displayID, source: "Retry")
                cancelSpaceChangeRetry()
            } else {
                scheduleSpaceChangeRetry()
            }
        }
    }

    // Debounces widget updates to throttle system load.
    private func scheduleWidgetUpdate() {
        widgetUpdateWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.performWidgetUpdate()
        }
        
        widgetUpdateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }
    
    struct WidgetSpace: Codable {
        let id: String
        let name: String
        let num: Int
        let displayID: String
    }

    private func performWidgetUpdate() {
        guard let defaults = UserDefaults(suiteName: SpaceManager.appGroupId) else { return }
        
        let name = getSpaceName(currentSpaceUUID)
        let num = getSpaceNum(currentSpaceUUID)
        // Check if current space is desktop
        let isDesktop = !(spaceNameDict.first(where: { $0.id == currentSpaceUUID })?.isFullscreen ?? false)
        
        // Prepare structured data for Widget
        let sortedSpaces = spaceNameDict.sorted {
            if $0.displayID != $1.displayID {
                return $0.displayID < $1.displayID
            }
            return $0.num < $1.num
        }
        
        let widgetSpaces = sortedSpaces.map { space in
            let defaultName = space.isFullscreen ? (space.appName ?? "Fullscreen") : String(format: NSLocalizedString("Space.DefaultName", comment: ""), space.num)
            return WidgetSpace(
                id: space.id,
                name: space.customName.isEmpty ? defaultName : space.customName,
                num: space.num,
                displayID: space.displayID
            )
        }
        
        if let data = try? JSONEncoder().encode(widgetSpaces) {
            defaults.set(data, forKey: "widget_spacesData")
        }
        
        // Some simple fields for basic widgets to use
        let allSpaceNames = sortedSpaces.map { space in
            if !space.customName.isEmpty { return space.customName }
            return space.isFullscreen ? (space.appName ?? "Fullscreen") : "\(space.num)"
        }
        defaults.set(allSpaceNames, forKey: "widget_allSpaces")
        
        defaults.set(name, forKey: "widget_spaceName")
        defaults.set(num, forKey: "widget_spaceNum")
        defaults.set(isDesktop, forKey: "widget_isDesktop")
        defaults.set(currentSpaceUUID, forKey: "widget_currentSpaceUUID")

        WidgetCenter.shared.reloadAllTimelines()
    }
    
    func prepareForTermination() {
        stopPeriodicSpaceLayoutCheck()
        DistributedNotificationCenter.default().postNotificationName(SpaceAPI.apiToggleNotification, object: nil, userInfo: ["isEnabled": false], deliverImmediately: true)
    }

    // MARK: - Periodic Space Layout Check

    private func startPeriodicSpaceLayoutCheck() {
        stopPeriodicSpaceLayoutCheck()
        spaceLayoutCheckTimer = Timer.scheduledTimer(withTimeInterval: spaceLayoutCheckInterval, repeats: true) { [weak self] _ in
            self?.checkForNewSpaces()
        }
    }

    private func stopPeriodicSpaceLayoutCheck() {
        spaceLayoutCheckTimer?.invalidate()
        spaceLayoutCheckTimer = nil
    }

    /// Lightweight check that compares the current CGS space set against
    /// spaceNameDict. If new spaces exist (e.g., created in Mission Control on an
    /// external display) without a space switch having occurred, triggers a full
    /// detection refresh to pick them up.
    private func checkForNewSpaces() {
        guard let cgsState = SpaceHelper.getSystemState() else { return }
        let cgsIDs = Set(cgsState.spaces.map { $0.id })
        let currentIDs = Set(spaceNameDict.map { $0.id })
        guard cgsIDs != currentIDs else { return }
        print("SpaceManager: Detected space layout change (CGS: \(cgsIDs.count) vs cached: \(currentIDs.count)). Refreshing...")
        refreshSpaceState()
    }
    
    private func loadSavedData() {
        if let data = UserDefaults.standard.data(forKey: SpaceManager.spacesKey),
           let spaces = try? JSONDecoder().decode([DesktopSpace].self, from: data) {
            spaceNameDict = spaces.map {
                var s = $0
                s.customName = s.customName.replacingOccurrences(of: "~", with: "")
                
                // Migrate displayID from "Name (ID)" to UUID if needed
                if s.displayID.contains("(") && s.displayID.contains(")") {
                    if let lastParenIndex = s.displayID.lastIndex(of: "("),
                       let lastBracketIndex = s.displayID.lastIndex(of: ")") {
                        let idStart = s.displayID.index(after: lastParenIndex)
                        let idString = String(s.displayID[idStart..<lastBracketIndex])
                        var displayIdentifier = s.displayID
                        if let screenID = UInt32(idString),
                           let uuidRef = CGDisplayCreateUUIDFromDisplayID(screenID) {
                            let uuid = uuidRef.takeRetainedValue()
                            if let uuidStr = CFUUIDCreateString(nil, uuid) as String? {
                                displayIdentifier = uuidStr.uppercased()
                            }
                        }
                        s.displayID = displayIdentifier
                    }
                }
                return s
            }
        }
        if let data = UserDefaults.standard.data(forKey: SpaceManager.nameCacheKey),
           let cache = try? JSONDecoder().decode([String: String].self, from: data) {
            nameCache = cache.mapValues { $0.replacingOccurrences(of: "~", with: "") }
        }
        if let data = UserDefaults.standard.data(forKey: SpaceManager.indexCacheKey),
           let cache = try? JSONDecoder().decode([String: String].self, from: data) {
            indexCache = cache.mapValues { $0.replacingOccurrences(of: "~", with: "") }
        }
        if (nameCache.isEmpty || indexCache.isEmpty) && !spaceNameDict.isEmpty {
            var displayDesktopCounters: [String: Int] = [:]
            for space in spaceNameDict where !space.isFullscreen {
                let count = displayDesktopCounters[space.displayID, default: 0] + 1
                displayDesktopCounters[space.displayID] = count
                
                if !space.customName.isEmpty {
                    nameCache[space.id] = space.customName
                    let indexKey = "\(space.displayID)|Desktop|\(count)"
                    indexCache[indexKey] = space.customName
                }
            }
            saveData()
        }
    }
    
    public func saveSpaces() {
        saveData()
    }
    
    private func saveData() {
        // We only save the spaces. Naming logic for fullscreen is re-run on load/refresh.
        if let data = try? JSONEncoder().encode(spaceNameDict) {
            UserDefaults.standard.set(data, forKey: SpaceManager.spacesKey)
        }
        if let data = try? JSONEncoder().encode(nameCache) {
            UserDefaults.standard.set(data, forKey: SpaceManager.nameCacheKey)
        }
        if let data = try? JSONEncoder().encode(indexCache) {
            UserDefaults.standard.set(data, forKey: SpaceManager.indexCacheKey)
        }
    }

    func getSpaceNum(_ spaceUUID: String) -> Int {
        if spaceUUID == "FULLSCREEN" { return 0 }
        if let space = spaceNameDict.first(where: { $0.id == spaceUUID }) { return space.num }
        return -1
    }
    
    private static func normalizeDisplayID(_ id: String, mainUUID: String?) -> String {
        let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanId.isEmpty || cleanId.uppercased() == "MAIN" || cleanId.uppercased() == "UNKNOWN" {
            return mainUUID?.uppercased() ?? "MAIN"
        }
        return cleanId.uppercased()
    }
    
    func getSpaceName(_ spaceUUID: String) -> String {
        if spaceUUID == "FULLSCREEN" { return "Fullscreen" }
        
        let matched = spaceNameDict.first(where: { $0.id == spaceUUID })
        var ret = matched?.customName
        if ret == nil || ret == "" {
            if matched?.isFullscreen == true {
                ret = matched?.appName ?? "Fullscreen"
            } else {
                ret = String(format: NSLocalizedString("Space.DefaultName", comment: ""), getSpaceNum(spaceUUID))
            }
        }
        return ret ?? ""
    }
    
    func resetAllNames() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            UserDefaults.standard.removeObject(forKey: SpaceManager.spacesKey)
            UserDefaults.standard.removeObject(forKey: SpaceManager.nameCacheKey)
            UserDefaults.standard.removeObject(forKey: SpaceManager.indexCacheKey)
            self.spaceNameDict.removeAll()
            self.nameCache.removeAll()
            self.indexCache.removeAll()
            self.saveData()
            self.refreshSpaceState()
            self.scheduleWidgetUpdate()
        }
    }
    
    func renameSpace(_ spaceUUID: String, to newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = spaceNameDict.firstIndex(where: { $0.id == spaceUUID }) {
            // Prevent renaming fullscreen spaces manually if needed, or just let it be overwritten on next refresh.
            // But UI filters them out, so this is mostly safe.
            spaceNameDict[index].customName = trimmedName
            let space = spaceNameDict[index]
            
            if !space.isFullscreen {
                let desktopsOnSameDisplay = spaceNameDict.filter { $0.displayID == space.displayID && !$0.isFullscreen }
                if let dIndex = desktopsOnSameDisplay.firstIndex(where: { $0.id == space.id }) {
                    let desktopNum = dIndex + 1
                    let indexKey = "\(space.displayID)|Desktop|\(desktopNum)"
                    let legacyIndexKey = "\(space.displayID)|\(space.num)"
                    
                    if trimmedName.isEmpty {
                        nameCache.removeValue(forKey: spaceUUID)
                        indexCache.removeValue(forKey: indexKey)
                        indexCache.removeValue(forKey: legacyIndexKey)
                    } else {
                        nameCache[spaceUUID] = trimmedName
                        indexCache[indexKey] = trimmedName
                    }
                }
            }
            saveData()
            scheduleWidgetUpdate()
        }
    }
    
    // Space navigation and switching logic.
    
    func switchToSpace(_ space: DesktopSpace, forceInstant: Bool = false, isManual: Bool = true) {
        print("SpaceManager: switchToSpace(\(space.id)) on display \(space.displayID) forceInstant: \(forceInstant) isManual: \(isManual)")
        if isManual {
            self.lastManualSwitchTime = Date().timeIntervalSince1970
            self.lastManualSwitchTargetUUID = space.id
        }
        SpaceHelper.switchToSpace(space.id, forceInstant: forceInstant)
    }
    
    func switchToPreviousSpace(onDisplayID displayID: String? = nil, forceInstant: Bool? = nil) {
        let targetDisplayID = displayID ?? spaceNameDict.first(where: { $0.id == currentSpaceUUID })?.displayID ?? currentDisplayID
        if let current = findBestCurrentSpace(for: targetDisplayID) {
            proceedToSwitch(from: current, on: targetDisplayID, direction: -1, forceInstant: forceInstant ?? false)
        }
    }

    func switchToNextSpace(onDisplayID displayID: String? = nil, forceInstant: Bool? = nil) {
        let targetDisplayID = displayID ?? spaceNameDict.first(where: { $0.id == currentSpaceUUID })?.displayID ?? currentDisplayID
        if let current = findBestCurrentSpace(for: targetDisplayID) {
            proceedToSwitch(from: current, on: targetDisplayID, direction: 1, forceInstant: forceInstant ?? false)
        }
    }

    private func findBestCurrentSpace(for displayID: String) -> DesktopSpace? {
        // Identify the visible space for the specified monitor.
        if let liveID = SpaceHelper.getCurrentSpaceID(for: displayID),
           let space = spaceNameDict.first(where: { $0.id == liveID && $0.displayID == displayID }) {
            // Update cache while we're at it
            currentSpaceByDisplay[displayID] = liveID
            return space
        }

        // Fallback: check the per-display cache.
        if let cachedID = currentSpaceByDisplay[displayID],
           let space = spaceNameDict.first(where: { $0.id == cachedID && $0.displayID == displayID }) {
            return space
        }
        
        // Fallback: check if the globally focused space is on this display.
        if let global = spaceNameDict.first(where: { $0.id == currentSpaceUUID && $0.displayID == displayID }) {
            return global
        }
        
        // Fallback: default to the first available space on this monitor.
        return spaceNameDict.first(where: { $0.displayID == displayID })
    }

    private func proceedToSwitch(from current: DesktopSpace, on targetDisplayID: String, direction: Int, forceInstant: Bool = false) {
        // Use spaces from the TARGET display
        let displaySpaces = spaceNameDict
            .filter { $0.displayID == targetDisplayID }
            .sorted { $0.num < $1.num }
        
        guard let currentIndex = displaySpaces.firstIndex(of: current) else { return }
        
        let targetIndex = currentIndex + direction
        guard targetIndex >= 0 && targetIndex < displaySpaces.count else { return }
        
        let target = displaySpaces[targetIndex]
        switchToSpace(target, forceInstant: forceInstant)
    }

    // MARK: - Move Window Functions
    
    func moveActiveWindowToNextSpace() {
        // Determine window and display context.
        guard let frame = SpaceHelper.getActiveWindowFrame() else {
            moveActiveWindowToNextSpaceLegacy()
            return
        }
        
        let displayID = SpaceHelper.getWindowDisplayID(for: frame) ?? self.currentDisplayID
        let currentSpaceID = SpaceHelper.getCurrentSpaceID(for: displayID) ?? self.currentSpaceUUID
        
        // Resolve space objects for the specific display.
        // Robustness: If the exact ID doesn't match, we fallback to finding any space on this display that's marked current.
        let spaceList = spaceNameDict
            .filter { $0.displayID == displayID }
            .sorted { $0.num < $1.num }
        
        guard !spaceList.isEmpty else {
            // Fallback: If no spaces for this display ID, maybe the display ID is wrong?
            // Try global search for the space ID.
            moveActiveWindowToNextSpaceLegacy()
            return
        }
        
        guard let current = spaceList.first(where: { $0.id == currentSpaceID }) else {
            // Fallback: try to guess current if the ID mismatch persists
            moveActiveWindowToNextSpaceLegacy()
            return
        }
        
        // Target the next available space.
        guard let currentIndex = spaceList.firstIndex(of: current),
              currentIndex < spaceList.count - 1 else { return }
        
        let target = spaceList[currentIndex + 1]
        SpaceHelper.dragActiveWindow(to: target.id, forceInstant: true)
    }

    private func moveActiveWindowToNextSpaceLegacy() {
        let displayID = SpaceHelper.getCursorDisplayID() ?? self.currentDisplayID
        let currentSpaceID = SpaceHelper.getCurrentSpaceID(for: displayID) ?? self.currentSpaceUUID
        
        let spaceList = spaceNameDict
            .filter { $0.displayID == displayID }
            .sorted { $0.num < $1.num }
        
        guard let current = spaceList.first(where: { $0.id == currentSpaceID }) else { return }
        guard let currentIndex = spaceList.firstIndex(of: current),
              currentIndex < spaceList.count - 1 else { return }
        
        let target = spaceList[currentIndex + 1]
        SpaceHelper.dragActiveWindow(to: target.id, forceInstant: true)
    }
    
    func moveActiveWindowToPreviousSpace() {
        guard let frame = SpaceHelper.getActiveWindowFrame() else {
            moveActiveWindowToPreviousSpaceLegacy()
            return
        }
        
        let displayID = SpaceHelper.getWindowDisplayID(for: frame) ?? self.currentDisplayID
        let currentSpaceID = SpaceHelper.getCurrentSpaceID(for: displayID) ?? self.currentSpaceUUID
        
        let spaceList = spaceNameDict
            .filter { $0.displayID == displayID }
            .sorted { $0.num < $1.num }
        
        guard !spaceList.isEmpty else {
            moveActiveWindowToPreviousSpaceLegacy()
            return
        }
        
        guard let current = spaceList.first(where: { $0.id == currentSpaceID }) else {
            moveActiveWindowToPreviousSpaceLegacy()
            return
        }
        
        guard let currentIndex = spaceList.firstIndex(of: current),
              currentIndex > 0 else { return }
        
        let target = spaceList[currentIndex - 1]
        SpaceHelper.dragActiveWindow(to: target.id, forceInstant: true)
    }

    private func moveActiveWindowToPreviousSpaceLegacy() {
        let displayID = SpaceHelper.getCursorDisplayID() ?? self.currentDisplayID
        let currentSpaceID = SpaceHelper.getCurrentSpaceID(for: displayID) ?? self.currentSpaceUUID
        
        let spaceList = spaceNameDict
            .filter { $0.displayID == displayID }
            .sorted { $0.num < $1.num }
        
        guard let current = spaceList.first(where: { $0.id == currentSpaceID }) else { return }
        guard let currentIndex = spaceList.firstIndex(of: current),
              currentIndex > 0 else { return }
        
        let target = spaceList[currentIndex - 1]
        SpaceHelper.dragActiveWindow(to: target.id, forceInstant: true)
    }
    
    func moveActiveWindowToSpace(number: Int) {
        if let target = spaceNameDict.first(where: { $0.num == number && $0.displayID == currentDisplayID }) {
            // BUG FIX: Prevent redundant move attempts if the target is already current.
            if target.id == currentSpaceUUID { return }
            SpaceHelper.dragActiveWindow(to: target.id, forceInstant: true)
        }
    }
    
    func switchToSpace(number: Int) {
        if let target = spaceNameDict.first(where: { $0.num == number && $0.displayID == currentDisplayID }) {
            switchToSpace(target)
        }
    }
    
    func moveActiveWindowToSpace(id: String) {
        // BUG FIX: Prevent redundant move attempts if the target is already current.
        if id == currentSpaceUUID { return }

        guard let targetSpace = spaceNameDict.first(where: { $0.id == id }), !targetSpace.isFullscreen else {
            return
        }

        // Un-fullscreen first if current space is fullscreen
        if let currentSpaceObj = spaceNameDict.first(where: { $0.id == currentSpaceUUID }), currentSpaceObj.isFullscreen {
            // Guard against unbounded recursive retry: if the AX exit is silently
            // ignored (sandboxed app, slow animation) we would loop forever.
            guard fullscreenExitRetrying.insert(id).inserted else { return }

            if let windowInfo = SpaceHelper.getActiveWindowInfo() {
                if let axWindow = SpaceHelper.getAXWindow(id: windowInfo.id, pid: windowInfo.pid) {
                    AXUIElementSetAttributeValue(axWindow, "AXFullScreen" as CFString, false as CFTypeRef)
                    // Wait for the exit-fullscreen animation to complete
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                        self?.fullscreenExitRetrying.remove(id)
                        self?.moveActiveWindowToSpace(id: id)
                    }
                    return
                }
            }
            fullscreenExitRetrying.remove(id)
        }

        // Robust Cross-Monitor Support: 
        // If the target space is on a different monitor, we use the direct CGS+AX move method
        // since the "swipe while dragging" gesture is limited to a single display.
        if let windowInfo = SpaceHelper.getActiveWindowInfo() {
            let sourceDisplayID = SpaceHelper.getWindowDisplayID(for: windowInfo.frame)
            if let sourceDisplay = sourceDisplayID, sourceDisplay != targetSpace.displayID {
                print("SpaceManager: Cross-monitor move requested (\(sourceDisplay) -> \(targetSpace.displayID)). Using robust method.")
                
                let fromSpaceID = Int(SpaceHelper.getCurrentSpaceID(for: sourceDisplay) ?? "0") ?? 0
                let targetSpaceID = Int(targetSpace.id) ?? 0
                
                SpaceHelper.moveWindowToSpace(windowID: windowInfo.id, fromSpaceID: fromSpaceID, targetSpaceID: targetSpaceID)
                
                // Switch to the target space to follow the window
                self.switchToSpace(targetSpace, forceInstant: true)
                return
            }
        }
        
        SpaceHelper.dragActiveWindow(to: id, forceInstant: true)
    }

    func isFirstSpace(onDisplayID displayID: String? = nil) -> Bool {
        var targetDisplayID = displayID
        var currentSpaceID = currentSpaceUUID
        
        if let requestedDisplayID = displayID {
            if let space = SpaceHelper.getCurrentSpaceID(for: requestedDisplayID) {
                currentSpaceID = space
                targetDisplayID = requestedDisplayID
            } else { return false }
        }
        
        guard let current = spaceNameDict.first(where: { $0.id == currentSpaceID }) else { return false }
        if targetDisplayID == nil { targetDisplayID = current.displayID }
        
        // Check manual filtering logic in displaySpaces
        let displaySpaces = spaceNameDict
            .filter { $0.displayID == targetDisplayID }
            .sorted { $0.num < $1.num }
            
        guard let currentIndex = displaySpaces.firstIndex(of: current) else { return false }
        return currentIndex == 0
    }
    
    func moveActiveWindowToNextDisplay() {
        moveActiveWindowToDisplay(offset: 1)
    }

    func moveActiveWindowToPreviousDisplay() {
        moveActiveWindowToDisplay(offset: -1)
    }

    private func moveActiveWindowToDisplay(offset: Int) {
        guard let windowInfo = SpaceHelper.getActiveWindowInfo() else { return }
        let sourceDisplayID = SpaceHelper.getWindowDisplayID(for: windowInfo.frame) ?? self.currentDisplayID
        
        let displayIDs = SpaceHelper.getAllDisplayUUIDs()
        guard displayIDs.count > 1 else { return }
        
        guard let currentIndex = displayIDs.firstIndex(of: sourceDisplayID) else { return }
        
        let targetIndex = (currentIndex + offset + displayIDs.count) % displayIDs.count
        let targetDisplayID = displayIDs[targetIndex]
        
        // Find the current space on the target display
        guard let targetSpaceIDStr = SpaceHelper.getCurrentSpaceID(for: targetDisplayID),
              let targetSpace = spaceNameDict.first(where: { $0.id == targetSpaceIDStr }) else { return }
        
        // Perform move using the robust cross-monitor logic
        let fromSpaceID = Int(SpaceHelper.getCurrentSpaceID(for: sourceDisplayID) ?? "0") ?? 0
        let targetSpaceID = Int(targetSpaceIDStr) ?? 0
        
        print("SpaceManager: Moving active window to display \(targetDisplayID)")
        SpaceHelper.moveWindowToSpace(windowID: windowInfo.id, fromSpaceID: fromSpaceID, targetSpaceID: targetSpaceID)
        
        // Switch to the target space to follow the window
        self.switchToSpace(targetSpace, forceInstant: true)
    }
    
    func isLastSpace(onDisplayID displayID: String? = nil) -> Bool {
        var targetDisplayID = displayID
        var currentSpaceID = currentSpaceUUID
        
        if let requestedDisplayID = displayID {
             if let space = SpaceHelper.getCurrentSpaceID(for: requestedDisplayID) {
                 currentSpaceID = space
                 targetDisplayID = requestedDisplayID
             } else { return false }
         }
         
         guard let current = spaceNameDict.first(where: { $0.id == currentSpaceID }) else { return false }
         if targetDisplayID == nil { targetDisplayID = current.displayID }
         
         let displaySpaces = spaceNameDict
             .filter { $0.displayID == targetDisplayID }
             .sorted { $0.num < $1.num }
             
         guard let currentIndex = displaySpaces.firstIndex(of: current) else { return false }
         return currentIndex == displaySpaces.count - 1
    }
    
    // MARK: - Diagnostic Report Accessors

    /// Returns a human-readable description of the last wake time, including
    /// remaining cooling time if we are still in the post-wake stabilization window.
    var lastWakeTimeAgo: String {
        let elapsed = Date().timeIntervalSince(lastWakeTime)
        if elapsed < wakeCoolingDuration {
            let remaining = wakeCoolingDuration - elapsed
            return "cooling (\(String(format: "%.1f", remaining))s remaining, started \(String(format: "%.1f", elapsed))s ago)"
        }
        return "\(String(format: "%.1f", elapsed))s ago"
    }

    /// Space change retry count / max for diagnostic reports.
    var spaceChangeRetryInfo: String {
        "\(spaceChangeRetryCount)/\(maxSpaceChangeRetries)"
    }

    /// Fullscreen exit retry set contents for diagnostic reports.
    var fullscreenExitRetryingInfo: String {
        fullscreenExitRetrying.isEmpty ? "(empty)" : fullscreenExitRetrying.sorted().joined(separator: ", ")
    }

    /// Connected display UUIDs for diagnostic reports.
    var connectedDisplayUUIDsInfo: String {
        connectedDisplayUUIDs.isEmpty ? "(none)" : connectedDisplayUUIDs.sorted().joined(separator: ", ")
    }

    /// Last manual switch target space UUID for diagnostic reports.
    var lastManualSwitchTargetUUIDInfo: String {
        lastManualSwitchTargetUUID ?? "nil"
    }

    private func pruneStaleMovedWindows() {
        guard !SpaceHelper.isDragging else { return }
        var staleKeys: [Int] = []
        for (windowID, entry) in movedWindowsOriginalSpaces {
            guard let actualCgsSpaceID = SpaceHelper.getWindowSpaceID(id: windowID) else {
                staleKeys.append(windowID)
                continue
            }
            if actualCgsSpaceID != entry.currentSpaceUUID {
                print("SpaceManager: Pruning window \(windowID) from restore queue — expected \(entry.currentSpaceUUID), actual \(actualCgsSpaceID)")
                staleKeys.append(windowID)
            }
        }
        for key in staleKeys {
            movedWindowsOriginalSpaces.removeValue(forKey: key)
        }
    }

    func restoreAllMovedWindows() {
        pruneStaleMovedWindows()
        let list = movedWindowsOriginalSpaces.map { (windowID: $0.key, originalSpaceUUID: $0.value.originalSpaceUUID, currentSpaceUUID: $0.value.currentSpaceUUID, pid: $0.value.pid) }
        guard !list.isEmpty else { return }
        
        let initialSpaceUUID = self.currentSpaceUUID
        restoreNextWindow(index: 0, list: list, initialSpaceUUID: initialSpaceUUID)
    }
    
    private func restoreNextWindow(index: Int, list: [(windowID: Int, originalSpaceUUID: String, currentSpaceUUID: String, pid: Int32)], initialSpaceUUID: String) {
        if index >= list.count {
            // All windows restored! Switch back to the user's initial space instantly after a short delay
            // to allow the last programmatic drag and OS space change state to fully settle.
            if let initialSpaceObj = self.spaceNameDict.first(where: { $0.id == initialSpaceUUID }) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    print("SpaceManager: All restorations complete. Switching back to initial space \(initialSpaceUUID)")
                    self?.switchToSpace(initialSpaceObj, forceInstant: true, isManual: true)
                }
            }
            return
        }
        
        let item = list[index]
        print("SpaceManager: Restoring window \(item.windowID) from \(item.currentSpaceUUID) back to \(item.originalSpaceUUID)")
        
        // 1. Switch to the window's current space instantly to grab it
        if let currentSpaceObj = self.spaceNameDict.first(where: { $0.id == item.currentSpaceUUID }) {
            self.switchToSpace(currentSpaceObj, forceInstant: true, isManual: false)
            
            // 2. Wait 600ms for the space switch to finish, focus the window, and drag it to originalSpaceUUID
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.60) { [weak self] in
                SpaceHelper.focusWindow(id: item.windowID, pid: item.pid)
                
                // Wait 250ms for the window to raise/focus
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    SpaceHelper.dragActiveWindow(to: item.originalSpaceUUID, forceInstant: true)
                    self?.movedWindowsOriginalSpaces.removeValue(forKey: item.windowID)
                    
                    // 3. Wait 500ms for the drag-move operation to fully complete before starting the next one!
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.50) {
                        self?.restoreNextWindow(index: index + 1, list: list, initialSpaceUUID: initialSpaceUUID)
                    }
                }
            }
        } else {
            // Space not found, skip this one
            self.restoreNextWindow(index: index + 1, list: list, initialSpaceUUID: initialSpaceUUID)
        }
    }
}

struct AppGrabException: Codable, Identifiable, Hashable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    let appName: String
    var grabOffsetX: Double
    var grabOffsetY: Double
    var dragBeforeSwitch: Bool?
    
    var shouldDragBeforeSwitch: Bool {
        dragBeforeSwitch ?? false
    }
    
    init(bundleIdentifier: String, appName: String, grabOffsetX: Double, grabOffsetY: Double, dragBeforeSwitch: Bool? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.grabOffsetX = grabOffsetX
        self.grabOffsetY = grabOffsetY
        self.dragBeforeSwitch = dragBeforeSwitch
    }
}
