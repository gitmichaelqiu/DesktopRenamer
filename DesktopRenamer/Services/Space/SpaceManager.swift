import Foundation
import AppKit
import SwiftUI
import WidgetKit

class SpaceManager: ObservableObject {
    // App group ID for sharing data with the widget extension
    static let appGroupId = "group.com.michaelqiu.DesktopRenamer"
    
    static let spacesKey = "com.michaelqiu.desktoprenamer.spaces"
    static let nameCacheKey = "com.michaelqiu.desktoprenamer.namecache"
    static let indexCacheKey = "com.michaelqiu.desktoprenamer.indexcache"
    static let isAPIEnabledKey = "com.michaelqiu.desktoprenamer.isapienabled"
    static let grabOffsetXKey = "com.michaelqiu.desktoprenamer.grabOffsetX"
    static let grabOffsetYKey = "com.michaelqiu.desktoprenamer.grabOffsetY"
    static let lockedSpaceIDsKey = "com.michaelqiu.desktoprenamer.lockedSpaceIDs"
    static let movedWindowsOriginalSpacesKey = "com.michaelqiu.desktoprenamer.movedWindowsOriginalSpaces"
    static let returnToOriginalAfterBatchMoveKey = "com.michaelqiu.desktoprenamer.returnToOriginalAfterBatchMove"
    static let appGrabExceptionsKey = "com.michaelqiu.desktoprenamer.appGrabExceptions"
    static let autoRearrangeFullscreenSpacesKey = "com.michaelqiu.desktoprenamer.autoRearrangeFullscreenSpaces"
    
    @Published var currentSpaceUUID: String = ""
    @Published var currentRawSpaceUUID: String = ""
    @Published var currentDisplayID: String = "Main"
    @Published var autoEditBundleID: String? = nil
    
    // Tracks active space per display to ensure local switching context
    var currentSpaceByDisplay: [String: String] = [:]
    
    @Published var spaceNameDict: [DesktopSpace] = []
    
    // Convenience views for the current display
    var currentDisplaySpaces: [DesktopSpace] {
        spaceNameDict
            .filter { $0.displayID == currentDisplayID }
            .sorted { $0.num < $1.num }
    }
    
    var nameCache: [String: String] = [:]
    var indexCache: [String: String] = [:]
    
    @Published var currentNcCount: Int = 0
    @Published var currentIsDesktop: Bool = false
    
    // Widget Debouncer
    var widgetUpdateWorkItem: DispatchWorkItem?
    
    // Stabilization state for system wake events
    var lastWakeTime: Date = .distantPast
    let wakeCoolingDuration: TimeInterval = 15.0
    let wakeRecoveryDelay: TimeInterval = 3.0
    var isSystemSleeping = false
    var wakeRecoveryWorkItem: DispatchWorkItem?
    var isInWakeCoolingPeriod: Bool {
        Date().timeIntervalSince(lastWakeTime) < wakeCoolingDuration
    }

    // Retry state for space change detection (Cmd+Tab switches can fire notifications
    // before CGS state stabilizes, causing stale labels)
    var spaceChangeRetryCount: Int = 0
    let maxSpaceChangeRetries: Int = 5
    var spaceChangeRetryWorkItem: DispatchWorkItem?
    
    // Display Cache
    var connectedDisplayUUIDs: Set<String> = []

    // Periodic space layout check to detect new spaces created in Mission Control
    // without an explicit space switch event.
    var spaceLayoutCheckTimer: Timer?
    let spaceLayoutCheckInterval: TimeInterval = 5.0
    
    // Space locking state and configurations

    // Prevents unbounded recursive retry in moveActiveWindowToSpace when
    // AXFullScreen=false is silently ignored by the target app.
    var fullscreenExitRetrying: Set<String> = []

    @Published var lockedSpaceIDs: Set<String> = []
    @Published var movedWindowsOriginalSpaces: [Int: (originalSpaceUUID: String, currentSpaceUUID: String, pid: Int32)] = [:]
    var lastManualSwitchTime: TimeInterval = 0
    var lastManualSwitchTargetUUID: String? = nil
    
    @Published var returnToOriginalAfterBatchMove: Bool {
        didSet {
            UserDefaults.standard.set(returnToOriginalAfterBatchMove, forKey: SpaceManager.returnToOriginalAfterBatchMoveKey)
        }
    }

