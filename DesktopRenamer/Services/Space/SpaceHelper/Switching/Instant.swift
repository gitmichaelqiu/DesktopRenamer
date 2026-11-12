import AppKit
import CoreGraphics
import Foundation

private enum SyntheticSpaceGestureStream {

    private struct Gesture {
        let id: UUID
        let directionRight: Bool
        let frameCount: Int
        let progressPerFrame: Double
        let exitVelocity: Double
        let startTime: DispatchTime
        let originalMouseLocation: CGPoint?
        let shouldRestoreMouse: Bool
        var progress: Double
    }

    private static let queue = DispatchQueue(
        label: "dev.mqiu.DesktopRenamer.synthetic-space-gesture",
        qos: .userInteractive
    )
    private static var activeGesture: Gesture?
    private static var nextFrameWorkItem: DispatchWorkItem?

    static func start(
        steps: Int,
        directionRight: Bool,
        targetDuration: TimeInterval,
        warpLocation: CGPoint?
    ) {
        queue.sync {
            cancelActiveGesture()

            let originalMouseLocation = CGEvent(source: nil)?.location
            let shouldRestoreMouse = warpLocation != nil && originalMouseLocation != nil
            if let warpLocation, shouldRestoreMouse {
                CGWarpMouseCursorPosition(warpLocation)
            }

            let duration = max(
                SpaceHelper.linearGestureFrameInterval,
                targetDuration * Double(steps)
            )
            let frameCount = max(
                1,
                Int(ceil(duration / SpaceHelper.linearGestureFrameInterval))
            )
            let progressPerFrame =
                SpaceHelper.linearGestureProgressPerSpace * Double(steps)
                / Double(frameCount)
            let exitVelocity = progressPerFrame * 100
            let id = UUID()
            let startTime = DispatchTime.now()

            activeGesture = Gesture(
                id: id,
                directionRight: directionRight,
                frameCount: frameCount,
                progressPerFrame: progressPerFrame,
                exitVelocity: exitVelocity,
                startTime: startTime,
                originalMouseLocation: originalMouseLocation,
                shouldRestoreMouse: shouldRestoreMouse,
                progress: progressPerFrame
            )

            guard SpaceHelper.postDockSwipe(
                phase: 1,
                directionRight: directionRight,
                progress: progressPerFrame,
                velocity: 0
            ) else {
                finishActiveGesture()
                return
            }

            scheduleFrame(id: id, frameIndex: 1)
        }
    }

    static func cancel() {
        queue.sync {
            cancelActiveGesture()
        }
    }

    private static func scheduleFrame(id: UUID, frameIndex: Int) {
        guard let gesture = activeGesture, gesture.id == id else { return }

        let interval = SpaceHelper.linearGestureFrameInterval
        let offset = UInt64(Double(frameIndex) * interval * 1_000_000_000)
        let deadline = DispatchTime(uptimeNanoseconds: gesture.startTime.uptimeNanoseconds + offset)
        let workItem = DispatchWorkItem {
            guard var currentGesture = activeGesture, currentGesture.id == id else { return }

            if frameIndex < currentGesture.frameCount {
                let progress = currentGesture.progressPerFrame * Double(frameIndex + 1)
                guard SpaceHelper.postDockSwipe(
                    phase: 2,
                    directionRight: currentGesture.directionRight,
                    progress: progress,
                    velocity: 0
                ) else {
                    cancelActiveGesture()
                    return
                }

                currentGesture.progress = progress
                activeGesture = currentGesture
                scheduleFrame(id: id, frameIndex: frameIndex + 1)
                return
            }

            _ = SpaceHelper.postDockSwipe(
                phase: 4,
                directionRight: currentGesture.directionRight,
                progress: currentGesture.progress,
                velocity: currentGesture.exitVelocity
            )
            finishActiveGesture()
        }
        nextFrameWorkItem = workItem
        queue.asyncAfter(deadline: deadline, execute: workItem)
    }

    private static func cancelActiveGesture() {
        nextFrameWorkItem?.cancel()
        nextFrameWorkItem = nil

        guard let gesture = activeGesture else { return }
        _ = SpaceHelper.postDockSwipe(
            phase: 8,
            directionRight: gesture.directionRight,
            progress: gesture.progress,
            velocity: gesture.exitVelocity
        )
        finishActiveGesture()
    }

