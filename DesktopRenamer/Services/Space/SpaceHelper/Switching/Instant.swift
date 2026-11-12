import AppKit
import CoreFoundation
import CoreGraphics
import Darwin
import Foundation

private enum SyntheticSpaceGestureStream {

    private struct Gesture {
        let id: UUID
        let directionRight: Bool
        let sourceSpaceID: String?
        let targetSpaceID: String?
        let switchGeneration: UInt64?
        let targetDisplayID: String
        let gestureLayout: String
        let targetDuration: TimeInterval
        let totalSteps: Int
        let frameCount: Int
        let progressPerFrame: Double
        let commitVelocity: Double
        let startedAt: DispatchTime
        var stepStartTime: DispatchTime
        var lastProgressTime: DispatchTime
        var lastEndedAt: DispatchTime?
        let originalMouseLocation: CGPoint?
        let shouldRestoreMouse: Bool
        var completedSteps: Int
        var swipeInProgress: Bool
        var progress: Double
        var changedFrameCount: Int
        var frameIntervalSum: TimeInterval
        var minFrameInterval: TimeInterval?
        var maxFrameInterval: TimeInterval
        var maxDeadlineSlip: TimeInterval
        var swipeDurations: [TimeInterval]
        var settleDurations: [TimeInterval]
    }

    private static let queue = DispatchQueue(
        label: "dev.mqiu.DesktopRenamer.synthetic-space-gesture",
        qos: .userInteractive
    )
    private static var activeGesture: Gesture?
    private static var nextFrameWorkItem: DispatchWorkItem?
    private static var lastAnimationSummary = "none"
    private static var lastFinishedGestureID: String?
    private static var lastFinishedSwitchGeneration: UInt64?

    static func start(
        steps: Int,
        sourceSpaceID: String?,
        targetSpaceID: String?,
        switchGeneration: UInt64?,
        directionRight: Bool,
        targetDuration: TimeInterval,
        targetDisplayID: String,
        gestureLayout: String,
        warpLocation: CGPoint?
    ) {
        queue.sync {
            cancelActiveGesture(reason: "superseded by a new space switch")

            let originalMouseLocation = CGEvent(source: nil)?.location
            let shouldRestoreMouse = warpLocation != nil && originalMouseLocation != nil
            if let warpLocation, shouldRestoreMouse {
                CGWarpMouseCursorPosition(warpLocation)
            }

            let durationPerStep = max(
                SpaceHelper.linearGestureFrameInterval,
                targetDuration
            )
            let frameCount = max(
                1,
                Int(ceil(durationPerStep / SpaceHelper.linearGestureFrameInterval))
            )
            let progressPerFrame = SpaceHelper.linearGestureProgressPerSpace
                * SpaceHelper.linearGestureFrameInterval / durationPerStep
            let commitVelocity = SpaceHelper.linearGestureCommitVelocity
            let id = UUID()
            let now = DispatchTime.now()
            let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
            let usesModernDockSwipeProtocol = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
            let eventPath = usesModernDockSwipeProtocol
                ? "augmented Dock swipe + companion gesture event"
                : "legacy CGEvent"

            activeGesture = Gesture(
                id: id,
                directionRight: directionRight,
                sourceSpaceID: sourceSpaceID,
                targetSpaceID: targetSpaceID,
                switchGeneration: switchGeneration,
                targetDisplayID: targetDisplayID,
                gestureLayout: gestureLayout,
                targetDuration: durationPerStep,
                totalSteps: steps,
                frameCount: frameCount,
                progressPerFrame: progressPerFrame,
                commitVelocity: commitVelocity,
                startedAt: now,
                stepStartTime: now,
                lastProgressTime: now,
                lastEndedAt: nil,
                originalMouseLocation: originalMouseLocation,
                shouldRestoreMouse: shouldRestoreMouse,
                completedSteps: 0,
                swipeInProgress: false,
                progress: 0,
                changedFrameCount: 0,
                frameIntervalSum: 0,
                minFrameInterval: nil,
                maxFrameInterval: 0,
                maxDeadlineSlip: 0,
                swipeDurations: [],
                settleDurations: []
            )

            DiagnosticEventLog.shared.record(
                subsystem: "SpaceGestureAnimation",
                level: "info",
                "phase=start id=\(id.uuidString) generation=\(switchGeneration.map(String.init) ?? "nil") source=\(sourceSpaceID ?? "nil") target=\(targetSpaceID ?? "nil") display=\(targetDisplayID) layout=\(gestureLayout) direction=\(directionRight ? "right" : "left") steps=\(steps) targetDurationPerSpace=\(durationPerStep) frameInterval=\(SpaceHelper.linearGestureFrameInterval) progressPerSpace=\(SpaceHelper.linearGestureProgressPerSpace) settleInterval=\(SpaceHelper.linearGestureSettleInterval) framesPerSwipe=\(frameCount) progressPerFrame=\(progressPerFrame) commitVelocity=\(commitVelocity) os=\(osVersion) eventPath=\(eventPath) directionConvention=\(usesModernDockSwipeProtocol ? "natural-scroll-sign" : "legacy")"
            )

            guard postGestureBegan(id: id) else {
                finishActiveGesture(outcome: "failed to post began phase")
                return
            }

            scheduleFrame(id: id, frameIndex: 1)
        }
    }