    @Published var autoRearrangeFullscreenSpaces: Bool {
        didSet {
            UserDefaults.standard.set(autoRearrangeFullscreenSpaces, forKey: SpaceManager.autoRearrangeFullscreenSpacesKey)
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
        self.autoRearrangeFullscreenSpaces = UserDefaults.standard.bool(forKey: SpaceManager.autoRearrangeFullscreenSpacesKey)

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
        self.spaceAPI = MainActor.assumeIsolated {
            SpaceAPI(spaceManager: self)
        }
        

        if SpaceManager.isAPIEnabled {
            MainActor.assumeIsolated {
                self.spaceAPI?.setupListener()
            }
            DistributedNotificationCenter.default().postNotificationName(SpaceAPI.apiToggleNotification, object: nil, userInfo: ["isEnabled": true], deliverImmediately: true)
        }
        
        SpaceHelper.startMonitoring { [weak self] rawUUID, isDesktop, ncCnt, displayID in
            self?.handleSpaceChange(rawUUID, isDesktop: isDesktop, ncCount: ncCnt, displayID: displayID, source: "Monitor")
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersDidChange), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(systemWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
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
        widgetUpdateWorkItem?.cancel()
        wakeRecoveryWorkItem?.cancel()
        spaceChangeRetryWorkItem?.cancel()
        if Thread.isMainThread {
            SpaceHelper.stopMonitoring()
        } else {
            DispatchQueue.main.async {
                SpaceHelper.stopMonitoring()
            }
        }
        // Timer invalidation is not thread-safe; deinit can run on any thread.
        if let timer = spaceLayoutCheckTimer {
            DispatchQueue.main.async {
                timer.invalidate()
            }
        }
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    @objc private func systemDidWake() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // A wake notification can arrive even when the sleep notification
            // was delivered while the main queue was busy. Ensure monitoring is
            // suspended before scheduling any post-wake CGS work.
            if !self.isSystemSleeping {
                self.prepareForSystemSleep()
            }
            self.recoverFromSystemWake()
        }
    }

    @objc private func systemWillSleep() {
        DispatchQueue.main.async { [weak self] in
            self?.prepareForSystemSleep()
        }
    }

    private func prepareForSystemSleep() {
        guard !isSystemSleeping else { return }

        isSystemSleeping = true
        wakeRecoveryWorkItem?.cancel()
        wakeRecoveryWorkItem = nil
        cancelSpaceChangeRetry()
        stopPeriodicSpaceLayoutCheck()
        SpaceHelper.stopMonitoring()
        DiagnosticEventLog.shared.record(subsystem: "SpaceManager", level: "info", "System sleep detected; suspended space monitoring")
    }

    private func recoverFromSystemWake() {
        lastWakeTime = Date()
        isSystemSleeping = true
        wakeRecoveryWorkItem?.cancel()

        // WindowServer can preserve stale label-window assignments while it
        // rebuilds Mission Control after wake. Recreate labels after recovery.
        DispatchQueue.main.async {
            AppDelegate.shared.statusBarController?.labelManager.resetForSystemTransition()
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.isSystemSleeping else { return }

            self.isSystemSleeping = false
            print("SpaceManager: Wake stabilization complete. Restarting space monitoring.")
            SpaceHelper.startMonitoring { [weak self] rawUUID, isDesktop, ncCnt, displayID in
                self?.handleSpaceChange(rawUUID, isDesktop: isDesktop, ncCount: ncCnt, displayID: displayID, source: "Monitor")
            }
            self.refreshConnectedDisplays()
            self.startPeriodicSpaceLayoutCheck()
            self.refreshSpaceState()

            DiagnosticEventLog.shared.record(subsystem: "SpaceManager", level: "info", "Wake recovery completed; space monitoring resumed")

            // Allow the first reconciliation to complete before creating
            // windows. A second refresh handles displays that become available
            // slightly later than the wake event.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self, !self.isSystemSleeping else { return }
                self.refreshSpaceState()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                AppDelegate.shared.statusBarController?.labelManager.reloadAllWindows()
            }
        }

        wakeRecoveryWorkItem = workItem
        print("SpaceManager: System wake detected. Suspending CGS reads for \(wakeRecoveryDelay)s.")
        DiagnosticEventLog.shared.record(subsystem: "SpaceManager", level: "info", "System wake detected; delaying recovery")
        DispatchQueue.main.asyncAfter(deadline: .now() + wakeRecoveryDelay, execute: workItem)
    }
    
    @objc private func screenParametersDidChange() {
        guard !isSystemSleeping else { return }
        print("SpaceManager: Screen parameters changed. Refreshing spaces and labels...")
        DispatchQueue.main.async {
            AppDelegate.shared.statusBarController?.labelManager.resetForSystemTransition()
        }
        refreshConnectedDisplays()
        refreshSpaceState()
        
        // Recreate labels after the display and space layout has stabilized.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            AppDelegate.shared.statusBarController?.labelManager.reloadAllWindows()
        }
    }
}
