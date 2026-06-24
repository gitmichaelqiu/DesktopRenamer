import AppKit
import CoreGraphics
import Foundation
import SwiftUI

@_silgen_name("_CGSDefaultConnection") private func _CGSDefaultConnection() -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces") private func CGSCopyManagedDisplaySpaces(_ cid: Int32)
    -> CFArray?
@_silgen_name("CGSCopyActiveMenuBarDisplayIdentifier")
private func CGSCopyActiveMenuBarDisplayIdentifier(_ cid: Int32) -> CFString?
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: inout CGWindowID) -> Int32

@_silgen_name("CGSCopySpacesForWindows")
private func CGSCopySpacesForWindows(_ cid: Int32, _ mask: Int32, _ windows: CFArray) -> CFArray?

@_silgen_name("CGSAddWindowsToSpaces")
private func CGSAddWindowsToSpaces(_ cid: Int32, _ windows: CFArray, _ spaces: CFArray)

@_silgen_name("CGSRemoveWindowsFromSpaces")
private func CGSRemoveWindowsFromSpaces(_ cid: Int32, _ windows: CFArray, _ spaces: CFArray)

@_silgen_name("CGSOrderWindow")
private func CGSOrderWindow(_ cid: Int32, _ windowID: UInt32, _ op: Int32, _ relativeToWindowID: UInt32) -> Int32

class SpaceHelper {

    private static var onSpaceChange: ((String, Bool, Int, String) -> Void)?
    private static var globalEventMonitor: Any?
    private static var localEventMonitor: Any?

    // Tokens for block-based notification observers (required for proper cleanup).
    private static var spaceChangeObserver: NSObjectProtocol?
    private static var appActivationObserver: NSObjectProtocol?

    // Tracks switching state to prevent recursion during transitions.
    private static var isSwitching = false
    static var lastProgrammaticSwitchTime: TimeInterval = 0
    static var lastProgrammaticTargetSpaceID: String? = nil
    
    // Session state for active dragging operations.
    private static var originalMousePoint: CGPoint? = nil
    private static var restorationTask: DispatchWorkItem? = nil
    private static var pendingFocusTask: DispatchWorkItem? = nil
    private static var pendingMoveCount = 0
    private static var isInstantDrag = false
    private static var targetSpaceID: String? = nil
    private static var draggedWindowID: Int? = nil
    private static var draggedWindowPID: Int32? = nil
    private static var draggedWindowBundleID: String? = nil
    private static var draggedWindowAppName: String? = nil
    private static var draggedWindowOriginalFrame: CGRect? = nil
    static var isDragging: Bool { originalMousePoint != nil }

    /// Full drag state summary for diagnostic reports.
    static var dragStateInfo: String {
        let wid = draggedWindowID.map { "\($0)" } ?? "nil"
        let pid = draggedWindowPID.map { "\($0)" } ?? "nil"
        let bundle = draggedWindowBundleID ?? "nil"
        let app = draggedWindowAppName ?? "nil"
        let target = targetSpaceID ?? "nil"
        let mouse = originalMousePoint.map { "(\($0.x), \($0.y))" } ?? "nil"
        return """
          draggedWindowID: \(wid)
          draggedWindowPID: \(pid)
          draggedWindowBundleID: \(bundle)
          draggedWindowAppName: \(app)
          targetSpaceID: \(target)
          isInstantDrag: \(isInstantDrag)
          pendingMoveCount: \(pendingMoveCount)
          originalMousePoint: \(mouse)
        """
    }

    // Velocity calibration — adjusts multiplier per display so measured switch
    // time converges to the user-configured target duration (default 0.35s).
    // Multipliers are cached in UserDefaults for persistence across restarts.
    // Two-point calibration: measures switch time at velocity 52 (native) and
    // at velocity 104 (2×), then computes the actual non-linear exponent p from
    // the two data points.  This gives an accurate velocity multiplier for any
    private static var gestureTimingStart: TimeInterval = 0
    private static var gestureTimingDisplayID: String = ""

    private static let calibrationKey = "GestureManager.CachedCalibrations"
    private static let targetDurationKey = "GestureManager.SwitchDuration"
    private static let defaultTargetDuration: TimeInterval = 0.30
    private static let minMultiplier: Double = 0.1
    private static let maxMultiplier: Double = 10.0

    /// The user's target switch duration — 0 means instant mode.
    static var targetDuration: TimeInterval {
        guard UserDefaults.standard.object(forKey: targetDurationKey) != nil else {
            return defaultTargetDuration
        }
        return UserDefaults.standard.double(forKey: targetDurationKey)
    }

    struct DisplayCalibration: Codable {
        var avg52: Double
        var avg104: Double
    }

    // Cached calibrations keyed by display (direction-agnostic).
    private static var displayCalibrations: [String: DisplayCalibration] = {
        guard let data = UserDefaults.standard.data(forKey: calibrationKey),
              let dict = try? JSONDecoder().decode([String: DisplayCalibration].self, from: data)
        else { return [:] }
        return dict
    }()

    // Phase 1: 3 samples at velocity 52. Phase 2: 3 samples at velocity 104.
    private static var phase1Samples: [String: [TimeInterval]] = [:]
    private static var phase2Samples: [String: [TimeInterval]] = [:]
    private static let phaseSamplesNeeded = 3
    private static let phase1Velocity: Double = 52.0
    private static let phase2Velocity: Double = 104.0

    /// Calibration state summary for diagnostic reports: per-display avg values.
    static var displayCalibrationsInfo: String {
        guard !displayCalibrations.isEmpty else { return "  (none)\n" }
        var s = ""
        for (displayID, cal) in displayCalibrations {
            s += "  \(displayID): avg52=\(String(format: "%.4f", cal.avg52)) avg104=\(String(format: "%.4f", cal.avg104))\n"
        }
        return s
    }

    /// Calibration phase sample counts for diagnostic reports.
    static var phaseSampleCountsInfo: String {
        let allIDs = Set(phase1Samples.keys).union(phase2Samples.keys)
        guard !allIDs.isEmpty else { return "  (no samples)\n" }
        var s = ""
        for did in allIDs.sorted() {
            let p1 = phase1Samples[did]?.count ?? 0
            let p2 = phase2Samples[did]?.count ?? 0
            s += "  \(did): phase1=\(p1) phase2=\(p2)\n"
        }
        return s
    }

    /// Returns a stable velocity multiplier based on empirical curve.
    static func multiplierForDisplay(_ displayID: String) -> Double {
        let target = targetDuration
        guard target > 0 else { return 1.0 }
        
        guard let cal = displayCalibrations[displayID] else { return 1.0 }
        
        let p = log(cal.avg52 / cal.avg104) / log(0.5)
        let clampedP = min(-0.1, max(-3.0, p))
        
        let ratio = target / cal.avg52
        let multiplier = pow(ratio, 1.0 / clampedP)
        return max(minMultiplier, min(maxMultiplier, multiplier))
    }