    private static func finishActiveGesture() {
        nextFrameWorkItem?.cancel()
        nextFrameWorkItem = nil

        guard let gesture = activeGesture else { return }
        activeGesture = nil
        if gesture.shouldRestoreMouse, let originalMouseLocation = gesture.originalMouseLocation {
            CGWarpMouseCursorPosition(originalMouseLocation)
        }
    }
}

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
    
    private static let gestureDirectionPreferencePrefix =
        "dev.mqiu.DesktopRenamer.spaceGestureDirectionInverted"

    /// Shared Spaces expose one managed display to CGS even when multiple
    /// physical displays are connected. macOS 27 release builds use the
    /// pre-beta gesture direction in that layout, while the existing
    /// augmented-event compensation remains the correct default for the
    /// separate-Space layout.
    static func usesSharedDisplaySpaces() -> Bool {
        guard NSScreen.screens.count > 1 else { return false }
        return getCurrentSpaceIDsByDisplay().count == 1
    }

    static func gestureDirectionLayout() -> String {
        usesSharedDisplaySpaces() ? "shared" : "separate"
    }

    private static func gestureDirectionPreferenceKey(
        for displayID: String,
        layout: String
    ) -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        return "\(gestureDirectionPreferencePrefix).\(os).\(layout).\(displayID)"
    }

    private static func defaultGestureDirectionInversion(layout: String) -> Bool {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return os.majorVersion >= 27 && layout != "shared"
    }

    static func gestureDirectionIsInverted(
        for displayID: String,
        layout: String? = nil
    ) -> Bool {
        let layout = layout ?? gestureDirectionLayout()
        let key = gestureDirectionPreferenceKey(for: displayID, layout: layout)
        if let stored = UserDefaults.standard.object(forKey: key) as? Bool {
            return stored
        }
        return defaultGestureDirectionInversion(layout: layout)
    }

    /// Records a direction anomaly. The next gesture uses the other
    /// convention, and the preference remains there until a later anomaly
    /// proves that it is no longer valid.
    static func flipGestureDirection(for displayID: String, layout: String? = nil) {
        let layout = layout ?? gestureDirectionLayout()
        let key = gestureDirectionPreferenceKey(for: displayID, layout: layout)
        let oldValue = gestureDirectionIsInverted(for: displayID, layout: layout)
        let newValue = !oldValue
        UserDefaults.standard.set(newValue, forKey: key)
        DiagnosticEventLog.shared.record(
            subsystem: "SpaceHelper",
            level: "warning",
            "gesture direction preference flipped: display=\(displayID), inverted=\(oldValue) -> \(newValue)"
        )
    }

    static func confirmGestureDirection(for displayID: String, layout: String? = nil) {
        let layout = layout ?? gestureDirectionLayout()
        let key = gestureDirectionPreferenceKey(for: displayID, layout: layout)
        let value = gestureDirectionIsInverted(for: displayID, layout: layout)
        UserDefaults.standard.set(value, forKey: key)
    }

    fileprivate static func postDockSwipe(
        phase: Int,
        directionRight: Bool,
        progress: Double? = nil,
        velocity: Double
    ) -> Bool {
        // Use Float.leastNonzeroMagnitude to precisely match FLT_TRUE_MIN used in ISS.c
        // Double.leastNonzeroMagnitude is too small (e-324) and gets truncated to 0.0 by the OS when positive.
        let progress = progress.map { directionRight ? $0 : -$0 }
            ?? (directionRight ? Double(Float.leastNonzeroMagnitude) : -Double(Float.leastNonzeroMagnitude))
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
    
    static func performSpaceSwitchGesture(
        steps: Int,
        targetDisplayID: String,
        forceInstant: Bool = false,
        gestureLayout: String? = nil
    ) {
        let gestureLayout = gestureLayout ?? gestureDirectionLayout()
        let invertDirection = gestureDirectionIsInverted(
            for: targetDisplayID,
            layout: gestureLayout
        )
        DiagnosticEventLog.shared.record(
            subsystem: "SpaceHelper",
            level: "info",
            "gesture steps=\(steps) display=\(targetDisplayID) layout=\(gestureLayout) inverted=\(invertDirection)"
        )
        if steps == 0 { return }

        // Finish any earlier timed stream before reading the pointer position
        // or emitting another gesture. This keeps rapid requests ordered and
        // makes the target-display cursor warp independent of the old stream.
        SyntheticSpaceGestureStream.cancel()

        let adjustedSteps = invertDirection ? -steps : steps
        let directionRight = adjustedSteps > 0
        let absSteps = abs(adjustedSteps)

        let target = targetDuration
        let isInstant = forceInstant || !target.isFinite || target <= 0
        let velocity = 2000.0 * Double(absSteps)

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

        // Warp to the target display only when the cursor is on another display.
        // Resolve the AppKit screen information here; the event stream itself
        // runs on its own queue so frame timing never blocks the main thread.
        var warpLocation: CGPoint?
        if let targetScreen = targetScreen {
            let cursorPoint = NSEvent.mouseLocation
            let cursorScreen = NSScreen.screens.first { NSMouseInRect(cursorPoint, $0.frame, false) }
            if cursorScreen != targetScreen {
                let screenID = targetScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
                let bounds = CGDisplayBounds(screenID)
                warpLocation = CGPoint(x: bounds.midX, y: bounds.midY)
            }
        }

        if isInstant {
            let originalLocation = CGEvent(source: nil)?.location ?? .zero
            if let warpLocation {
                CGWarpMouseCursorPosition(warpLocation)
            }
            for _ in 0..<absSteps {
                _ = postDockSwipe(phase: 1, directionRight: directionRight, velocity: velocity)
                _ = postDockSwipe(phase: 2, directionRight: directionRight, velocity: velocity)
                _ = postDockSwipe(phase: 4, directionRight: directionRight, velocity: velocity)
            }
            if warpLocation != nil {
                CGWarpMouseCursorPosition(originalLocation)
            }
            return
        }

        let duration = min(target, 1.0)
        DiagnosticEventLog.shared.record(
            subsystem: "SpaceHelper",
            level: "info",
            "linear gesture durationPerSpace=\(duration), frameInterval=\(linearGestureFrameInterval), progressPerSpace=\(linearGestureProgressPerSpace)"
        )
        SyntheticSpaceGestureStream.start(
            steps: absSteps,
            directionRight: directionRight,
            targetDuration: duration,
            warpLocation: warpLocation
        )
    }
}