    static func cancel() {
        queue.sync {
            cancelActiveGesture(reason: "superseded by a new space switch")
        }
    }

    static var diagnosticInfo: String {
        return queue.sync { () -> String in
            guard let gesture = activeGesture else {
                return "active: false\nlastAnimation: \(lastAnimationSummary)\n"
            }

            let elapsed = seconds(from: gesture.startedAt, to: .now())
            let phase = gesture.swipeInProgress ? "swiping" : "settling"
            return """
            active: true
            gestureID: \(gesture.id.uuidString)
            sourceSpaceID: \(gesture.sourceSpaceID ?? "nil")
            targetSpaceID: \(gesture.targetSpaceID ?? "nil")
            switchGeneration: \(gesture.switchGeneration.map(String.init) ?? "nil")
            targetDisplayID: \(gesture.targetDisplayID)
            gestureLayout: \(gesture.gestureLayout)
            direction: \(gesture.directionRight ? "right" : "left")
            targetDurationPerSpace: \(gesture.targetDuration)
            framesPerSwipe: \(gesture.frameCount)
            progressPerFrame: \(gesture.progressPerFrame)
            commitVelocity: \(gesture.commitVelocity)
            progress: \(gesture.progress)
            currentStep: \(min(gesture.completedSteps + 1, gesture.totalSteps))/\(gesture.totalSteps)
            currentPhase: \(phase)
            completedSteps: \(gesture.completedSteps)
            elapsedMs: \(milliseconds(elapsed))
            changedFrameCount: \(gesture.changedFrameCount)
            frameIntervalMs: \(frameIntervalStatistics(gesture))
            maximumDeadlineSlipMs: \(milliseconds(gesture.maxDeadlineSlip))
            swipeDurationMs: \(durationStatistics(gesture.swipeDurations))
            settleDurationMs: \(durationStatistics(gesture.settleDurations))
            lastAnimation: \(lastAnimationSummary)
            """
        }
    }

    static func diagnosticGestureID(for switchGeneration: UInt64?) -> String? {
        queue.sync {
            if let activeGesture {
                return activeGesture.id.uuidString
            }
            guard switchGeneration != nil,
                  switchGeneration == lastFinishedSwitchGeneration else {
                return nil
            }
            return lastFinishedGestureID
        }
    }

    static func recordInstantGesture(id: String, switchGeneration: UInt64?) {
        queue.sync {
            lastFinishedGestureID = id
            lastFinishedSwitchGeneration = switchGeneration
        }
    }

