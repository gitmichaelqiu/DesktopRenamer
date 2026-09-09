import AppKit
import Darwin.sys.sysctl
import Foundation

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
        sections.append(makeLabelWindows())
        sections.append(makeGestureOverride())
        sections.append(makeHotkeys())
        sections.append(makeDragState())
        sections.append(makeCalibration())
        sections.append(makeSpaceManagerInternals())
        sections.append(makeLauncherState())
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
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            let bundleID = frontmost.bundleIdentifier ?? "?"
            s += "Frontmost Application: \(frontmost.localizedName ?? "?") (bundleID=\(bundleID), pid=\(frontmost.processIdentifier))\n"
        } else {
            s += "Frontmost Application: nil\n"
        }
        s += "Screens: \(NSScreen.screens.count)\n"
        for (i, screen) in NSScreen.screens.enumerated() {
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
            let bounds = CGDisplayBounds(id)
            let isBuiltin = CGDisplayIsBuiltin(id) != 0
            let scale = String(format: "%.2f", screen.backingScaleFactor)
            s += "  Screen \(i): \"\(screen.localizedName)\" displayID=\(id) \(Int(bounds.width))×\(Int(bounds.height)) scale=\(scale)"
            s += " frame=\(NSStringFromRect(screen.frame)) visibleFrame=\(NSStringFromRect(screen.visibleFrame)) isBuiltin=\(isBuiltin ? 1 : 0)\n"
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
        s += "Event synthesis: \(pm.isEventSynthesisGranted ? "Granted" : "Not Granted")\n"
        s += "Screen capture: \(pm.isScreenCaptureGranted ? "Granted" : "Not Granted")\n"
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
        s += "disableActiveLiquidGlass: \(lm.disableActiveLiquidGlass)\n"
        s += "disablePreviewLiquidGlass: \(lm.disablePreviewLiquidGlass)\n"
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

    private static func makeLabelWindows() -> String {
        guard let labelManager = AppDelegate.shared.statusBarController?.labelManager else {
            return "─── Label Windows ───\nLabelManager: nil\n"
        }

        var s = "─── Label Windows ───\n"
        s += "previewWindowCount: \(labelManager.createdWindows.count)\n"
        s += "activeWindowCount: \(labelManager.activeWindows.count)\n"
        s += "knownSpaceCount: \(labelManager.knownSpaceIDs.count)\n"
        s += "knownFullscreenSpaceCount: \(labelManager.knownFullscreenSpaceIDs.count)\n"
        s += "lastKnownVisibleSpaceIDs: \(labelManager.lastKnownVisibleSpaceIDs.sorted())\n"
        s += "previewTransitionSuppressed: \(labelManager.isPreviewTransitionSuppressed)\n"
        s += "previewSuppressedForSettings: \(labelManager.arePreviewLabelsSuppressedForSettings)\n"
        s += "settingsWindowOpen: \(labelManager.isSettingsWindowOpen)\n"
        s += "previewTransitionGeneration: \(labelManager.previewTransitionGeneration)\n"
        s += "previewTransitionRestoreAttempt: \(labelManager.previewTransitionRestoreAttempt)\n"
        s += "previewTransitionStablePasses: \(labelManager.previewTransitionStablePasses)\n"
        s += "previewTransitionCompletionObserved: \(labelManager.previewTransitionCompletionObserved)\n"

        let windows = labelManager.createdWindows.map { (role: "preview", window: $0.value) }
            + labelManager.activeWindows.map { (role: "active", window: $0.value) }
        for entry in windows.sorted(by: { lhs, rhs in
            if lhs.window.displayID != rhs.window.displayID {
                return lhs.window.displayID < rhs.window.displayID
            }
            if lhs.window.spaceId != rhs.window.spaceId {
                return lhs.window.spaceId < rhs.window.spaceId
            }
            return lhs.role < rhs.role
        }) {
            let window = entry.window
            let assignedSpaces = window.windowNumber > 0
                ? SpaceHelper.getWindowCurrentSpaces(windowID: window.windowNumber).sorted()
                : []
            s += "  \(entry.role) space=\(window.spaceId) display=\(window.displayID) window=\(window.windowNumber)"
            s += " visible=\(window.isVisible) alpha=\(String(format: "%.2f", window.alphaValue))"
            s += " activeMode=\(window.isActiveMode) current=\(window.isCurrentSpaceLabel)"
            s += " dragging=\(window.isDragging) anchor=\(window.isInvisibleAnchorMode)"
            s += " key=\(window.isKeyWindow) main=\(window.isMainWindow) level=\(window.level.rawValue)"
            s += " behavior=\(window.collectionBehavior.rawValue) assignedSpaces=\(assignedSpaces)"
            s += " frame=\(NSStringFromRect(window.frame))\n"
        }
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
        s += "programmaticSwitch:\n\(SpaceHelper.programmaticSwitchStateInfo)"
        s += "observationFence:\n\(sm.confirmedSpaceObservationFence.diagnosticDescription)"
        s += "pendingProgrammaticSpaceSwitches: \(sm.pendingProgrammaticSpaceSwitches.map { "\($0.key)=\($0.value.spaceID)/g\($0.value.generation)" }.sorted())\n"
        s += "latestProgrammaticSwitchRequestIDs: \(sm.latestProgrammaticSwitchRequestIDs)\n"
        s += "retryObservedSpace: \(sm.spaceChangeRetryObservedSpaceID ?? "nil") passes=\(sm.spaceChangeRetryObservedPasses) display=\(sm.spaceChangeRetryDisplayID ?? "nil") generation=\(sm.spaceChangeRetryGeneration)\n"
        if let pending = sm.pendingMonitorSpaceChange {
            s += "pendingMonitorSpaceChange: raw=\(pending.rawUUID) desktop=\(pending.isDesktop) notifications=\(pending.ncCount) display=\(pending.displayID) generation=\(sm.monitorSpaceChangeGeneration)\n"
        } else {
            s += "pendingMonitorSpaceChange: nil generation=\(sm.monitorSpaceChangeGeneration)\n"
        }
        s += "autoEditBundleID: \(sm.autoEditBundleID ?? "nil")\n"
        return s
    }

    private static func makeLauncherState() -> String {
        let controller = LauncherWindowController.shared
        let viewModel = controller.viewModel
        var s = "─── Launcher State ───\n"
        if let window = controller.window {
            s += "window: visible=\(window.isVisible) key=\(window.isKeyWindow) main=\(window.isMainWindow)"
            s += " level=\(window.level.rawValue) behavior=\(window.collectionBehavior.rawValue)"
            s += " frame=\(NSStringFromRect(window.frame))\n"
        } else {
            s += "window: nil\n"
        }
        s += "activeCommand: \(viewModel.activeCommand?.type.rawValue ?? "nil")\n"
        s += "searchQuery: \(viewModel.searchQuery.debugDescription) spaceBarQuery: \(viewModel.spaceBarQuery.debugDescription)\n"
        s += "selectedRowIndex: \(viewModel.selectedRowIndex) selectedSpaceIndex: \(viewModel.selectedSpaceIndex)\n"
        s += "isLoadingData: \(viewModel.isLoadingData) keyboardSelection=\(viewModel.isKeyboardSelection) bottomBarFocused=\(viewModel.isBottomBarFocused)\n"
        s += "showCommandNumbers: \(viewModel.showCommandNumbers) isRearrangingSpace=\(viewModel.isRearrangingSpace)\n"
        s += "currentSpaces: \(viewModel.currentSpaces.count) currentWindows: \(viewModel.currentWindows.count)\n"
        s += "stagedMoves: \(viewModel.stagedMoves.count) isExecutingBatchMove=\(viewModel.isExecutingBatchMove)\n"
        s += "commandKTargetWindow: \(viewModel.commandKTargetWindow?.id.description ?? "nil") commandKSelectedIndex=\(viewModel.commandKSelectedIndex)\n"
        s += "isStagingForRestoreTo: \(viewModel.isStagingForRestoreTo) isExecutingRestoreToImmediately=\(viewModel.isExecutingRestoreToImmediately)\n"
        if let window = viewModel.previouslyActiveWindow {
            s += "previouslyActiveWindow: id=\(window.id) pid=\(window.pid) frame=\(NSStringFromRect(window.frame))\n"
        } else {
            s += "previouslyActiveWindow: nil\n"
        }
        s += "renameInputText: \(viewModel.renameInputText.debugDescription) terminatingApplicationPIDs: \(viewModel.terminatingApplicationPIDs.sorted())\n"
        return s
    }

    private static func makeSpaceAPIState() -> String {
        var s = "─── SpaceAPI State ───\n"
        s += "isAPIEnabled: \(SpaceManager.isAPIEnabled)\n"
        if let api = AppDelegate.shared.spaceManager?.spaceAPI {
            s += "hasActiveListeners: \(api.hasActiveListeners)\n"
            s += "currentSnapshotRevision: \(api.currentSnapshotRevision)\n"
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
