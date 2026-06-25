import AppKit
import Darwin.sys.sysctl
import Foundation

// MARK: - Diagnostic Event Log

/// A single event recorded by the diagnostic system.
public struct DiagnosticEvent: Codable {
    public let timestamp: Date
    public let subsystem: String  // e.g. "SpaceHelper", "GestureManager"
    public let level: String      // "info", "warning", "error"
    public let message: String
}

/// Thread-safe circular buffer of diagnostic events.
/// The last `capacity` events are kept in memory and included in diagnostic
/// reports.  When collection mode is active, events are also logged in
/// real-time for reproduction workflows.
public class DiagnosticEventLog {
    public static let shared = DiagnosticEventLog()

    public private(set) var isCollecting: Bool = false
    public private(set) var collectionStartTime: Date?
    public private(set) var sessionEvents: [DiagnosticEvent] = []

    private var ring: [DiagnosticEvent] = []
    private var nextIndex = 0
    private let capacity = 500
    private let lock = NSLock()

    private init() {}

    /// Record an event.  Always stored in the ring buffer; when collection
    /// mode is active also appended to the linear session buffer.
    /// Thread-safe — can be called from any thread.
    public func record(subsystem: String, level: String = "info", _ message: String) {
        let ev = DiagnosticEvent(timestamp: Date(), subsystem: subsystem, level: level, message: message)

        lock.lock()
        defer { lock.unlock() }
        
        if ring.count < capacity {
            ring.append(ev)
        } else {
            ring[nextIndex % capacity] = ev
            nextIndex += 1
        }
        if isCollecting {
            sessionEvents.append(ev)
        }
    }

    /// Start a diagnostic collection session.
    /// Thread-safe.
    public func startCollection() {
        lock.lock()
        isCollecting = true
        collectionStartTime = Date()
        sessionEvents.removeAll()
        sessionEvents.append(DiagnosticEvent(timestamp: Date(), subsystem: "System", level: "info", message: "Diagnostic collection started"))
        lock.unlock()
    }

    /// Stop a diagnostic collection session.
    /// Thread-safe.
    public func stopCollection() {
        lock.lock()
        isCollecting = false
        sessionEvents.append(DiagnosticEvent(timestamp: Date(), subsystem: "System", level: "info", message: "Diagnostic collection stopped"))
        lock.unlock()
    }

    /// Format all ring events for inclusion in a report.
    /// Thread-safe.
    public func formattedRing() -> String {
        lock.lock()
        let copy = ring
        lock.unlock()
        let sorted = copy.sorted { $0.timestamp < $1.timestamp }
        return format(sorted)
    }

    /// Format session events for inclusion in a report.
    /// Thread-safe.
    public func formattedSession() -> String {
        lock.lock()
        let copy = sessionEvents
        lock.unlock()
        return format(copy)
    }

    private func format(_ events: [DiagnosticEvent]) -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return events.map { ev in
            "[\(df.string(from: ev.timestamp))] [\(ev.subsystem)] [\(ev.level)] \(ev.message)"
        }.joined(separator: "\n")
    }
}

// MARK: - Diagnostic Report Builder

/// Generates a comprehensive diagnostic report capturing the state of every
/// subsystem in DesktopRenamer.  The output is a single formatted text string
/// intended to be saved as a `.log` file by the user.
@MainActor
struct DiagnosticReportBuilder {

    // MARK: - Public API

    /// Produce the full report.
    static func generate() -> String {
        var sections: [String] = []
        sections.append(makeHeader())
        sections.append(makeSystemInfo())
        sections.append(makePermissions())
        sections.append(makeSpaceState())
        sections.append(makeLabelSystem())
        sections.append(makeGestureOverride())
        sections.append(makeHotkeys())
        sections.append(makeDragState())
        sections.append(makeCalibration())
        sections.append(makeSpaceManagerInternals())
        sections.append(makeSpaceAPIState())
        sections.append(makeUpdaterState())
        sections.append(makeEventLog())
        sections.append(makeWindowList())
        sections.append(makeUserDefaultsDump())
        sections.append(makeWidgetData())
        return sections.joined(separator: "\n\n" + String(repeating: "=", count: 72) + "\n\n")
    }

    // MARK: - Section Builders