    private static func scheduleFrame(id: UUID, frameIndex: Int) {
        guard let gesture = activeGesture, gesture.id == id else { return }

        let interval = SpaceHelper.linearGestureFrameInterval
        let intervalNanoseconds = UInt64(interval * 1_000_000_000)
        let durationNanoseconds = UInt64(gesture.targetDuration * 1_000_000_000)
        let endTime = gesture.stepStartTime.uptimeNanoseconds + durationNanoseconds
        let nominalOffset = min(Double(frameIndex) * interval, gesture.targetDuration)
        let nominalDeadline = gesture.stepStartTime.uptimeNanoseconds
            + UInt64(nominalOffset * 1_000_000_000)
        let earliestDeadline = gesture.lastProgressTime.uptimeNanoseconds + intervalNanoseconds
        // Skip missed ticks instead of posting catch-up events back-to-back.
        let deadline = DispatchTime(
            uptimeNanoseconds: min(max(nominalDeadline, earliestDeadline), endTime)
        )
        let workItem = DispatchWorkItem {
            guard var currentGesture = activeGesture, currentGesture.id == id else { return }

            let callbackTime = DispatchTime.now()
            let deadlineSlip = seconds(from: deadline, to: callbackTime)
            let elapsed = seconds(from: currentGesture.stepStartTime, to: callbackTime)
            // Derive progress from elapsed time so callback jitter does not alter velocity.
            let progress = SpaceHelper.linearGestureProgressPerSpace
                * min(elapsed / currentGesture.targetDuration, 1)
            let progressDelta = progress - currentGesture.progress
            guard SpaceHelper.postDockSwipe(
                phase: 2,
                directionRight: currentGesture.directionRight,
                progress: progress,
                velocity: 0
            ) else {
                cancelActiveGesture(reason: "failed to post changed phase")
                return
            }
            let eventTime = DispatchTime.now()
            let actualInterval = seconds(from: currentGesture.lastProgressTime, to: eventTime)
            currentGesture.progress = progress
            currentGesture.lastProgressTime = eventTime
            currentGesture.changedFrameCount += 1
            currentGesture.frameIntervalSum += actualInterval
            currentGesture.minFrameInterval = min(
                currentGesture.minFrameInterval ?? actualInterval,
                actualInterval
            )
            currentGesture.maxFrameInterval = max(currentGesture.maxFrameInterval, actualInterval)
            currentGesture.maxDeadlineSlip = max(currentGesture.maxDeadlineSlip, deadlineSlip)

            DiagnosticEventLog.shared.recordDuringCollection(
                subsystem: "SpaceGestureAnimation",
                level: "debug",
                "phase=changed id=\(id.uuidString) step=\(currentGesture.completedSteps + 1)/\(currentGesture.totalSteps) frame=\(frameIndex)/\(currentGesture.frameCount) progress=\(progress) delta=\(progressDelta) scheduledIntervalMs=\(milliseconds(SpaceHelper.linearGestureFrameInterval)) actualIntervalMs=\(milliseconds(actualInterval)) deadlineSlipMs=\(milliseconds(deadlineSlip))"
            )

            if progress < SpaceHelper.linearGestureProgressPerSpace {
                activeGesture = currentGesture
                scheduleFrame(id: id, frameIndex: frameIndex + 1)
                return
            }

            activeGesture = currentGesture
            let swipeStartTime = currentGesture.stepStartTime
            guard SpaceHelper.postDockSwipe(
                phase: 4,
                directionRight: currentGesture.directionRight,
                progress: SpaceHelper.dockSwipeMinimumProgress,
                velocity: currentGesture.commitVelocity
            ) else {
                cancelActiveGesture(reason: "failed to post ended phase")
                return
            }
            let endedAt = DispatchTime.now()
            let swipeDuration = seconds(from: swipeStartTime, to: endedAt)
            currentGesture.completedSteps += 1
            currentGesture.swipeInProgress = false
            currentGesture.lastEndedAt = endedAt
            currentGesture.swipeDurations.append(swipeDuration)
            activeGesture = currentGesture
            DiagnosticEventLog.shared.recordDuringCollection(
                subsystem: "SpaceGestureAnimation",
                level: "debug",
                "phase=ended id=\(id.uuidString) step=\(currentGesture.completedSteps)/\(currentGesture.totalSteps) finalProgress=\(currentGesture.progress) commitProgress=\(SpaceHelper.dockSwipeMinimumProgress) commitVelocity=\(currentGesture.commitVelocity) swipeDurationMs=\(milliseconds(swipeDuration))"
            )
            scheduleAfterSettle(id: id)
        }
        nextFrameWorkItem = workItem
        queue.asyncAfter(deadline: deadline, execute: workItem)
    }

