import AppKit
import CoreGraphics
import Foundation


extension SpaceHelper {

    static func scheduleSpaceSwitchLabelSuppression(generation: UInt64?) {
        // dragActiveWindow() posts this notification before it synthesizes the
        // mouse-down event. Repeating the notification from the switch path
        // makes every preview label perform another synchronous WindowServer
        // update while the window is being dragged.
        if isDragging {
            return
        }

        let suppress = {
            NotificationCenter.default.post(
                name: NSNotification.Name("SpaceSwitchRequested"),
                object: nil
            )
        }

        // Synthetic events must be posted before preview-window work. An
        // instant operation has no event to protect, so keep its existing
        // synchronous notification behavior.
        if generation == nil {
            suppress()
        } else {
            DispatchQueue.main.async(execute: suppress)
        }
    }

    static func scheduleActiveLabelPreparation(spaceID: String, generation: UInt64?) {
        // The active label is reconciled after the move arrives at its target
        // space. Preparing it here would add synchronous layout/binding work
        // to the drag initiation path, and is redundant with the pre-drag
        // preview suppression above.
        if isDragging {
            return
        }

        let prepare = {
            if let generation {
                guard let active = switchTransactionCoordinator.active,
                      isSwitching,
                      active.generation == generation,
                      active.request.spaceID == spaceID else {
                    return
                }
            }

            NotificationCenter.default.post(
                name: NSNotification.Name("SpaceSwitchTargetRequested"),
                object: nil,
                userInfo: ["spaceID": spaceID]
            )
        }

        // The synthetic gesture must reach WindowServer before the active
        // label performs its layout/binding work. Force-instant operations do
        // not have a gesture to protect, so preserve their immediate behavior.
        if generation == nil {
            prepare()
        } else {
            DispatchQueue.main.async(execute: prepare)
        }
    }

    static func markProgrammaticSwitchStarted(
        spaceID: String,
        generation: UInt64?,
        isManual: Bool,
        forceInstant: Bool,
        displayID: String,
        isFullscreen: Bool
    ) {
        lastProgrammaticSwitchTime = Date().timeIntervalSince1970
        lastProgrammaticTargetSpaceID = spaceID
        programmaticSwitchDisplayID = displayID
        nextProgrammaticSwitchRequestID += 1
        let requestID = nextProgrammaticSwitchRequestID
        lastProgrammaticSwitchRequestID = requestID

        let traceID = debugTraceID()
        debugTrace(
            traceID,
            "programmatic switch primitive emitted request=\(requestID), generation=\(generation.map(String.init) ?? "instant"), target=\(spaceID), display=\(displayID), forceInstant=\(forceInstant), live=\(debugFormatSpaceMap(getCurrentSpaceIDsByDisplay()))"
        )

        DiagnosticEventLog.shared.record(
            subsystem: "SpaceHelper",
            level: "info",
            "programmatic switch started: generation=\(generation.map(String.init) ?? "instant"), target=\(spaceID), display=\(displayID), fullscreen=\(isFullscreen)"
        )

        var startedUserInfo: [String: Any] = [
            "spaceID": spaceID,
            "isManual": isManual,
            "forceInstant": forceInstant,
            "displayID": displayID,
            "requestID": requestID
        ]
        if let generation {
            startedUserInfo["generation"] = generation
            scheduleProgrammaticSwitchTimeout(
                spaceID: spaceID,
                generation: generation
            )
        }
        NotificationCenter.default.post(
            name: NSNotification.Name("SpaceProgrammaticSwitchStarted"),
            object: nil,
            userInfo: startedUserInfo
        )
    }

    static func cancelPendingSwitchPromotion() {
        programmaticSwitchPromotionWorkItem?.cancel()
        programmaticSwitchPromotionWorkItem = nil
        programmaticSwitchPromotionRequest = nil
        programmaticSwitchPromotionGeneration = nil
    }

    static func cancelActiveProgrammaticSwitch(reason: String) {
        guard let active = switchTransactionCoordinator.active else {
            switchTransactionCoordinator.cancelActive(dropPending: true)
            isSwitching = false
            programmaticSwitchDestinationObserved = false
            programmaticSwitchNotificationObserved = false
            programmaticSwitchUsesExtendedSettle = false
            programmaticSwitchFastFollowUpRequested = false
            programmaticSwitchCompletionWorkItem?.cancel()
            programmaticSwitchCompletionWorkItem = nil
            programmaticSwitchTimeoutWorkItem?.cancel()
            programmaticSwitchTimeoutWorkItem = nil
            syntheticGestureRetryWorkItem?.cancel()
            syntheticGestureRetryWorkItem = nil
            cancelPendingSwitchPromotion()
            lastProgrammaticSwitchTime = 0
            lastProgrammaticTargetSpaceID = nil
            programmaticSwitchDisplayID = nil
            return
        }

        programmaticSwitchCompletionWorkItem?.cancel()
        programmaticSwitchCompletionWorkItem = nil
        programmaticSwitchTimeoutWorkItem?.cancel()
        programmaticSwitchTimeoutWorkItem = nil
        syntheticGestureRetryWorkItem?.cancel()
        syntheticGestureRetryWorkItem = nil
        cancelPendingSwitchPromotion()
        switchTransactionCoordinator.cancelActive(dropPending: true)
        isSwitching = false
        programmaticSwitchDestinationObserved = false
        programmaticSwitchNotificationObserved = false
        programmaticSwitchUsesExtendedSettle = false
        programmaticSwitchFastFollowUpRequested = false
        lastProgrammaticSwitchTime = 0
        lastProgrammaticTargetSpaceID = nil
        programmaticSwitchDisplayID = nil

        DiagnosticEventLog.shared.record(
            subsystem: "SpaceHelper",
            level: "warning",
            "programmatic switch canceled: generation=\(active.generation), target=\(active.request.spaceID), reason=\(reason)"
        )
    }

}