    /// Returns the velocity to use for the current calibration phase.
    static func velocityForPhase(displayID: String) -> Double {
        if displayCalibrations[displayID] != nil {
            return phase1Velocity * multiplierForDisplay(displayID)
        }
        
        let phase1Count = phase1Samples[displayID]?.count ?? 0
        let phase2Count = phase2Samples[displayID]?.count ?? 0
        
        if phase1Count < phaseSamplesNeeded { return phase1Velocity }
        if phase2Count < phaseSamplesNeeded { return phase2Velocity }
        
        return phase1Velocity * multiplierForDisplay(displayID)
    }

    static func beginGestureTiming(for displayID: String) {
        gestureTimingStart = Date().timeIntervalSince1970
        gestureTimingDisplayID = displayID
    }

    static func endGestureTiming() {
        guard gestureTimingStart > 0, !gestureTimingDisplayID.isEmpty else { return }
        
        let duration = Date().timeIntervalSince1970 - gestureTimingStart
        let displayID = gestureTimingDisplayID
        
        // Reset state
        gestureTimingStart = 0
        gestureTimingDisplayID = ""
        
        // Sanity check
        guard duration > 0.05 && duration < 2.0 else { return }

        // If already calibrated, no need to record samples
        if displayCalibrations[displayID] != nil { return }

        let phase1Count = phase1Samples[displayID]?.count ?? 0
        let phase2Count = phase2Samples[displayID]?.count ?? 0

        if phase1Count < phaseSamplesNeeded {
            var s = phase1Samples[displayID, default: []]
            s.append(duration)
            phase1Samples[displayID] = s
        } else if phase2Count < phaseSamplesNeeded {
            var s = phase2Samples[displayID, default: []]
            s.append(duration)
            phase2Samples[displayID] = s
        }

        tryLockCalibration(for: displayID)
    }

    private static func tryLockCalibration(for displayID: String) {
        guard displayCalibrations[displayID] == nil else { return }

        let p1 = phase1Samples[displayID] ?? []
        let p2 = phase2Samples[displayID] ?? []
        guard p1.count >= phaseSamplesNeeded, p2.count >= phaseSamplesNeeded else { return }

        let avg52 = p1.reduce(0, +) / Double(p1.count)
        let avg104 = p2.reduce(0, +) / Double(p2.count)
        guard avg52 > 0, avg104 > 0 else { return }

        displayCalibrations[displayID] = DisplayCalibration(avg52: avg52, avg104: avg104)
        if let data = try? JSONEncoder().encode(displayCalibrations) {
            UserDefaults.standard.set(data, forKey: calibrationKey)
        }
    }

    // Minimum width and height for a window to be considered a regular app window in getActiveWindowInfo (filtering out small system utilities/status items).
    private static let minActiveWindowWidth: CGFloat = 100
    private static let minActiveWindowHeight: CGFloat = 100

    // Core space switching implementation.
    static func switchToSpace(_ spaceID: String, forceInstant: Bool = false) {
        DiagnosticEventLog.shared.record(subsystem: "SpaceHelper", level: "info", "switchToSpace(\(spaceID), forceInstant=\(forceInstant))")
        lastProgrammaticSwitchTime = Date().timeIntervalSince1970
        lastProgrammaticTargetSpaceID = spaceID

        if !forceInstant {
            guard !isSwitching else { return }
            isSwitching = true
        }

        defer {
            if !forceInstant {
                // Short delay to allow OS animations to settle before allowing another switch
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isSwitching = false
                }
            }
        }

        NotificationCenter.default.post(
            name: NSNotification.Name("SpaceSwitchRequested"), object: nil)

        // Resolve target space information.
        var targetNum: Int? = nil
        var targetGlobalNum: Int? = nil
        var shouldUseShortcut = true
        var targetIsFullscreen = false

        if let state = getSystemState() {
            if let targetSpace = state.spaces.first(where: { $0.id == spaceID }) {
                targetNum = targetSpace.num
                targetGlobalNum = targetSpace.globalShortcutNum
                targetIsFullscreen = targetSpace.isFullscreen
                
                // CRITICAL FIX: To check if we are ALREADY on the target space, 
                // we must check the current space of the TARGET display, 
                // not the global active display.
                if let liveCurrentID = getCurrentSpaceID(for: targetSpace.displayID) {
                    print("SpaceHelper: switchToSpace check. Live ID: \(liveCurrentID), Target: \(spaceID)")
                    if liveCurrentID == spaceID {
                        print("SpaceHelper: Already on target space \(spaceID). Stopping.")
                        return 
                    }
                }
            }

            // If we are already on the target space, stop.
            if state.currentUUID == spaceID { return }
            
            // Gesture-based Space Switch handling
            // We use the gesture method for all normal switches (no window moving).
            if !isDragging, let targetSpace = state.spaces.first(where: { $0.id == spaceID }) {
                let displayID = targetSpace.displayID
                if let liveCurrentID = getCurrentSpaceID(for: displayID) {
                    let displaySpaces = state.spaces
                        .filter { $0.displayID == displayID }
                        .sorted { $0.num < $1.num }

                    if let currentIndex = displaySpaces.firstIndex(where: { $0.id == liveCurrentID }),
                       let targetIndex = displaySpaces.firstIndex(where: { $0.id == spaceID }) {
                        let steps = targetIndex - currentIndex
                        if steps != 0 {
                            performSpaceSwitchGesture(steps: steps, targetDisplayID: displayID, forceInstant: forceInstant)
                            return
                        }
                    }
                }
            }
        }
        


        if let state = getSystemState(),
            let targetSpace = state.spaces.first(where: { $0.id == spaceID })
        {
            // Note: Native shortcuts (Ctrl+1, Ctrl+2) only map to Desktops.
            if targetSpace.isFullscreen {
                shouldUseShortcut = false
            } else {
                let spacesBefore = state.spaces.filter {
                    $0.displayID == targetSpace.displayID && $0.num < targetSpace.num
                }
                if spacesBefore.contains(where: { $0.isFullscreen }) {
                    shouldUseShortcut = false
                }
            }
        }

        // Attempt to use system Desktop shortcuts (Control + Number).
        // This provides the smoothest transition when available.
        if shouldUseShortcut {
            if let globalNum = targetGlobalNum {
                if isShortcutEnabled(for: globalNum) && simulateDesktopShortcut(for: globalNum) {
                    return
                }
            } else if let localNum = targetNum {
                // Fallback to local num if global is missing (should verify if this is ever needed/correct)
                if isShortcutEnabled(for: localNum) && simulateDesktopShortcut(for: localNum) {
                    return
                }
            }
        }