    private static func postGestureBegan(id: UUID) -> Bool {
        guard var gesture = activeGesture, gesture.id == id else { return false }
        guard SpaceHelper.postDockSwipe(
            phase: 1,
            directionRight: gesture.directionRight,
            progress: SpaceHelper.dockSwipeMinimumProgress,
            velocity: 0
        ) else {
            return false
        }
        let eventTime = DispatchTime.now()
        gesture.swipeInProgress = true
        gesture.progress = 0
        gesture.stepStartTime = eventTime
        gesture.lastProgressTime = eventTime
        activeGesture = gesture
        DiagnosticEventLog.shared.recordDuringCollection(
            subsystem: "SpaceGestureAnimation",
            level: "debug",
            "phase=began id=\(id.uuidString) step=\(gesture.completedSteps + 1)/\(gesture.totalSteps) eventProgress=\(SpaceHelper.dockSwipeMinimumProgress) frameCount=\(gesture.frameCount)"
        )
        return true
    }

    private static func scheduleAfterSettle(id: UUID) {
        guard let gesture = activeGesture,
              gesture.id == id,
              let endedAt = gesture.lastEndedAt else { return }
        let deadline = endedAt + SpaceHelper.linearGestureSettleInterval
        let workItem = DispatchWorkItem {
            guard var currentGesture = activeGesture, currentGesture.id == id else { return }
            let settleDuration = seconds(from: endedAt, to: .now())
            currentGesture.settleDurations.append(settleDuration)
            currentGesture.lastEndedAt = nil
            activeGesture = currentGesture
            DiagnosticEventLog.shared.recordDuringCollection(
                subsystem: "SpaceGestureAnimation",
                level: "debug",
                "phase=settled id=\(id.uuidString) step=\(currentGesture.completedSteps)/\(currentGesture.totalSteps) scheduledSettleMs=\(milliseconds(SpaceHelper.linearGestureSettleInterval)) actualSettleMs=\(milliseconds(settleDuration))"
            )

            guard currentGesture.completedSteps < currentGesture.totalSteps else {
                finishActiveGesture(outcome: "completed")
                return
            }
            guard postGestureBegan(id: id) else {
                cancelActiveGesture(reason: "failed to post began phase")
                return
            }
            scheduleFrame(id: id, frameIndex: 1)
        }
        nextFrameWorkItem = workItem
        queue.asyncAfter(deadline: deadline, execute: workItem)
    }

    private static func cancelActiveGesture(reason: String) {
        nextFrameWorkItem?.cancel()
        nextFrameWorkItem = nil

        guard var gesture = activeGesture else { return }
        if gesture.swipeInProgress {
            _ = SpaceHelper.postDockSwipe(
                phase: 8,
                directionRight: gesture.directionRight,
                progress: gesture.progress,
                velocity: 0
            )
            DiagnosticEventLog.shared.recordDuringCollection(
                subsystem: "SpaceGestureAnimation",
                level: "debug",
                "phase=cancelled id=\(gesture.id.uuidString) step=\(gesture.completedSteps + 1)/\(gesture.totalSteps) progress=\(gesture.progress) reason=\(reason)"
            )
        } else if let endedAt = gesture.lastEndedAt {
            let interruptedSettle = seconds(from: endedAt, to: .now())
            gesture.settleDurations.append(interruptedSettle)
            activeGesture = gesture
            DiagnosticEventLog.shared.recordDuringCollection(
                subsystem: "SpaceGestureAnimation",
                level: "debug",
                "phase=settle-interrupted id=\(gesture.id.uuidString) step=\(gesture.completedSteps)/\(gesture.totalSteps) actualSettleMs=\(milliseconds(interruptedSettle)) reason=\(reason)"
            )
        }
        DiagnosticEventLog.shared.record(
            subsystem: "SpaceGestureAnimation",
            level: "warning",
            "phase=cancel id=\(gesture.id.uuidString) reason=\(reason) completedSteps=\(gesture.completedSteps)/\(gesture.totalSteps) currentProgress=\(gesture.progress) swipeInProgress=\(gesture.swipeInProgress)"
        )
        finishActiveGesture(outcome: "cancelled: \(reason)")
    }

