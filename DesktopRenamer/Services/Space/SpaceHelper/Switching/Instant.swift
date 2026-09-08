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
