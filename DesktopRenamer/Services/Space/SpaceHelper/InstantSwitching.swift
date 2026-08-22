import AppKit
import CoreGraphics
import Foundation

extension SpaceHelper {

    // MARK: - Instant Space Switch Helpers
    
    // MARK: - SLS Space Switching for macOS 27+
    
    static func shouldSwitchToSpaceUsingSLS() -> Bool {
        // Automatic version check: SLS Operation for macOS 27+, legacy swipe for older.
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
                    lastProgrammaticSwitchUsedSLS = true
                    return true
                }
            }
        }
        
        // Fallback for compatibility
        if let operation = initializedOp as? Operation {
            DiagnosticEventLog.shared.record(subsystem: "SpaceHelper", level: "info", "Executing SLS operation via OperationQueue: \(displayUUID), \(spaceID)")
            OperationQueue.main.addOperation(operation)
            lastProgrammaticSwitchUsedSLS = true
            return true
        } else {
            let startSel = NSSelectorFromString("start")
            if initializedOp.responds(to: startSel) {
                DiagnosticEventLog.shared.record(subsystem: "SpaceHelper", level: "info", "Starting SLS operation via start selector: \(displayUUID), \(spaceID)")
                initializedOp.perform(startSel)
                lastProgrammaticSwitchUsedSLS = true
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
}