    private static func finishActiveGesture(outcome: String) {
        nextFrameWorkItem?.cancel()
        nextFrameWorkItem = nil

        guard let gesture = activeGesture else { return }
        let finishedAt = DispatchTime.now()
        let summary = "id=\(gesture.id.uuidString) generation=\(gesture.switchGeneration.map(String.init) ?? "nil") outcome=\(outcome) source=\(gesture.sourceSpaceID ?? "nil") target=\(gesture.targetSpaceID ?? "nil") display=\(gesture.targetDisplayID) layout=\(gesture.gestureLayout) direction=\(gesture.directionRight ? "right" : "left") steps=\(gesture.completedSteps)/\(gesture.totalSteps) targetDurationPerSpace=\(gesture.targetDuration) framesPerSwipe=\(gesture.frameCount) progressPerFrame=\(gesture.progressPerFrame) commitVelocity=\(gesture.commitVelocity) elapsedMs=\(milliseconds(seconds(from: gesture.startedAt, to: finishedAt))) changedFrameCount=\(gesture.changedFrameCount) frameIntervalMs=\(frameIntervalStatistics(gesture)) swipeDurationMs=\(durationStatistics(gesture.swipeDurations)) settleDurationMs=\(durationStatistics(gesture.settleDurations)) maximumDeadlineSlipMs=\(milliseconds(gesture.maxDeadlineSlip))"
        lastAnimationSummary = summary
        lastFinishedGestureID = gesture.id.uuidString
        lastFinishedSwitchGeneration = gesture.switchGeneration
        activeGesture = nil
        if gesture.shouldRestoreMouse, let originalMouseLocation = gesture.originalMouseLocation {
            CGWarpMouseCursorPosition(originalMouseLocation)
        }
        DiagnosticEventLog.shared.record(
            subsystem: "SpaceGestureAnimation",
            level: outcome == "completed" ? "info" : "warning",
            "phase=finish \(summary)"
        )
    }

