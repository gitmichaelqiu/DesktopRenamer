import AppKit
import CoreGraphics
import Foundation
import SwiftUI

@_silgen_name("_CGSDefaultConnection") func _CGSDefaultConnection() -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces") func CGSCopyManagedDisplaySpaces(_ cid: Int32)
    -> CFArray?
@_silgen_name("CGSCopyActiveMenuBarDisplayIdentifier")
func CGSCopyActiveMenuBarDisplayIdentifier(_ cid: Int32) -> CFString?
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: inout CGWindowID) -> Int32

@_silgen_name("CGSCopySpacesForWindows")
func CGSCopySpacesForWindows(_ cid: Int32, _ mask: Int32, _ windows: CFArray) -> CFArray?

@_silgen_name("CGSAddWindowsToSpaces")
func CGSAddWindowsToSpaces(_ cid: Int32, _ windows: CFArray, _ spaces: CFArray)

@_silgen_name("CGSRemoveWindowsFromSpaces")
func CGSRemoveWindowsFromSpaces(_ cid: Int32, _ windows: CFArray, _ spaces: CFArray)

@_silgen_name("CGSOrderWindow")
func CGSOrderWindow(_ cid: Int32, _ windowID: UInt32, _ op: Int32, _ relativeToWindowID: UInt32) -> Int32

class SpaceHelper {

    static var onSpaceChange: ((String, Bool, Int, String) -> Void)?
    static var globalEventMonitor: Any?
    static var localEventMonitor: Any?

    // Tokens for block-based notification observers (required for proper cleanup).
    static var spaceChangeObserver: NSObjectProtocol?
    static var appActivationObserver: NSObjectProtocol?
    // Only the most recent delayed WindowServer read may publish a space
    // change. Dock activation and mouse events can otherwise queue several
    // reads whose callbacks arrive after a newer transition has started.
    static var spaceDetectionGeneration = 0

    // Tracks switching state to prevent recursion during transitions.
    static var isSwitching = false
    static var lastProgrammaticSwitchTime: TimeInterval = 0
    static var lastProgrammaticTargetSpaceID: String? = nil
    static var lastProgrammaticSwitchUsedSLS = false
    // A WindowServer space read can reach SpaceManager before macOS delivers
    // the active-space notification. Keep the programmatic transition open
    // until both signals have arrived, so label restoration cannot use the
    // first destination snapshot as proof that the animation has finished.
    static var programmaticSwitchDestinationObserved = false
    static var programmaticSwitchNotificationObserved = false
    static var programmaticSwitchCompletionWorkItem: DispatchWorkItem?
    static var programmaticSwitchTimeoutWorkItem: DispatchWorkItem?
    static var fullscreenGestureRetryWorkItem: DispatchWorkItem?
    static var programmaticSwitchPromotionWorkItem: DispatchWorkItem?
    static var programmaticSwitchPromotionRequest: SpaceSwitchTransactionCoordinator.Request?
    static var programmaticSwitchPromotionGeneration: UInt64?
    // All transaction coordinator mutations are performed on the main queue,
    // alongside the WindowServer and AppKit callbacks that consume them.
    static var switchTransactionCoordinator = SpaceSwitchTransactionCoordinator()

    static var activeProgrammaticSwitchGeneration: UInt64? {
        switchTransactionCoordinator.active?.generation
    }

    static var activeProgrammaticSwitchTargetSpaceID: String? {
        switchTransactionCoordinator.active?.request.spaceID
    }

    static var pendingProgrammaticSwitchTargetSpaceID: String? {
        switchTransactionCoordinator.pending?.spaceID
            ?? programmaticSwitchPromotionRequest?.spaceID
    }

    /// Current transaction state for diagnostic reports. The generation makes
    /// stale completion and retry callbacks distinguishable from a newer
    /// transition even when they target the same ManagedSpaceID.
    static var programmaticSwitchStateInfo: String {
        let activeGeneration = activeProgrammaticSwitchGeneration.map(String.init) ?? "nil"
        let activeTarget = activeProgrammaticSwitchTargetSpaceID ?? "nil"
        let pendingTarget = pendingProgrammaticSwitchTargetSpaceID ?? "nil"
        let promotionGeneration = programmaticSwitchPromotionGeneration.map(String.init) ?? "nil"
        let promotionTarget = programmaticSwitchPromotionRequest?.spaceID ?? "nil"
        let pendingRequest = switchTransactionCoordinator.pending
            ?? programmaticSwitchPromotionRequest
        let pendingManual = pendingRequest.map {
            String($0.isManual)
        } ?? "nil"
        return """
          isSwitching: \(isSwitching)
          activeGeneration: \(activeGeneration)
          activeTargetSpaceID: \(activeTarget)
          pendingTargetSpaceID: \(pendingTarget)
          pendingIsManual: \(pendingManual)
          promotionGeneration: \(promotionGeneration)
          promotionTargetSpaceID: \(promotionTarget)
          destinationObserved: \(programmaticSwitchDestinationObserved)
          notificationObserved: \(programmaticSwitchNotificationObserved)
        """
    }
    
    // Session state for active dragging operations.
    static var originalMousePoint: CGPoint? = nil
    static var restorationTask: DispatchWorkItem? = nil
    static var pendingFocusTask: DispatchWorkItem? = nil
    static var pendingMoveCount = 0
    static var isInstantDrag = false
    static var targetSpaceID: String? = nil
    static var draggedWindowID: Int? = nil
    static var draggedWindowPID: Int32? = nil
    static var draggedWindowBundleID: String? = nil
    static var draggedWindowAppName: String? = nil
    static var draggedWindowOriginalFrame: CGRect? = nil
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
    static var gestureTimingStart: TimeInterval = 0
    static var gestureTimingDisplayID: String = ""

    static let calibrationKey = "GestureManager.CachedCalibrations"
    static let targetDurationKey = "GestureManager.SwitchDuration"
    static let defaultTargetDuration: TimeInterval = 0.30
    static let minMultiplier: Double = 0.1
    static let maxMultiplier: Double = 10.0

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
    static var displayCalibrations: [String: DisplayCalibration] = {
        guard let data = UserDefaults.standard.data(forKey: calibrationKey),
              let dict = try? JSONDecoder().decode([String: DisplayCalibration].self, from: data)
        else { return [:] }
        return dict
    }()

    // Phase 1: 3 samples at velocity 52. Phase 2: 3 samples at velocity 104.
    static var phase1Samples: [String: [TimeInterval]] = [:]
    static var phase2Samples: [String: [TimeInterval]] = [:]
    static let phaseSamplesNeeded = 3
    static let phase1Velocity: Double = 52.0
    static let phase2Velocity: Double = 104.0

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
    static let minActiveWindowWidth: CGFloat = 100
    static let minActiveWindowHeight: CGFloat = 100
}
