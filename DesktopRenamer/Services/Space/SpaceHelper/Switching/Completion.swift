import AppKit
import CoreGraphics
import Foundation


extension SpaceHelper {

    static func scheduleProgrammaticSwitchTimeout(spaceID: String, generation: UInt64) {
        let workItem = DispatchWorkItem {
            guard let active = switchTransactionCoordinator.active,
                  active.generation == generation,
                  active.request.spaceID == spaceID else {
                return
            }
            programmaticSwitchTimeoutWorkItem = nil
            finishProgrammaticSwitch(
                at: spaceID,
                generation: generation,
                reason: .timedOut
            )
        }
        programmaticSwitchTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: workItem)
    }

    /// Records that SpaceManager has read the requested destination from live
    /// WindowServer state. NSWorkspace's active-space notification can be
    /// dropped when its XPC session resets, so a stable WindowServer result is
    /// sufficient after the normal settle verification.
    static func markProgrammaticSwitchComplete(at spaceID: String) {
        guard let active = switchTransactionCoordinator.active,
              isSwitching,
              active.request.spaceID == spaceID else { return }
        let liveSpaceMap = getCurrentSpaceIDsByDisplay()
        let isCurrentAndVisible = isSpaceCurrentAndVisible(spaceID)
        let traceID = debugTraceID()
        debugTrace(
            traceID,
            "destination observation candidate target=\(spaceID), generation=\(active.generation), live=\(debugFormatSpaceMap(liveSpaceMap)), currentAndVisible=\(isCurrentAndVisible), notificationObserved=\(programmaticSwitchNotificationObserved)"
        )
        guard isCurrentAndVisible else {
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceHelper",
                level: "info",
                "programmatic destination is not current and visible yet at space \(spaceID); waiting for a consistent WindowServer read"
            )
            return
        }
        programmaticSwitchDestinationObserved = true
        debugTrace(traceID, "destination observation accepted target=\(spaceID)")
        if !programmaticSwitchNotificationObserved {
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceHelper",
                level: "info",
                "programmatic destination observed at space \(spaceID) without active-space notification; using WindowServer settle verification"
            )
        }

        finishProgrammaticSwitch(at: spaceID, generation: active.generation)
    }

    /// Records the completion signal emitted by NSWorkspace when the active
    /// space changes. SpaceManager may have observed the destination first, so
    /// either ordering is accepted.
    static func noteActiveSpaceDidChange(_ currentSpaceIDsByDisplay: [String: String]) {
        let traceID = debugTraceID()
        debugTrace(
            traceID,
            "noteActiveSpaceDidChange snapshot=\(debugFormatSpaceMap(currentSpaceIDsByDisplay)), switching=\(isSwitching), expectedDisplay=\(programmaticSwitchDisplayID ?? "nil"), expectedTarget=\(activeProgrammaticSwitchTargetSpaceID ?? "nil"), destinationObserved=\(programmaticSwitchDestinationObserved)"
        )
        guard let active = switchTransactionCoordinator.active, isSwitching else { return }
        guard let displayID = programmaticSwitchDisplayID,
              currentSpaceIDsByDisplay[displayID] == active.request.spaceID else {
            debugTrace(traceID, "active-space notification decision=ignored-not-current-target")
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceHelper",
                level: "info",
                "Ignoring active-space notification for a different Space: display=\(programmaticSwitchDisplayID ?? "nil"), observed=\(programmaticSwitchDisplayID.flatMap { currentSpaceIDsByDisplay[$0] } ?? "nil"), target=\(active.request.spaceID)"
            )
            return
        }
        programmaticSwitchNotificationObserved = true
        debugTrace(traceID, "active-space notification matched target=\(active.request.spaceID)")
        guard programmaticSwitchDestinationObserved else { return }

        finishProgrammaticSwitch(at: active.request.spaceID, generation: active.generation)
    }

    /// Releases a confirmed regular-desktop transaction promptly when a new
    /// physical swipe is already waiting. Without this signal, the gesture
    /// gate accumulates inputs for the full visual settle interval and later
    /// executes them out of phase with the user's current gesture.
    static func requestFastFollowUpSwitch() {
        guard let active = switchTransactionCoordinator.active,
              isSwitching,
              !programmaticSwitchUsesExtendedSettle else {
            return
        }

        programmaticSwitchFastFollowUpRequested = true
        guard programmaticSwitchDestinationObserved else { return }

        programmaticSwitchCompletionWorkItem?.cancel()
        programmaticSwitchCompletionWorkItem = nil
        DiagnosticEventLog.shared.record(
            subsystem: "SpaceHelper",
            level: "info",
            "accelerating confirmed switch for waiting gesture: generation=\(active.generation), target=\(active.request.spaceID)"
        )
        finishProgrammaticSwitch(
            at: active.request.spaceID,
            generation: active.generation
        )
    }

    private static func finishProgrammaticSwitch(at spaceID: String, generation: UInt64) {
        guard programmaticSwitchCompletionWorkItem == nil else { return }

        // The first matching WindowServer read can arrive before the visual
        // swipe has finished. Keep the transition open for a short settling
        // interval, then verify the authoritative live state again before
        // releasing queued requests and restoring labels. Regular desktop
        // switches do not need the full animation duration here because the
        // destination was already independently observed above.
        let settleDelay: TimeInterval =
            programmaticSwitchFastFollowUpRequested && !programmaticSwitchUsesExtendedSettle
            ? 0.08
            : programmaticSwitchUsesExtendedSettle
                ? 0.35
                : max(0.08, min(0.18, targetDuration * 0.4))
        let workItem = DispatchWorkItem {
            guard let active = switchTransactionCoordinator.active,
                  isSwitching,
                  active.generation == generation,
                  active.request.spaceID == spaceID else {
                return
            }
            programmaticSwitchCompletionWorkItem = nil

            guard isSpaceCurrentAndVisible(spaceID) else {
                DiagnosticEventLog.shared.record(
                    subsystem: "SpaceHelper",
                    level: "warning",
                    "programmatic switch failed settle verification: generation=\(generation), target=\(spaceID); retaining transaction"
                )
                scheduleProgrammaticSwitchCompletionVerification(
                    spaceID: spaceID,
                    generation: generation,
                    delay: 0.2
                )
                return
            }

            finishProgrammaticSwitch(
                at: spaceID,
                generation: generation,
                reason: .confirmed
            )
        }
        programmaticSwitchCompletionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay, execute: workItem)
    }

    private static func scheduleProgrammaticSwitchCompletionVerification(
        spaceID: String,
        generation: UInt64,
        delay: TimeInterval
    ) {
        let workItem = DispatchWorkItem {
            guard let active = switchTransactionCoordinator.active,
                  isSwitching,
                  active.generation == generation,
                  active.request.spaceID == spaceID else {
                return
            }
            programmaticSwitchCompletionWorkItem = nil
            finishProgrammaticSwitch(at: spaceID, generation: generation)
        }
        programmaticSwitchCompletionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private static func finishProgrammaticSwitch(
        at spaceID: String,
        generation: UInt64,
        reason: ProgrammaticSwitchEndReason
    ) {
        guard let active = switchTransactionCoordinator.active,
              active.generation == generation,
              active.request.spaceID == spaceID else {
            return
        }

        programmaticSwitchCompletionWorkItem?.cancel()
        programmaticSwitchCompletionWorkItem = nil
        programmaticSwitchTimeoutWorkItem?.cancel()
        programmaticSwitchTimeoutWorkItem = nil
        syntheticGestureRetryWorkItem?.cancel()
        syntheticGestureRetryWorkItem = nil

        let pendingRequest = switchTransactionCoordinator.endActive()
        let displayID = programmaticSwitchDisplayID
        let traceID = debugTraceID()
        debugTrace(
            traceID,
            "finishProgrammaticSwitch reason=\(reason), generation=\(generation), target=\(spaceID), display=\(displayID ?? "nil"), live=\(debugFormatSpaceMap(getCurrentSpaceIDsByDisplay())), pending=\(pendingRequest?.spaceID ?? "nil")"
        )
        isSwitching = false
        programmaticSwitchDestinationObserved = false
        programmaticSwitchNotificationObserved = false
        programmaticSwitchUsesExtendedSettle = false
        programmaticSwitchFastFollowUpRequested = false
        programmaticSwitchDisplayID = nil

        switch reason {
        case .confirmed:
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceHelper",
                level: "info",
                "programmatic switch confirmed: generation=\(generation), target=\(spaceID)"
            )
            var completionUserInfo: [String: Any] = [
                "spaceID": spaceID,
                "generation": generation,
                "confirmed": true
            ]
            if let displayID {
                completionUserInfo["displayID"] = displayID
            }
            NotificationCenter.default.post(
                name: NSNotification.Name("SpaceProgrammaticSwitchFinished"),
                object: nil,
                userInfo: completionUserInfo
            )
            var settledUserInfo: [String: Any] = [
                "spaceID": spaceID,
                "generation": generation
            ]
            if let displayID {
                settledUserInfo["displayID"] = displayID
            }
            NotificationCenter.default.post(
                name: NSNotification.Name("SpaceProgrammaticSwitchSettled"),
                object: nil,
                userInfo: settledUserInfo
            )
        case .timedOut:
            // The target was not confirmed. Do not leave its timestamp and ID
            // available to classify a later external switch as ours.
            lastProgrammaticSwitchTime = 0
            lastProgrammaticTargetSpaceID = nil
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceHelper",
                level: "warning",
                "programmatic switch timed out: generation=\(generation), target=\(spaceID)"
            )
            var timeoutUserInfo: [String: Any] = [
                "spaceID": spaceID,
                "generation": generation,
                "confirmed": false
            ]
            if let displayID {
                timeoutUserInfo["displayID"] = displayID
            }
            NotificationCenter.default.post(
                name: NSNotification.Name("SpaceProgrammaticSwitchFinished"),
                object: nil,
                userInfo: timeoutUserInfo
            )
        }

        guard let pendingRequest else { return }

        // Give the completion notification and label manager one main-queue
        // turn before starting the latest pending destination. This preserves
        // the existing settle boundary without allowing previews to reopen
        // between two serialized requests.
        programmaticSwitchPromotionRequest = pendingRequest
        programmaticSwitchPromotionGeneration = generation
        let promotionWorkItem = DispatchWorkItem {
            guard programmaticSwitchPromotionGeneration == generation,
                  programmaticSwitchPromotionRequest == pendingRequest else {
                return
            }
            programmaticSwitchPromotionWorkItem = nil
            programmaticSwitchPromotionRequest = nil
            programmaticSwitchPromotionGeneration = nil

            guard switchTransactionCoordinator.active == nil else {
                DiagnosticEventLog.shared.record(
                    subsystem: "SpaceHelper",
                    level: "info",
                    "pending switch superseded before promotion: target=\(pendingRequest.spaceID)"
                )
                return
            }
            promotePendingSwitch(pendingRequest)
        }
        programmaticSwitchPromotionWorkItem = promotionWorkItem
        DispatchQueue.main.async(execute: promotionWorkItem)
    }

    private static func promotePendingSwitch(_ request: SpaceSwitchTransactionCoordinator.Request) {
        guard let context = makeSpaceSwitchContext(for: request.spaceID) else {
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceHelper",
                level: "warning",
                "pending switch discarded because target is unavailable: target=\(request.spaceID)"
            )
            return
        }

        if context.liveCurrentSpaceID == request.spaceID || context.currentUUID == request.spaceID {
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceHelper",
                level: "info",
                "pending switch discarded because target is already current: target=\(request.spaceID)"
            )
            return
        }

        DiagnosticEventLog.shared.record(
            subsystem: "SpaceHelper",
            level: "info",
            "promoting pending switch: target=\(request.spaceID), isManual=\(request.isManual)"
        )
        _ = startSpaceSwitch(context, forceInstant: false, isManual: request.isManual)
    }

}