        // If shortcuts didn't handle it, use our private window activation trick.
        if switchByActivatingOwnWindow(for: spaceID, isFullscreen: targetIsFullscreen) {

            // High-priority fix for Fullscreen Focus:
            // When switching to a Fullscreen space via SpaceLabelWindow, DesktopRenamer initially gets focus.
            // This can cause the OS to revert to the previous space if we don't hand off focus immediately.
            // We must identify the "owner" app of the fullscreen space and activate it.
            // Since we just triggered the visual switch, activating the app now should correctly
            // prioritize the window on the target space (resolving the "multiple windows" ambiguity).
            if targetIsFullscreen {
                if let pid = getOwnerPID(for: spaceID),
                    let app = NSRunningApplication(processIdentifier: pid)
                {

                    // A very short delay ensures the Window Server registers the space switch intent
                    // before we force the app activation.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        app.activate(options: .activateIgnoringOtherApps)
                    }
                }
            }
            return
        }


    }

    private static func switchByActivatingOwnWindow(for spaceID: String, isFullscreen: Bool) -> Bool
    {
        var targetWindow: SpaceLabelWindow? = nil
        var windowsToHide: [SpaceLabelWindow] = []

        // Identify target and potential conflicting windows.
        for window in NSApp.windows {
            if let labelWindow = window as? SpaceLabelWindow {
                if labelWindow.spaceId == spaceID {
                    targetWindow = labelWindow
                } else if labelWindow.isVisible {
                    // CRITICAL MULTI-MONITOR FIX: Only hide windows on the SAME display.
                    // Hiding windows on other displays causes them to lose focus state 
                    // and triggers "snap-back" issues when they are automatically restored.
                    if let target = targetWindow, labelWindow.displayID == target.displayID {
                        windowsToHide.append(labelWindow)
                    } else if targetWindow == nil {
                        // If we haven't found the target yet, we'll collect all visible ones
                        // and filter them after the loop.
                        windowsToHide.append(labelWindow)
                    }
                }
            }
        }
        
        // Final filter if we collected them before finding target
        if let target = targetWindow {
            windowsToHide = windowsToHide.filter { $0.displayID == target.displayID }
        }

        guard let window = targetWindow else { return false }

        // Manage conflicting windows to remove focus ambiguity.
        // For Desktop targets: We hide other windows to remove ambiguity about "Last Active Space".
        // This forces the OS to switch to the target window.
        // For Fullscreen targets: We MUST NOT hide the desktop window. Doing so removes the app's
        // anchor on the main desktop, causing the OS to panic and revert to the previous space.
        // During drag operations labels are already alpha=0 from hideImmediately, so skip.
        if !isFullscreen, !isDragging {
            for other in windowsToHide {
                other.orderOut(nil)
            }
        }

        // Force window activation.
        DiagnosticEventLog.shared.record(subsystem: "SpaceHelper", level: "info", "switchByActivatingOwnWindow space=\(spaceID)")
        window.orderFrontRegardless()
        window.canBecomeKeyOverride = true
        window.makeKey()
        window.canBecomeKeyOverride = false
        NSApp.activate(ignoringOtherApps: true)

        return true
    }
    
    // MARK: - Instant Space Switch Helpers
    
    // MARK: - SLS Space Switching for macOS 27+
    
    static func shouldSwitchToSpaceUsingSLS() -> Bool {
        let debugOverride = UserDefaults.standard.integer(forKey: "com.michaelqiu.desktoprenamer.debug.spaceSwitchMethod")
        if debugOverride == 1 {
            return false // Force legacy swipe
        }
        if debugOverride == 2 {
            return true  // Force SLS Operation
        }
        // Default: Automatic version check
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return os.majorVersion >= 27
    }
    
    // Method signature casting to pass a primitive UInt64 to the Objective-C initializer
    private typealias SLSInitMethodType = @convention(c) (NSObject, Selector, NSString, UInt64) -> Unmanaged<NSObject>?

    static func switchSpaceUsingSLSOperation(displayUUID: String, spaceID: Int) -> Bool {
        guard let opCls = NSClassFromString("SLSBridgedManagedDisplaySetCurrentSpaceOperation") as? NSObject.Type else {
            DiagnosticEventLog.shared.record(subsystem: "SpaceHelper", level: "error", "SLSBridgedManagedDisplaySetCurrentSpaceOperation class not found")
            return false
        }
        
        let allocSel = NSSelectorFromString("alloc")
        guard opCls.responds(to: allocSel),
              let allocatedOp = opCls.perform(allocSel)?.takeUnretainedValue() as? NSObject else {
            DiagnosticEventLog.shared.record(subsystem: "SpaceHelper", level: "error", "Failed to allocate SLSBridgedManagedDisplaySetCurrentSpaceOperation")
            return false
        }
        
        let initSel = NSSelectorFromString("initWithDisplayIdentifier:spaceID:")
        guard let method = class_getInstanceMethod(opCls, initSel) else {
            DiagnosticEventLog.shared.record(subsystem: "SpaceHelper", level: "error", "initWithDisplayIdentifier:spaceID: selector not found on SLSBridgedManagedDisplaySetCurrentSpaceOperation")
            return false
        }
        
        let imp = method_getImplementation(method)
        let initFunc = unsafeBitCast(imp, to: SLSInitMethodType.self)
        let displayStr = displayUUID as NSString
        
        guard let initializedOp = initFunc(allocatedOp, initSel, displayStr, UInt64(spaceID))?.takeUnretainedValue() else {
            DiagnosticEventLog.shared.record(subsystem: "SpaceHelper", level: "error", "Failed to initialize SLSBridgedManagedDisplaySetCurrentSpaceOperation via C-function casting")
            return false
        }
        
        // Execute operation using SLSWindowManagementFallbackBridge
        if let bridgeCls = NSClassFromString("SLSWindowManagementFallbackBridge") as? NSObject.Type,
           bridgeCls.responds(to: allocSel),
           let allocatedBridge = bridgeCls.perform(allocSel)?.takeUnretainedValue() as? NSObject {
            
            let initBridgeSel = NSSelectorFromString("init")
            if allocatedBridge.responds(to: initBridgeSel),
               let initializedBridge = allocatedBridge.perform(initBridgeSel)?.takeUnretainedValue() as? NSObject {
                
                let performSel = NSSelectorFromString("performAsynchronousBridgedWindowManagementOperation:")
                if initializedBridge.responds(to: performSel) {
                    DiagnosticEventLog.shared.record(subsystem: "SpaceHelper", level: "info", "Executing SLS operation via SLSWindowManagementFallbackBridge: \(displayUUID), \(spaceID)")
                    initializedBridge.perform(performSel, with: initializedOp)
                    return true
                }
            }
        }
        
        // Fallback for compatibility
        if let operation = initializedOp as? Operation {
            DiagnosticEventLog.shared.record(subsystem: "SpaceHelper", level: "info", "Executing SLS operation via OperationQueue: \(displayUUID), \(spaceID)")
            OperationQueue.main.addOperation(operation)
            return true
        } else {
            let startSel = NSSelectorFromString("start")
            if initializedOp.responds(to: startSel) {
                DiagnosticEventLog.shared.record(subsystem: "SpaceHelper", level: "info", "Starting SLS operation via start selector: \(displayUUID), \(spaceID)")
                initializedOp.perform(startSel)
                return true
            }
        }
        
        DiagnosticEventLog.shared.record(subsystem: "SpaceHelper", level: "error", "SLSBridgedManagedDisplaySetCurrentSpaceOperation could not be executed")
        return false
    }
    
    private static func hasAXWindows(pid: Int32) -> Bool {
        let appRef = AXUIElementCreateApplication(pid)
        var windowsValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsValue)
        guard result == .success, let windows = windowsValue as? [AXUIElement] else {
            return false
        }
        return !windows.isEmpty
    }

    private static func getTopWindowInfo(forSpace spaceID: String) -> (pid: Int32, windowID: Int)? {
        guard let targetSpaceInt = Int(spaceID) else { return nil }
        let conn = _CGSDefaultConnection()
        
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            print("SpaceHelper: Failed to copy window list")
            return nil
        }
        
        let ourPID = ProcessInfo.processInfo.processIdentifier
        
        for window in windowList {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let wID = window[kCGWindowNumber as String] as? Int,
                  let pid = window[kCGWindowOwnerPID as String] as? Int,
                  pid != ourPID,
                  let app = NSRunningApplication(processIdentifier: Int32(pid)),
                  app.activationPolicy == .regular,
                  hasAXWindows(pid: Int32(pid)),
                  (window[kCGWindowAlpha as String] as? Double ?? 1.0) > 0.1,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let w = bounds["Width"] as? CGFloat, let h = bounds["Height"] as? CGFloat,
                  w > 100, h > 100
            else { continue }
            
            // Check spaces for this window
            let wIDArray = [wID as NSNumber] as CFArray
            if let result = CGSCopySpacesForWindows(conn, 7, wIDArray),
               let spaceIDs = result as? [NSNumber] {
                let spaceInts = spaceIDs.map { $0.intValue }
                if spaceInts.contains(targetSpaceInt), spaceInts.count == 1 {
                    let appName = window[kCGWindowOwnerName as String] as? String ?? "Unknown"
                    print("SpaceHelper: Found top window on Space \(spaceID): \(appName) (PID: \(pid), WindowID: \(wID), Spaces: \(spaceInts))")
                    DiagnosticEventLog.shared.record(subsystem: "SpaceHelper", "Found top window on Space \(spaceID): \(appName) (PID: \(pid), WindowID: \(wID), Spaces: \(spaceInts))")
                    return (Int32(pid), wID)
                }
            }
        }
        print("SpaceHelper: No top window found on Space \(spaceID)")
        return nil
    }

    private static func focusWindowViaAccessibility(pid: Int32, windowID: Int) -> Bool {
        let appRef = AXUIElementCreateApplication(pid)
        var windowsValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsValue)
        
        print("SpaceHelper: focusWindowViaAccessibility pid \(pid), windowID \(windowID). Copy windows result: \(result.rawValue)")
        DiagnosticEventLog.shared.record(subsystem: "SpaceHelper", "focusWindowViaAccessibility pid \(pid), windowID \(windowID). result=\(result.rawValue)")
        
        guard result == .success, let windows = windowsValue as? [AXUIElement] else {
            print("SpaceHelper: Failed to copy windows for PID \(pid)")
            return false
        }
        
        print("SpaceHelper: App PID \(pid) has \(windows.count) windows in accessibility")
        for windowRef in windows {
            var wID: CGWindowID = 0
            if _AXUIElementGetWindow(windowRef, &wID) == 0, Int(wID) == windowID {
                AXUIElementPerformAction(windowRef, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(windowRef, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementSetAttributeValue(windowRef, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                print("SpaceHelper: Successfully focused window \(windowID) via AX API")
                DiagnosticEventLog.shared.record(subsystem: "SpaceHelper", "Successfully focused window \(windowID) via AX API")
                return true
            }
        }
        
        // Fallback: Focus first window
        if let firstWindow = windows.first {
            AXUIElementPerformAction(firstWindow, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(firstWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(firstWindow, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            print("SpaceHelper: Focused first window of PID \(pid) via AX API fallback")
            DiagnosticEventLog.shared.record(subsystem: "SpaceHelper", "Focused first window of PID \(pid) via AX API fallback")
            return true
        }
        
        print("SpaceHelper: No windows found to focus for PID \(pid)")
        return false
    }

    static func restoreFocusAfterSLSSwitch(spaceID: String, immediate: Bool = false) {
        print("SpaceHelper: restoreFocusAfterSLSSwitch for Space \(spaceID), immediate: \(immediate)")
        DiagnosticEventLog.shared.record(subsystem: "SpaceHelper", "restoreFocusAfterSLSSwitch for Space \(spaceID), immediate: \(immediate)")
        
        pendingFocusTask?.cancel()
        
        // Use 350ms for immediate switches so it runs after transition slide animations settle.
        // This is key to preventing glitched, mangled, or stacked menu bar items.
        let delay = immediate ? 0.35 : 0.45
        
        let task = DispatchWorkItem {
            // Post-switch settlement: Activate target space owner app if fullscreen
            if let pid = getOwnerPID(for: spaceID),
               let app = NSRunningApplication(processIdentifier: pid) {
                print("SpaceHelper: Activating fullscreen owner app (PID: \(pid)) on Space \(spaceID)")
                app.activate(options: .activateIgnoringOtherApps)
                return
            }
            
            guard let topWinInfo = getTopWindowInfo(forSpace: spaceID) else {
                // Fallback: Activate Finder to reset the menu bar
                print("SpaceHelper: No top window found on Space \(spaceID). Activating Finder.")
                if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
                    finder.activate(options: .activateIgnoringOtherApps)
                }
                return
            }
            
            let pid = topWinInfo.pid
            let windowID = topWinInfo.windowID
            
            if let app = NSRunningApplication(processIdentifier: pid) {
                print("SpaceHelper: Activating top window app \(app.localizedName ?? "") (PID: \(pid), Window: \(windowID)) on Space \(spaceID)")
                
                // 1. Activate application
                app.activate(options: .activateIgnoringOtherApps)
                
                // 2. Focus the specific window via Accessibility API
                _ = focusWindowViaAccessibility(pid: pid, windowID: windowID)
            }
        }
        
        pendingFocusTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    private static func postDockSwipe(phase: Int, directionRight: Bool, velocity: Double) -> Bool {
        // Use Float.leastNonzeroMagnitude to precisely match FLT_TRUE_MIN used in ISS.c
        // Double.leastNonzeroMagnitude is too small (e-324) and gets truncated to 0.0 by the OS when positive.
        let progress: Double = directionRight ? Double(Float.leastNonzeroMagnitude) : -Double(Float.leastNonzeroMagnitude)
        let vel: Double = directionRight ? velocity : -velocity
        
        guard let ev = CGEvent(source: nil) else { return false }
        ev.setIntegerValueField(CGEventField(rawValue: 55)!, value: 30) // kCGSEventDockControl
        ev.setIntegerValueField(CGEventField(rawValue: 110)!, value: 23) // kIOHIDEventTypeDockSwipe
        ev.setIntegerValueField(CGEventField(rawValue: 132)!, value: Int64(phase)) // phase
        ev.setDoubleValueField(CGEventField(rawValue: 124)!, value: progress)
        ev.setIntegerValueField(CGEventField(rawValue: 123)!, value: 1) // horizontal motion
        ev.setDoubleValueField(CGEventField(rawValue: 129)!, value: vel)
        ev.setDoubleValueField(CGEventField(rawValue: 130)!, value: vel)
        ev.setIntegerValueField(CGEventField(rawValue: 115)!, value: directionRight ? 8 : 4) // swipe mask: right=8, left=4
        
        var eventToPost = ev
        let os = ProcessInfo.processInfo.operatingSystemVersion
        if os.majorVersion >= 27 {
            if let augmented = GestureAugmentor.augmentEvent(ev)?.takeRetainedValue() {
                eventToPost = augmented
            }
        }
        
        // Use cgSessionEventTap to match ISS.c and prevent HID acceleration/mishandling
        eventToPost.post(tap: .cgSessionEventTap)
        return true
    }
    
    static func performSpaceSwitchGesture(steps: Int, targetDisplayID: String, forceInstant: Bool = false) {
        DiagnosticEventLog.shared.record(subsystem: "SpaceHelper", level: "info", "gesture steps=\(steps) display=\(targetDisplayID)")
        if steps == 0 { return }

        // macOS 27 interprets swipe directions opposite of the expected behavior,
        // so we invert the step direction to compensate.
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let adjustedSteps = os.majorVersion >= 27 ? -steps : steps
        let directionRight = adjustedSteps > 0
        let absSteps = abs(adjustedSteps)

        let target = targetDuration
        let velocity: Double
        if target <= 0 || forceInstant {
            // Instant mode — use the same 2000 base velocity as the old toggle,
            // no calibration needed.
            velocity = 2000.0 * Double(absSteps)
        } else {
            // Calibrated mode — record timing and use phase-appropriate velocity.
            // Phase 1 (first 3): native 52 → baseline measurement.
            // Phase 2 (next 3): 2× 104 → second data point.
            // Locked: computed multiplier applied to 52.
            beginGestureTiming(for: targetDisplayID)
            let phaseVelocity = velocityForPhase(displayID: targetDisplayID)
            velocity = phaseVelocity * Double(absSteps)
        }

        // Resolve target display via NSScreen.
        var targetScreen: NSScreen?
        for screen in NSScreen.screens {
            guard let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
            if CGDisplayCreateUUIDFromDisplayID(screenID).map({ CFUUIDCreateString(nil, $0.takeRetainedValue()) as String })?.uppercased() == targetDisplayID.uppercased()
                || "\(screenID)" == targetDisplayID {
                targetScreen = screen
                break
            }
        }

        // Warp mouse to target display only when cursor is on a different display.
        // Compare by NSScreen objects (not identifier strings) to avoid format mismatches.
        let originalLocation = CGEvent(source: nil)?.location ?? .zero
        var warped = false
        if let targetScreen = targetScreen {
            let cursorPoint = NSEvent.mouseLocation
            let cursorScreen = NSScreen.screens.first { NSMouseInRect(cursorPoint, $0.frame, false) }
            if cursorScreen != targetScreen {
                let screenID = targetScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
                let bounds = CGDisplayBounds(screenID)
                CGWarpMouseCursorPosition(CGPoint(x: bounds.midX, y: bounds.midY))
                warped = true
            }
        }
        
        for _ in 0..<absSteps {
            _ = postDockSwipe(phase: 1, directionRight: directionRight, velocity: velocity)
            _ = postDockSwipe(phase: 2, directionRight: directionRight, velocity: velocity)
            _ = postDockSwipe(phase: 4, directionRight: directionRight, velocity: velocity)
        }
        
        if warped {
            // Restore original position
            CGWarpMouseCursorPosition(originalLocation)
        }
    }

    // MARK: - Window Moving Logic
    
    static func dragActiveWindow(to spaceID: String, forceInstant: Bool = false) {
        DiagnosticEventLog.shared.record(subsystem: "SpaceHelper", level: "info", "dragActiveWindow → \(spaceID)")
        targetSpaceID = spaceID
        // Cancel any pending restoration from a previous "chained" move
        restorationTask?.cancel()
        restorationTask = nil

        // Hide preview labels before any mouse manipulation. The later switchToSpace call
        // also posts SpaceSwitchRequested, but in the meantime the simulated mouse events
        // (move, down, drag) would otherwise show labels while the app window is being
        // grabbed for the drag-move. Post immediately so labels are hidden throughout.
        NotificationCenter.default.post(
            name: NSNotification.Name("SpaceSwitchRequested"), object: nil)

        let source = CGEventSource(stateID: .hidSystemState)

        // Session Initialization: Capture original mouse state for the initial move.
        if originalMousePoint == nil {
            isInstantDrag = forceInstant
            // Save starting location
            originalMousePoint = CGEvent(source: nil)?.location
            
            // Get Active Window Info to calculate grab point
            guard let activeWindowInfo = getActiveWindowInfo() else {
                originalMousePoint = nil
                return 
            }
            
            draggedWindowID = activeWindowInfo.id
            draggedWindowPID = activeWindowInfo.pid
            if let runningApp = NSRunningApplication(processIdentifier: activeWindowInfo.pid) {
                draggedWindowBundleID = runningApp.bundleIdentifier
                draggedWindowAppName = runningApp.localizedName
            }
            draggedWindowOriginalFrame = activeWindowInfo.frame
            
            let frame = activeWindowInfo.frame
            let grabX: CGFloat
            let grabY: CGFloat
            var shouldDragFirst = false
            
            if let sm = AppDelegate.shared.spaceManager {
                if let bundleID = draggedWindowBundleID,
                   let exception = sm.appGrabExceptions.first(where: { $0.bundleIdentifier == bundleID }) {
                    grabX = frame.origin.x + CGFloat(exception.grabOffsetX)
                    grabY = frame.origin.y + CGFloat(exception.grabOffsetY)
                    shouldDragFirst = exception.shouldDragBeforeSwitch
                    print("SpaceHelper: Using per-app grab exception (\(exception.grabOffsetX), \(exception.grabOffsetY)) for \(exception.appName) (\(bundleID)), dragBeforeSwitch=\(shouldDragFirst)")
                } else {
                    grabX = frame.origin.x + CGFloat(sm.grabOffsetX)
                    grabY = frame.origin.y + CGFloat(sm.grabOffsetY)
                }
            } else {
                grabX = frame.origin.x + 13
                grabY = frame.origin.y + 25
            }
            
            let grabPoint = CGPoint(x: grabX, y: grabY)
            
            // Move to grab point and Down
            if let moveEvent = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: grabPoint, mouseButton: .left) {
                moveEvent.flags = []
                moveEvent.post(tap: .cgSessionEventTap)
            }
            
            if shouldDragFirst {
                usleep(50000) // 50ms settle after move for drag-first path
            }
            
            if let downEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: grabPoint, mouseButton: .left) {
                downEvent.flags = []
                downEvent.post(tap: .cgSessionEventTap)
            }
            
            usleep(shouldDragFirst ? 50000 : 10000) // 50ms grip for drag-first, 10ms otherwise
            
            if shouldDragFirst {
                // Drag 5px to the right and then reverse it back before switching spaces
                let dragAmount: CGFloat = 5
                let dragPoint = CGPoint(x: grabPoint.x + dragAmount, y: grabPoint.y)
                if let dragEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: dragPoint, mouseButton: .left) {
                    dragEvent.flags = []
                    dragEvent.setIntegerValueField(.mouseEventDeltaX, value: Int64(dragAmount)) // kCGEventAssociatedMouseDeltaX
                    dragEvent.setIntegerValueField(.mouseEventDeltaY, value: 0) // kCGEventAssociatedMouseDeltaY
                    dragEvent.post(tap: .cgSessionEventTap)
                }
                usleep(30000) // 30ms settle
                
                if let dragBackEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: grabPoint, mouseButton: .left) {
                    dragBackEvent.flags = []
                    dragBackEvent.setIntegerValueField(.mouseEventDeltaX, value: Int64(-dragAmount)) // kCGEventAssociatedMouseDeltaX
                    dragBackEvent.setIntegerValueField(.mouseEventDeltaY, value: 0) // kCGEventAssociatedMouseDeltaY
                    dragBackEvent.post(tap: .cgSessionEventTap)
                }
                usleep(30000) // 30ms settle

                // If the window drifted from its original position after the drag-back,
                // warp the cursor to maintain the correct grab offset so the window
                // isn't "dragged behind" during the space switch.
                if let actual = getWindowInfo(id: activeWindowInfo.id) {
                    let dx = actual.frame.origin.x - frame.origin.x
                    let dy = actual.frame.origin.y - frame.origin.y
                    if abs(dx) >= 1 || abs(dy) >= 1 {
                        let correctedGrabPoint = CGPoint(x: grabPoint.x + dx, y: grabPoint.y + dy)
                        CGWarpMouseCursorPosition(correctedGrabPoint)
                    }
                }
            } else {
                // Standard windows with native titlebars automatically bind to the cursor on mouseDown.
                // We bypass drag simulation entirely to prevent unnecessary window shifting.
                let remainingTime = max(0, (forceInstant ? 20000 : 50000) - 10000)
                if remainingTime > 0 {
                    usleep(useconds_t(remainingTime))
                }
            }
        }
        
        // Trigger the space switch and track the movement.
        pendingMoveCount += 1
        switchToSpace(spaceID, forceInstant: forceInstant)
        
        // Schedule a safety fallback for cursor restoration.
        // Ensures the mouse is released after a timeout if the space change detection fails.
        scheduleRestoration(delay: 2.0)
    }
    
    /// Fast-forwards the restoration process because we detected a successful space change.
    static func signalSpaceSwitchComplete(arrivedAtSpaceID: String) {
        DiagnosticEventLog.shared.record(subsystem: "SpaceHelper", level: "info", "signalSpaceSwitchComplete(\(arrivedAtSpaceID))")
        guard originalMousePoint != nil else { return }
        
        let arrivedUUID = arrivedAtSpaceID.uppercased()
        let targetID = targetSpaceID?.uppercased() ?? ""
        
        // Prevent premature completion if we get notifications from other spaces.
        // We match either the raw Wallpaper UUID (for manual mode) or the active ManagedSpaceID (for automatic mode).
        let currentManagedSpaceIDs = getCurrentSpaceIDs().map { $0.uppercased() }
        let isMatch = (arrivedUUID == targetID) || currentManagedSpaceIDs.contains(targetID)
        
        guard isMatch else {
            print("SpaceHelper: Ignoring premature space change event to \(arrivedAtSpaceID) (waiting for \(targetSpaceID ?? ""))")
            return
        }
        
        print("SpaceHelper: Arrived at target space \(arrivedAtSpaceID). Completing move...")
        
        // Decrement pending moves
        pendingMoveCount = max(0, pendingMoveCount - 1)
        
        // Only trigger the "Drop & Restore" if all pending moves are accounted for.
        // We replace the 2.0s safety timer with a quick 0.15s settle-and-restore.
        if pendingMoveCount == 0 {
            let delay = isInstantDrag ? 0.01 : 0.15
            scheduleRestoration(delay: delay)
        }
    }
    
    /// Schedules an atomic cleanup task that drops the window and restores the cursor.
    /// Calling this automatically cancels any previously scheduled restoration job.
    private static func scheduleRestoration(delay: TimeInterval) {
        // Atomic Cancellation: This is the critical fix for "multi restoration" bugs.
        restorationTask?.cancel()
        
        let source = CGEventSource(stateID: .hidSystemState)
        let isInstant = isInstantDrag
        let task = DispatchWorkItem { [originalPoint = originalMousePoint] in
            guard let restorePoint = originalPoint else { 
                originalMousePoint = nil
                restorationTask = nil
                pendingMoveCount = 0
                return 
            }
            
            // Release the window (Mouse Up).
            if let upEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: CGEvent(source: nil)?.location ?? .zero, mouseButton: .left) {
                upEvent.flags = []
                upEvent.post(tap: .cgSessionEventTap)
            }

            // Restore window to its original position if it shifted during drag-before-switch.
            if let frame = draggedWindowOriginalFrame, let wid = draggedWindowID, let pid = draggedWindowPID {
                let appElement = AXUIElementCreateApplication(pid)
                var windowsRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                   let axWindows = windowsRef as? [AXUIElement] {
                    for axWindow in axWindows {
                        var cgWID: CGWindowID = 0
                        if _AXUIElementGetWindow(axWindow, &cgWID) == 0, cgWID == CGWindowID(wid) {
                            var point = frame.origin
                            if let positionRef = AXValueCreate(.cgPoint, &point) {
                                AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, positionRef)
                            }
                            break
                        }
                    }
                }
            }
            
            // Verify window move success after a small delay
            let winID = draggedWindowID
            let bundleID = draggedWindowBundleID
            let appName = draggedWindowAppName
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let winID = winID, let bundleID = bundleID, let appName = appName {
                    verifyMoveSuccess(windowID: winID, bundleID: bundleID, appName: appName)
                }
            }
            
            // Restore the cursor position.
            usleep(isInstant ? 5000 : 50000) // 5ms for instant switches, 50ms otherwise
            if let restoreEvent = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: restorePoint, mouseButton: .left) {
                restoreEvent.flags = []
                restoreEvent.post(tap: .cgSessionEventTap)
            }
            
            // Reset session state.
            originalMousePoint = nil
            restorationTask = nil
            pendingMoveCount = 0
            targetSpaceID = nil
            draggedWindowID = nil
            draggedWindowPID = nil
            draggedWindowBundleID = nil
            draggedWindowAppName = nil
            draggedWindowOriginalFrame = nil
        }
        
        restorationTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }
    
    private static func verifyMoveSuccess(windowID: Int, bundleID: String, appName: String) {
        // Query visible windows on the screen
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        
        let isStillVisible = windowList.contains { window in
            if let id = window[kCGWindowNumber as String] as? Int, id == windowID {
                return true
            }
            return false
        }
        
        if !isStillVisible {
            DiagnosticEventLog.shared.record(subsystem: "SpaceHelper", level: "error", "Window move FAILED for \(appName) (ID: \(windowID))")
            print("SpaceHelper: Window move failed for \(appName) (ID: \(windowID), BundleID: \(bundleID))")
            
            // Trigger failure HUD notification
            DispatchQueue.main.async {
                handleMoveFailure(bundleID: bundleID, appName: appName)
            }
        } else {
            print("SpaceHelper: Window move succeeded for \(appName) (ID: \(windowID))")
        }
    }
    
    private static func handleMoveFailure(bundleID: String, appName: String) {
        guard let sm = AppDelegate.shared.spaceManager else { return }
        
        let hasException = sm.appGrabExceptions.contains(where: { $0.bundleIdentifier == bundleID })
        
        let message = String(format: String(localized: "Moving window failed for %@"), appName)
        let buttonTitle = hasException ? String(localized: "Edit Exception") : String(localized: "Add Exception")
        
        HUDWindowController.shared.show(
            message: message,
            systemImage: "exclamationmark.triangle.fill",
            iconColor: .orange,
            buttonTitle: buttonTitle
        ) {
            DispatchQueue.main.async {
                if !hasException {
                    // Automatically add the exception with default grab values
                    let newException = AppGrabException(
                        bundleIdentifier: bundleID,
                        appName: appName,
                        grabOffsetX: sm.grabOffsetX,
                        grabOffsetY: sm.grabOffsetY
                    )
                    withAnimation {
                        sm.appGrabExceptions.append(newException)
                    }
                }
                
                // Set autoEditBundleID to open the editor sheet
                sm.autoEditBundleID = bundleID
                
                // Open Settings settings switch tab
                AppDelegate.shared.statusBarController?.openSettingsWindow(tab: .sswitch)
            }
        }
    }
    
    static func getActiveWindowInfo() -> (id: Int, pid: Int32, frame: CGRect)? {
        let ourPID = ProcessInfo.processInfo.processIdentifier
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        
        if frontApp.processIdentifier == ourPID {
            // Find the first window in Z-order that is layer 0, not our PID, has valid size, and belongs to a regular app.
            for window in windowList {
                guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                      let windowPid = window[kCGWindowOwnerPID as String] as? Int,
                      windowPid != Int(ourPID),
                      let wid = window[kCGWindowNumber as String] as? Int,
                      let bounds = window[kCGWindowBounds as String] as? [String: Any],
                      let x = bounds["X"] as? CGFloat, let y = bounds["Y"] as? CGFloat,
                      let w = bounds["Width"] as? CGFloat, let h = bounds["Height"] as? CGFloat,
                      w >= minActiveWindowWidth, h >= minActiveWindowHeight
                else { continue }
                
                // Reject transparent or non-shared utility windows
                if let alpha = window[kCGWindowAlpha as String] as? Double, alpha <= 0.1 { continue }
                if let sharing = window[kCGWindowSharingState as String] as? Int, sharing == 0 { continue }
                
                // Ensure it's a regular application window (not a system overlay)
                if let app = NSRunningApplication(processIdentifier: Int32(windowPid)),
                   app.activationPolicy == .regular {
                    let info = (id: wid, pid: Int32(windowPid), frame: CGRect(x: x, y: y, width: w, height: h))
                    print("SpaceHelper: Captured active window ID: \(info.id), PID: \(info.pid), frame: \(info.frame) (using fallback scan)")
                    return info
                }
            }
        } else {
            let pid = frontApp.processIdentifier
            for window in windowList {
                if let windowPid = window[kCGWindowOwnerPID as String] as? Int,
                   windowPid == pid,
                   let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                   let wid = window[kCGWindowNumber as String] as? Int,
                   let bounds = window[kCGWindowBounds as String] as? [String: Any],
                   let x = bounds["X"] as? CGFloat, let y = bounds["Y"] as? CGFloat,
                   let w = bounds["Width"] as? CGFloat, let h = bounds["Height"] as? CGFloat {
                       
                       // Apply the same strict filtering for foreign windows to avoid capturing transparent/overlay helper windows!
                       if w < minActiveWindowWidth || h < minActiveWindowHeight { continue }
                       if let alpha = window[kCGWindowAlpha as String] as? Double, alpha <= 0.1 { continue }
                       if let sharing = window[kCGWindowSharingState as String] as? Int, sharing == 0 { continue }
                       
                       let info = (id: wid, pid: Int32(pid), frame: CGRect(x: x, y: y, width: w, height: h))
                       print("SpaceHelper: Captured active window ID: \(info.id), PID: \(info.pid), frame: \(info.frame)")
                       return info
                   }
            }
        }
        return nil
    }

    static func getActiveWindowInfo(forPID pid: Int32) -> (id: Int, pid: Int32, frame: CGRect)? {
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements)
        let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        
        for window in windowList {
            if let windowPid = window[kCGWindowOwnerPID as String] as? Int,
               windowPid == Int(pid),
               let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
               let wid = window[kCGWindowNumber as String] as? Int,
               let bounds = window[kCGWindowBounds as String] as? [String: Any],
               let x = bounds["X"] as? CGFloat, let y = bounds["Y"] as? CGFloat,
               let w = bounds["Width"] as? CGFloat, let h = bounds["Height"] as? CGFloat {
                   
                   // Apply filtering
                   if w < minActiveWindowWidth || h < minActiveWindowHeight { continue }
                   if let alpha = window[kCGWindowAlpha as String] as? Double, alpha <= 0.1 { continue }
                   if let sharing = window[kCGWindowSharingState as String] as? Int, sharing == 0 { continue }
                   
                   return (id: wid, pid: pid, frame: CGRect(x: x, y: y, width: w, height: h))
               }
        }
        return nil
    }

    static func getWindowInfo(id: Int) -> (pid: Int32, frame: CGRect)? {
        let options = CGWindowListOption(arrayLiteral: .optionIncludingWindow)
        let windowList = CGWindowListCopyWindowInfo(options, CGWindowID(id)) as? [[String: Any]] ?? []
        
        if let window = windowList.first,
           let pid = window[kCGWindowOwnerPID as String] as? Int32,
           let bounds = window[kCGWindowBounds as String] as? [String: Any],
           let x = bounds["X"] as? CGFloat, let y = bounds["Y"] as? CGFloat,
           let w = bounds["Width"] as? CGFloat, let h = bounds["Height"] as? CGFloat {
               return (pid: pid, frame: CGRect(x: x, y: y, width: w, height: h))
        }
        return nil
    }

    static func getWindowSpaceID(id: Int) -> String? {
        let conn = _CGSDefaultConnection()
        let widArray = [id as NSNumber] as CFArray
        if let result = CGSCopySpacesForWindows(conn, 7, widArray),
           let spaceIDs = result as? [NSNumber],
           let firstSpace = spaceIDs.first {
            return String(firstSpace.intValue)
        }
        return nil
    }

    static func getActiveWindowFrame() -> CGRect? {
        return getActiveWindowInfo()?.frame
    }

    private static func getOwnerPID(for spaceID: String) -> Int32? {
        let conn = _CGSDefaultConnection()
        guard let displays = CGSCopyManagedDisplaySpaces(conn) as? [NSDictionary] else {
            return nil
        }

        for display in displays {
            guard let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            for space in spaces {
                guard let managedID = space["ManagedSpaceID"] as? Int,
                    String(managedID) == spaceID
                else { continue }

                return space["pid"] as? Int32 ?? space["owner pid"] as? Int32
            }
        }
        return nil
    }



    // Shortcut configuration helpers.

    private static func isShortcutEnabled(for number: Int) -> Bool {
        let baseID = 118
        let targetID = baseID + (number - 1)

        guard
            let dict = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys"),
            let hotkeys = dict["AppleSymbolicHotKeys"] as? [String: Any]
        else {
            return true
        }

        guard let targetKeyDict = hotkeys[String(targetID)] as? [String: Any] else {
            return true
        }

        if let enabled = targetKeyDict["enabled"] as? Bool, !enabled {
            return false
        }

        if let value = targetKeyDict["value"] as? [String: Any],
            let parameters = value["parameters"] as? [Int],
            parameters.count >= 3
        {

            let registeredKeyCode = parameters[1]
            let registeredModifiers = parameters[2]

            let expectedKeyCode = Int(getKeyCode(for: number))
            let expectedModifiers = 262144  // Control

            if registeredKeyCode != expectedKeyCode || registeredModifiers != expectedModifiers {
                return false
            }
        }

        return true
    }

    private static func getKeyCode(for number: Int) -> CGKeyCode {
        switch number {
        case 1: return 18
        case 2: return 19
        case 3: return 20
        case 4: return 21
        case 5: return 23
        case 6: return 22
        case 7: return 26
        case 8: return 28
        case 9: return 25
        case 10: return 29
        default: return 255
        }
    }

    @discardableResult
    private static func simulateDesktopShortcut(for number: Int) -> Bool {
        let code = getKeyCode(for: number)
        if code == 255 { return false }

        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        else {
            return false
        }

        keyDown.flags = .maskControl
        keyUp.flags = .maskControl

        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)

        return true
    }

    static func startMonitoring(onChange: @escaping (String, Bool, Int, String) -> Void) {
        onSpaceChange = onChange

        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { _ in detectSpaceChange() }
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

    private static func normalizeDisplayID(_ id: String, mainUUID: String?) -> String {
        let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanId.isEmpty || cleanId.uppercased() == "MAIN" || cleanId.uppercased() == "UNKNOWN" {
            return mainUUID?.uppercased() ?? "MAIN"
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

    static func getWindowsForAllSpaces(spaces: [DesktopSpace], spaceNames: [String: String]) -> String {
        let conn = _CGSDefaultConnection()
        let ourPID = ProcessInfo.processInfo.processIdentifier

        // Pre-calculate screen mapping for efficiency as recommended by reviewer.
        var screenMap: [String: String] = [:]
        for screen in NSScreen.screens {
            if let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
               let uuidRef = CGDisplayCreateUUIDFromDisplayID(id) {
                let uuid = uuidRef.takeRetainedValue()
                let uuidStr = (CFUUIDCreateString(nil, uuid) as String).uppercased()
                screenMap[uuidStr] = screen.localizedName
            }
        }

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
        else { return "" }

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
            guard let displays = CGSCopyManagedDisplaySpaces(conn) as? [NSDictionary] else { return "" }
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

        // Build output sorted by display then number.
        let sortedSpaces = spaces.sorted {
            if $0.displayID != $1.displayID { return $0.displayID < $1.displayID }
            return $0.num < $1.num
        }

        var output = ""
        for space in sortedSpaces {
            let name = spaceNames[space.id] ?? ""
            let displayName = getDisplayName(for: space.displayID, screenMap: screenMap)
            output += ">\(space.id)~\(name)~\(displayName)~\(space.num)~\(space.isFullscreen ? "1" : "0")~\(space.appPath ?? "")\n"

            guard let windows = windowsBySpaceID[space.id] else { continue }
            for window in windows {
                guard let wid = window[kCGWindowNumber as String] as? Int,
                      let pid = window[kCGWindowOwnerPID as String] as? Int,
                      let appPath = pidToAppPath[Int32(pid)]
                else { continue }

                let ownerName = window[kCGWindowOwnerName as String] as? String ?? ""
                let title = window[kCGWindowName as String] as? String ?? ""
                let isMinimized = minimizedAXWindowIDs.contains(wid) ? "1" : "0"
                let isHidden = (NSRunningApplication(processIdentifier: Int32(pid))?.isHidden ?? false) ? "1" : "0"
                output += "  \(wid)|\(pid)|\(ownerName)|\(appPath)|\(title)|\(isMinimized)|\(isHidden)\n"
            }
        }
        return output
    }

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

    /// Returns the display UUID that a specific space belongs to.
    static func getDisplayID(for spaceID: String) -> String? {
        let conn = _CGSDefaultConnection()
        guard let displays = CGSCopyManagedDisplaySpaces(conn) as? [NSDictionary] else {
            return nil
        }
        
        let screenUUIDs = getAllDisplayUUIDs()
        let mainScreenUUID = screenUUIDs.first

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

    private static func getDisplayName(for uuidString: String, screenMap: [String: String]) -> String {
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
        
        let screenUUIDs = getAllDisplayUUIDs()
        let mainScreenUUID = screenUUIDs.first

        for display in displays {
            if let rawID = display["Display Identifier"] as? String {
                let currentID = normalizeDisplayID(rawID, mainUUID: mainScreenUUID)
                if currentID == displayID,
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
                let parentElement = parentVal as! AXUIElement
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
