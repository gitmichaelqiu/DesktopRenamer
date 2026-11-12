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

    #if DEBUG
    private static var debugTraceSequence: UInt64 = 0

    /// Monotonic IDs make interleaved WindowServer, monitor, and label output
    /// reconstructable from the Xcode console without changing runtime state.
    static func debugTraceID() -> UInt64 {
        debugTraceSequence += 1
        return debugTraceSequence
    }

    static func debugTrace(_ id: UInt64, _ message: @autoclosure () -> String) {
        let queue = Thread.isMainThread ? "main" : "background"
        let trace = "SpaceTrace[\(id)][\(queue)] \(message())"
        DiagnosticEventLog.shared.recordDuringCollection(subsystem: "SpaceTrace", trace)
        print(trace)
    }
    #else
    static func debugTraceID() -> UInt64 { 0 }

    static func debugTrace(_ id: UInt64, _ message: @autoclosure () -> String) {
        let queue = Thread.isMainThread ? "main" : "background"
        DiagnosticEventLog.shared.recordDuringCollection(
            subsystem: "SpaceTrace",
            "SpaceTrace[\(id)][\(queue)] \(message())"
        )
    }
    #endif

    static func debugFormatSpaceMap(_ spacesByDisplay: [String: String]) -> String {
        guard !spacesByDisplay.isEmpty else { return "{}" }
        return "{"
            + spacesByDisplay.keys.sorted().map { "\($0)=\(spacesByDisplay[$0] ?? "nil")" }
                .joined(separator: ", ")
            + "}"
    }

    static var onSpaceChange: ((String, Bool, Int, String) -> Void)?
    static var onAuthoritativeSpaceChange: (([String: String]) -> Void)?
    static var globalEventMonitor: Any?
    static var localEventMonitor: Any?

    // Tokens for block-based notification observers (required for proper cleanup).
    static var spaceChangeObserver: NSObjectProtocol?
    static var appActivationObserver: NSObjectProtocol?
    // Only the most recent delayed WindowServer read may publish a space
    // change. Dock activation and mouse events can otherwise queue several
    // reads whose callbacks arrive after a newer transition has started.
    static var spaceDetectionGeneration = 0
    // The raw WindowServer scan is relatively expensive because it also walks
    // the on-screen window list. Keep only the newest scheduled scan so a
    // burst of activation or mouse events cannot occupy the main queue after
    // a gesture has already begun.
    static let rawSpaceUUIDStateLock = NSLock()
    static var rawSpaceUUIDWorkItem: DispatchWorkItem?
    static var rawSpaceUUIDGeneration = 0

    // Tracks switching state to prevent recursion during transitions.
    static var isSwitching = false
    static var lastProgrammaticSwitchTime: TimeInterval = 0
    static var lastProgrammaticTargetSpaceID: String? = nil
    static var programmaticSwitchDisplayID: String?
    // Unlike the transaction generation, this identity also covers requests
    // that use an instant primitive without entering the serialized
    // transaction coordinator. It lets SpaceManager discard delayed start
    // notifications from an older request after a rapid sequence of
    // selections.
    static var nextProgrammaticSwitchRequestID: UInt64 = 0
    static var lastProgrammaticSwitchRequestID: UInt64?
    // Window moves intentionally change the active space. Keep this separate
    // from the short-lived mouse-drag session because reconciliation can run
    // after the synthetic mouse button has already been released.
    static var pendingWindowMoveTargetSpaceID: String?
    static var pendingWindowMoveIntentTime: TimeInterval = 0
    // WindowServer state is the authoritative completion signal. The
    // active-space notification is useful corroboration, but it is delivered
    // through a lossy XPC path and can be absent even after the destination is
    // current. The generation-scoped settle verification below prevents one
    // early snapshot from completing the transition by itself.
    static var programmaticSwitchDestinationObserved = false
    static var programmaticSwitchNotificationObserved = false
    static var programmaticSwitchUsesExtendedSettle = false
    static var programmaticSwitchFastFollowUpRequested = false
    static var programmaticSwitchCompletionWorkItem: DispatchWorkItem?
    static var programmaticSwitchTimeoutWorkItem: DispatchWorkItem?
    static var syntheticGestureRetryWorkItem: DispatchWorkItem?
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

    // `isSwitching` becomes false for the short settle interval before a
    // coalesced request is promoted. Gesture requests must not run in that
    // gap or they can race the promotion and discard the latest destination.
    static var isProgrammaticSwitchPromotionPending: Bool {
        programmaticSwitchPromotionRequest != nil
            || programmaticSwitchPromotionWorkItem != nil
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
    static var pendingMoveCount = 0
    static var isInstantDrag = false
    static var targetSpaceID: String? = nil
    static var draggedWindowID: Int? = nil
    static var draggedWindowPID: Int32? = nil
    static var draggedWindowBundleID: String? = nil
    static var draggedWindowAppName: String? = nil
    static var draggedWindowOriginalFrame: CGRect? = nil
    static var draggedWindowOriginalSpaceID: String? = nil
    static var isDragging: Bool { originalMousePoint != nil }

    static func markWindowMoveIntent(to spaceID: String) {
        pendingWindowMoveTargetSpaceID = spaceID
        pendingWindowMoveIntentTime = Date().timeIntervalSince1970
    }

    static func consumeWindowMoveIntent(for spaceID: String) -> Bool {
        let age = Date().timeIntervalSince1970 - pendingWindowMoveIntentTime
        guard pendingWindowMoveTargetSpaceID == spaceID, age < 2.5 else {
            if age >= 2.5 {
                pendingWindowMoveTargetSpaceID = nil
                pendingWindowMoveIntentTime = 0
            }
            return false
        }
        pendingWindowMoveTargetSpaceID = nil
        pendingWindowMoveIntentTime = 0
        return true
    }

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

    // Synthetic Space swipes use evenly spaced progress updates so each
    // neighboring Space takes the same configured amount of time. End at the
    // adjacent Space; values beyond one Space over-travel and can make Dock
    // rebound while it settles on the destination.
    static let linearGestureFrameInterval: TimeInterval = 0.008
    static let linearGestureProgressPerSpace = 1.0
    static let linearGestureSettleInterval: TimeInterval = 0.20
    static let targetDurationKey = "GestureManager.SwitchDuration"
    static let defaultTargetDuration: TimeInterval = 0.30

    /// The user's target switch duration — 0 means instant mode.
    static var targetDuration: TimeInterval {
        guard UserDefaults.standard.object(forKey: targetDurationKey) != nil else {
            return defaultTargetDuration
        }
        return UserDefaults.standard.double(forKey: targetDurationKey)
    }

    // Minimum width and height for a window to be considered a regular app window in getActiveWindowInfo (filtering out small system utilities/status items).
    static let minActiveWindowWidth: CGFloat = 100
    static let minActiveWindowHeight: CGFloat = 100
}