    private static func seconds(from start: DispatchTime, to end: DispatchTime) -> TimeInterval {
        TimeInterval(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
    }

    private static func milliseconds(_ duration: TimeInterval) -> String {
        String(format: "%.2f", duration * 1_000)
    }

    private static func durationStatistics(_ values: [TimeInterval]) -> String {
        guard let minimum = values.min(), let maximum = values.max() else { return "n/a" }
        let average = values.reduce(0, +) / Double(values.count)
        return "min=\(milliseconds(minimum)),avg=\(milliseconds(average)),max=\(milliseconds(maximum))"
    }

    private static func frameIntervalStatistics(_ gesture: Gesture) -> String {
        guard let minimum = gesture.minFrameInterval, gesture.changedFrameCount > 0 else {
            return "n/a"
        }
        let average = gesture.frameIntervalSum / Double(gesture.changedFrameCount)
        return "min=\(milliseconds(minimum)),avg=\(milliseconds(average)),max=\(milliseconds(gesture.maxFrameInterval))"
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
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let usesModernDockSwipeProtocol = os.majorVersion >= 27
        let directionSign = directionRight ? 1.0 : -1.0
        let naturalScrolling = usesModernDockSwipeProtocol ? naturalScrollingEnabled() : true
        let progressSign: Double
        if usesModernDockSwipeProtocol {
            // Dock swipe signs on macOS 27 follow the trackpad's natural-scroll setting.
            progressSign = -directionSign * (naturalScrolling ? 1.0 : -1.0)
        } else {
            progressSign = directionSign
        }
        let progressMagnitude = progress ?? SpaceHelper.dockSwipeMinimumProgress
        let signedProgress = progressMagnitude * progressSign
        let signedVelocity = velocity * progressSign
        
        guard let ev = CGEvent(source: nil) else { return false }
        ev.setIntegerValueField(CGEventField(rawValue: 55)!, value: 30) // kCGSEventDockControl
        ev.setIntegerValueField(CGEventField(rawValue: 110)!, value: 23) // kIOHIDEventTypeDockSwipe
        ev.setIntegerValueField(CGEventField(rawValue: 132)!, value: Int64(phase)) // phase
        ev.setDoubleValueField(CGEventField(rawValue: 124)!, value: signedProgress)
        ev.setIntegerValueField(CGEventField(rawValue: 123)!, value: 1) // horizontal motion
        if usesModernDockSwipeProtocol {
            ev.setIntegerValueField(CGEventField(rawValue: 134)!, value: Int64(phase)) // phase alias
            ev.setDoubleValueField(CGEventField(rawValue: 138)!, value: 3.0) // gesture zoom delta Y
            ev.setDoubleValueField(CGEventField(rawValue: 169)!, value: Double(mach_absolute_time()))
            ev.setDoubleValueField(CGEventField(rawValue: 125)!, value: 0.1) // normalized gesture position X
            if phase == 4 {
                ev.setDoubleValueField(CGEventField(rawValue: 129)!, value: signedVelocity)
            }
        } else {
            ev.setDoubleValueField(CGEventField(rawValue: 129)!, value: signedVelocity)
            ev.setDoubleValueField(CGEventField(rawValue: 130)!, value: 0)
            ev.setIntegerValueField(CGEventField(rawValue: 115)!, value: directionRight ? 8 : 4) // swipe mask: right=8, left=4
        }
        
        var eventToPost = ev
        var companionEvent: CGEvent?
        if usesModernDockSwipeProtocol {
            guard let augmented = GestureAugmentor.augmentEvent(ev)?.takeRetainedValue() else {
                DiagnosticEventLog.shared.recordDuringCollection(
                    subsystem: "SpaceGestureAnimation",
                    level: "warning",
                    "eventPath=modern-augmentation-failed phase=\(phase) progress=\(signedProgress) velocity=\(signedVelocity)"
                )
                return false
            }
            guard let companion = CGEvent(source: nil) else {
                DiagnosticEventLog.shared.recordDuringCollection(
                    subsystem: "SpaceGestureAnimation",
                    level: "warning",
                    "eventPath=modern-companion-creation-failed phase=\(phase)"
                )
                return false
            }
            companion.setIntegerValueField(CGEventField(rawValue: 55)!, value: 29) // kCGSEventGesture
            eventToPost = augmented
            companionEvent = companion
        }

        if phase == 4 || phase == 8 {
            DiagnosticEventLog.shared.recordDuringCollection(
                subsystem: "SpaceGestureAnimation",
                level: "debug",
                "phase=\(phase == 4 ? "ended" : "cancelled") direction=\(directionRight ? "right" : "left") progress=\(signedProgress) commitVelocity=\(signedVelocity) naturalScrolling=\(naturalScrolling) modernProtocol=\(usesModernDockSwipeProtocol) os=\(os.majorVersion).\(os.minorVersion)"
            )
        }
        
        // Use cgSessionEventTap to match ISS.c and prevent HID acceleration/mishandling
        eventToPost.post(tap: .cgSessionEventTap)
        companionEvent?.post(tap: .cgSessionEventTap)
        return true
    }

    private static func naturalScrollingEnabled() -> Bool {
        guard let value = CFPreferencesCopyAppValue(
            "com.apple.swipescrolldirection" as CFString,
            kCFPreferencesAnyApplication
        ) as? NSNumber else {
            return true
        }
        return value.boolValue
    }
    
    static func performSpaceSwitchGesture(
        steps: Int,
        targetDisplayID: String,
        sourceSpaceID: String? = nil,
        targetSpaceID: String? = nil,
        switchGeneration: UInt64? = nil,
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
            let gestureID = UUID().uuidString
            SyntheticSpaceGestureStream.recordInstantGesture(
                id: gestureID,
                switchGeneration: switchGeneration
            )
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceGestureAnimation",
                level: "info",
                "phase=instant id=\(gestureID) generation=\(switchGeneration.map(String.init) ?? "nil") source=\(sourceSpaceID ?? "nil") target=\(targetSpaceID ?? "nil") display=\(targetDisplayID) steps=\(absSteps) direction=\(directionRight ? "right" : "left") forceInstant=\(forceInstant) configuredDuration=\(target)"
            )
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
            sourceSpaceID: sourceSpaceID,
            targetSpaceID: targetSpaceID,
            switchGeneration: switchGeneration,
            directionRight: directionRight,
            targetDuration: duration,
            targetDisplayID: targetDisplayID,
            gestureLayout: gestureLayout,
            warpLocation: warpLocation
        )
    }

    static var syntheticGestureAnimationInfo: String {
        SyntheticSpaceGestureStream.diagnosticInfo
    }

    static var syntheticGestureAnimationID: String? {
        SyntheticSpaceGestureStream.diagnosticGestureID(
            for: activeProgrammaticSwitchGeneration
        )
    }
}