    private static func makeHeader() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return """
        ╔══════════════════════════════════════════════════════════════════════════════╗
        ║                     DesktopRenamer Diagnostic Report                       ║
        ╚══════════════════════════════════════════════════════════════════════════════╝
        Generated: \(formatter.string(from: Date()))
        """
    }

    private static func makeSystemInfo() -> String {
        var s = "─── System Info ───\n"
        if let info = Bundle.main.infoDictionary {
            let version = info["CFBundleShortVersionString"] as? String ?? "?"
            let build = info["CFBundleVersion"] as? String ?? "?"
            s += "DesktopRenamer: \(version) (build \(build))\n"
        }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        s += "macOS: \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)\n"
        let uptime = ProcessInfo.processInfo.systemUptime
        s += "Uptime: \(String(format: "%.1f", uptime))s\n"
        s += "Screens: \(NSScreen.screens.count)\n"
        for (i, screen) in NSScreen.screens.enumerated() {
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
            let bounds = CGDisplayBounds(id)
            let isBuiltin = CGDisplayIsBuiltin(id) != 0
            s += "  Screen \(i): \"\(screen.localizedName)\" \(Int(bounds.width))×\(Int(bounds.height)) isBuiltin=\(isBuiltin ? 1 : 0)\n"
        }
        // Hardware details
        let processCount = ProcessInfo.processInfo.processorCount
        let activeCount = ProcessInfo.processInfo.activeProcessorCount

        var hwModel = "?"
        var hwModelRaw: [CChar] = Array(repeating: 0, count: 256)
        var size = MemoryLayout<[CChar]>.stride
        if sysctlbyname("hw.model", &hwModelRaw, &size, nil, 0) == 0 {
            hwModel = String(cString: hwModelRaw)
        }

        var cpuBrand = "?"
        var cpuRaw: [CChar] = Array(repeating: 0, count: 256)
        size = MemoryLayout<[CChar]>.stride
        if sysctlbyname("machdep.cpu.brand_string", &cpuRaw, &size, nil, 0) == 0 {
            cpuBrand = String(cString: cpuRaw)
        }

        #if arch(arm64)
        let arch = "Apple Silicon (arm64)"
        #else
        let arch = "Intel (x86_64)"
        #endif

        s += "Hardware Model: \(hwModel)\n"
        s += "CPU: \(cpuBrand)\n"
        s += "Architecture: \(arch)\n"
        s += "Processor Count: \(processCount) logical, \(activeCount) active\n"
        return s
    }

    private static func makePermissions() -> String {
        var s = "─── Permissions ───\n"
        let pm = PermissionManager.shared
        s += "Accessibility: \(pm.isAccessibilityGranted ? "Granted" : "Not Granted")\n"
        return s
    }

    private static func makeSpaceState() -> String {
        guard let sm = AppDelegate.shared.spaceManager else { return "─── Space State ───\nSpaceManager: nil\n" }
        var s = "─── Space State ───\n"
        s += "currentSpaceUUID: \(sm.currentSpaceUUID)\n"
        s += "currentRawSpaceUUID: \(sm.currentRawSpaceUUID)\n"
        s += "currentDisplayID: \(sm.currentDisplayID)\n"
        s += "currentIsDesktop: \(sm.currentIsDesktop)\n"
        s += "currentNcCount: \(sm.currentNcCount)\n"
        s += "spaceNameDict.count: \(sm.spaceNameDict.count)\n"
        s += "lockedSpaceIDs (\(sm.lockedSpaceIDs.count)): "
        if sm.lockedSpaceIDs.isEmpty {
            s += "(none)\n"
        } else {
            s += sm.lockedSpaceIDs.sorted().joined(separator: ", ") + "\n"
        }
        s += "movedWindowsOriginalSpaces (\(sm.movedWindowsOriginalSpaces.count)):\n"
        if sm.movedWindowsOriginalSpaces.isEmpty {
            s += "  (none)\n"
        } else {
            for (windowID, entry) in sm.movedWindowsOriginalSpaces {
                s += "  windowID=\(windowID) originalSpace=\(entry.originalSpaceUUID) currentSpace=\(entry.currentSpaceUUID) pid=\(entry.pid)\n"
            }
        }
        s += "lastManualSwitchTime: \(sm.lastManualSwitchTime)\n"
        s += "currentSpaceByDisplay:\n"
        for (displayID, spaceID) in sm.currentSpaceByDisplay {
            s += "  Display \(displayID) -> Space \(spaceID)\n"
        }
        for space in sm.spaceNameDict {
            let name = sm.getSpaceName(space.id)
            s += "  Space id=\(space.id) num=\(space.num) display=\(space.displayID) FS=\(space.isFullscreen ? 1 : 0) name=\"\(name)\" app=\"\(space.appName ?? "")\"\n"
        }
        s += "Raw CGS Managed Display Spaces:\n"
        s += SpaceHelper.getRawCGSDisplaySpacesDescription()
        return s
    }

    private static func makeLabelSystem() -> String {
        guard let lm = AppDelegate.shared.statusBarController?.labelManager else {
            return "─── Label System ───\nLabelManager: nil\n"
        }
        var s = "─── Label System ───\n"
        s += "showActiveLabels: \(lm.showActiveLabels)\n"
        s += "showPreviewLabels: \(lm.showPreviewLabels)\n"
        s += "showOnDesktop: \(lm.showOnDesktop)\n"
        s += "hideWhenSwitching: \(lm.hideWhenSwitching)\n"
        s += "globalIsDocked: \(lm.globalIsDocked)\n"
        s += "globalCenterPoint: \(lm.globalCenterPoint.map { "\($0.x),\($0.y)" } ?? "nil")\n"
        s += "activeFontScale: \(lm.activeFontScale)\n"
        s += "previewFontScale: \(lm.previewFontScale)\n"
        s += "activePaddingScale: \(lm.activePaddingScale)\n"
        s += "previewPaddingScale: \(lm.previewPaddingScale)\n"
        return s
    }

    private static func makeGestureOverride() -> String {
        guard let gm = AppDelegate.shared.gestureManager else {
            return "─── Gesture Override ───\nGestureManager: nil\n"
        }
        var s = "─── Gesture Override ───\n"
        s += "isEnabled: \(gm.isEnabled)\n"
        s += "fingerCount: \(gm.fingerCount)\n"
        s += "switchOverride: \(gm.switchOverride.rawValue)\n"
        s += "swipeThreshold: \(gm.swipeThreshold)\n"
        s += "moveWindowOnOption: \(gm.moveWindowOnOption)\n"
        s += "switchDuration: \(gm.switchDuration)\n"
        return s
    }

    private static func makeHotkeys() -> String {
        var s = "─── Hotkeys ───\n"
        guard let hk = AppDelegate.shared.hotkeyManager else {
            s += "HotkeyManager: nil\n"
            return s
        }
        let shortcuts = [
            ("Main", hk.mainShortcut),
            ("Switch Left", hk.switchLeftShortcut),
            ("Switch Right", hk.switchRightShortcut),
            ("Move Window Next", hk.moveWindowNextShortcut),
            ("Move Window Previous", hk.moveWindowPreviousShortcut),
            ("Move Window Number", hk.moveWindowNumberShortcut),
            ("Switch Space Number", hk.switchSpaceNumberShortcut),
            ("Reload Labels", hk.reloadLabelsShortcut),
            ("Move Window Next Display", hk.moveWindowNextDisplayShortcut),
            ("Move Window Previous Display", hk.moveWindowPreviousDisplayShortcut),
            ("Toggle Lock", hk.toggleLockShortcut),
            ("Restore Windows", hk.restoreWindowsShortcut),
            ("Launcher", hk.launcherShortcut),
        ]
        for (label, sc) in shortcuts {
            let desc: String
            if let k = sc.key {
                desc = "\(sc.modifiers) + \(k)"
            } else {
                desc = "Unassigned"
            }
            s += "  \(label): \(desc)\n"
        }
        s += "isListening: \(hk.isListening)\n"
        s += "listeningType: \(hk.listeningType.map { "\($0)" } ?? "nil")\n"
        return s
    }

    private static func makeDragState() -> String {
        var s = "─── Drag State ───\n"
        s += "isDragging: \(SpaceHelper.isDragging)\n"
        s += SpaceHelper.dragStateInfo
        return s
    }

    private static func makeCalibration() -> String {
        var s = "─── Calibration ───\n"
        s += "targetDuration: \(SpaceHelper.targetDuration)\n"
        s += "Display Calibrations:\n"
        s += SpaceHelper.displayCalibrationsInfo
        s += "Phase Sample Counts:\n"
        s += SpaceHelper.phaseSampleCountsInfo
        return s
    }

    private static func makeSpaceManagerInternals() -> String {
        guard let sm = AppDelegate.shared.spaceManager else {
            return "─── SpaceManager Internals ───\nSpaceManager: nil\n"
        }
        var s = "─── SpaceManager Internals ───\n"
        s += "lastWakeTime: \(sm.lastWakeTimeAgo)\n"
        s += "spaceChangeRetry: \(sm.spaceChangeRetryInfo)\n"
        s += "fullscreenExitRetrying: \(sm.fullscreenExitRetryingInfo)\n"
        s += "connectedDisplayUUIDs: \(sm.connectedDisplayUUIDsInfo)\n"
        s += "lastManualSwitchTargetUUID: \(sm.lastManualSwitchTargetUUIDInfo)\n"
        s += "autoEditBundleID: \(sm.autoEditBundleID ?? "nil")\n"
        return s
    }

    private static func makeSpaceAPIState() -> String {
        var s = "─── SpaceAPI State ───\n"
        s += "isAPIEnabled: \(SpaceManager.isAPIEnabled)\n"
        if let api = AppDelegate.shared.spaceManager?.spaceAPI {
            s += "hasActiveListeners: \(api.hasActiveListeners)\n"
        } else {
            s += "spaceAPI: nil\n"
        }
        return s
    }

    private static func makeUpdaterState() -> String {
        var s = "─── Sparkle Updater ───\n"
        let updater = UpdateManager.shared.updaterController.updater
        s += "automaticallyChecksForUpdates: \(updater.automaticallyChecksForUpdates)\n"
        s += "automaticallyDownloadsUpdates: \(updater.automaticallyDownloadsUpdates)\n"
        return s
    }

    private static func makeEventLog() -> String {
        let log = DiagnosticEventLog.shared
        var s = "─── Event Log ───\n"
        s += "isCollecting: \(log.isCollecting)\n"
        if let startTime = log.collectionStartTime {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd HH:mm:ss"
            s += "collectionStartTime: \(df.string(from: startTime))\n"
        }
        s += "\n─── Event Log (Ring Buffer) ───\n"
        s += log.formattedRing()
        s += "\n"

        if !log.sessionEvents.isEmpty {
            s += "\n─── Event Log (Session) ───\n"
            s += log.formattedSession()
            s += "\n"
        }
        return s
    }

    private static func makeWindowList() -> String {
        guard let sm = AppDelegate.shared.spaceManager else {
            return "─── Window List ───\nSpaceManager: nil\n"
        }
        var s = "─── Window List ───\n"
        var names: [String: String] = [:]
        for space in sm.spaceNameDict {
            names[space.id] = sm.getSpaceName(space.id)
        }
        let raw = SpaceHelper.getWindowsForAllSpaces(spaces: sm.spaceNameDict, spaceNames: names)
        let lines = raw.components(separatedBy: "\n")
        for line in lines where !line.isEmpty {
            s += "  \(line)\n"
        }
        return s
    }

    private static func makeUserDefaultsDump() -> String {
        var s = "─── UserDefaults ───\n"
        let ud = UserDefaults.standard
        let keys = [
            "com.michaelqiu.desktoprenamer.spaces",
            "com.michaelqiu.desktoprenamer.namecache",
            "com.michaelqiu.desktoprenamer.indexcache",
            "com.michaelqiu.desktoprenamer.isapienabled",
            "com.michaelqiu.desktoprenamer.grabOffsetX",
            "com.michaelqiu.desktoprenamer.grabOffsetY",
            "com.michaelqiu.desktoprenamer.lockedSpaceIDs",
            "com.michaelqiu.desktoprenamer.returnToOriginalAfterBatchMove",
            "com.michaelqiu.desktoprenamer.appGrabExceptions",
            "GestureManager.Enabled",
            "GestureManager.FingerCount",
            "GestureManager.SwitchOverride",
            "GestureManager.SwipeThreshold",
            "GestureManager.MoveWindowOnOption",
            "GestureManager.SwitchDuration",
            "GestureManager.CachedCalibrations",
            "kShowPreviewLabels", "kShowActiveLabels", "kShowOnDesktop", "kHideWhenSwitching",
            "kActiveFontScale", "kPreviewFontScale", "kActivePaddingScale", "kPreviewPaddingScale",
            "kGlobalIsDocked", "kGlobalDockEdge", "kGlobalCenterX", "kGlobalCenterY",
            "HasInitializedDefaults", "hasSeenSplashScreen",
            "LauncherCommandFrequency",
            "com.michaelqiu.desktoprenamer.automaticallyRankCommands",
            "com.michaelqiu.desktoprenamer.launcherManualCommandOrder",
            "isStatusBarHidden",
        ]
        for key in keys {
            if let val = ud.object(forKey: key) {
                s += "  \(key) = \(val)\n"
            }
        }
        return s
    }

    private static func makeWidgetData() -> String {
        var s = "─── Widget Data (App Group) ───\n"
        guard let defaults = UserDefaults(suiteName: SpaceManager.appGroupId) else {
            s += "  No app group defaults\n"
            return s
        }
        let keys = ["widget_spaceName", "widget_spaceNum", "widget_isDesktop", "widget_currentSpaceUUID", "widget_spacesData", "widget_allSpaces"]
        for key in keys {
            if let val = defaults.object(forKey: key) {
                s += "  \(key) = \(val)\n"
            }
        }
        return s
    }
}
