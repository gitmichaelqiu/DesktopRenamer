import AppKit
import CoreGraphics
import Foundation

extension SpaceHelper {

    struct SpaceSwitchContext {
        let spaces: [DesktopSpace]
        let currentUUID: String
        let targetSpace: DesktopSpace
        let liveCurrentSpaceID: String?
        let targetNum: Int?
        let targetGlobalNum: Int?
        let targetIsFullscreen: Bool
        let currentSpaceIsFullscreen: Bool
        let steps: Int?
    }

    enum ProgrammaticSwitchEndReason {
        case confirmed
        case timedOut
    }

    static func isSpaceCurrentAndVisible(_ spaceID: String) -> Bool {
        guard let state = getSystemState(),
              let targetSpace = state.spaces.first(where: { $0.id == spaceID }),
              getCurrentSpaceID(for: targetSpace.displayID) == spaceID else {
            return false
        }
        return getVisibleSystemSpaceIDs().contains(spaceID)
    }

    // Core space switching implementation. Non-instant requests are serialized
    // so a gesture arriving while WindowServer is settling cannot be lost or
    // overwrite the active transaction's identity.
    @discardableResult
    static func switchToSpace(
        _ spaceID: String,
        forceInstant: Bool = false,
        isManual: Bool = false
    ) -> SpaceSwitchRequestDisposition {
        let traceID = debugTraceID()
        debugTrace(
            traceID,
            "switch request target=\(spaceID), forceInstant=\(forceInstant), manual=\(isManual), live=\(debugFormatSpaceMap(getCurrentSpaceIDsByDisplay())), active=\(activeProgrammaticSwitchTargetSpaceID ?? "nil")/\(activeProgrammaticSwitchGeneration.map(String.init) ?? "nil"), pending=\(pendingProgrammaticSwitchTargetSpaceID ?? "nil")"
        )
        DiagnosticEventLog.shared.record(
            subsystem: "SpaceHelper",
            level: "info",
            "switchToSpace(\(spaceID), forceInstant=\(forceInstant), isManual=\(isManual))"
        )

        if programmaticSwitchPromotionRequest != nil {
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceHelper",
                level: "info",
                "pending switch promotion superseded by new request: target=\(spaceID)"
            )
            cancelPendingSwitchPromotion()
        }

        // An immediate operation is outside the serialized queue. Stop any
        // in-flight non-instant transaction before checking whether this
        // request is already current, so a stale transaction cannot continue
        // after a forceInstant no-op.
        if forceInstant && (switchTransactionCoordinator.active != nil || isSwitching) {
            cancelActiveProgrammaticSwitch(reason: "forceInstant request")
        }

        // Queue before taking another WindowServer snapshot. During an active
        // fullscreen animation the requested space can briefly disappear from
        // CGS enumeration; promotion will validate it again after settling.
        if !forceInstant, switchTransactionCoordinator.active != nil {
            let update = switchTransactionCoordinator.enqueue(spaceID: spaceID, isManual: isManual)
            let updateDescription: String
            switch update {
            case .queued:
                updateDescription = "queued"
            case let .replaced(previous):
                updateDescription = "replaced pending \(previous.spaceID)"
            case .coalesced:
                updateDescription = "coalesced duplicate"
            case .cleared:
                updateDescription = "cleared pending destination"
            }
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceHelper",
                level: "info",
                "switch request \(updateDescription): generation=\(activeProgrammaticSwitchGeneration.map(String.init) ?? "nil"), target=\(spaceID), active=\(activeProgrammaticSwitchTargetSpaceID ?? "nil"), pending=\(pendingProgrammaticSwitchTargetSpaceID ?? "nil")"
            )
            return .queued
        }

        guard let context = makeSpaceSwitchContext(for: spaceID) else {
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceHelper",
                level: "warning",
                "switch request unavailable: target=\(spaceID)"
            )
            return .unavailable
        }

        if context.liveCurrentSpaceID == spaceID || context.currentUUID == spaceID {
            print("SpaceHelper: Already on target space \(spaceID). Stopping.")
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceHelper",
                level: "info",
                "switch request already current: target=\(spaceID)"
            )
            debugTrace(traceID, "switch request disposition=alreadyCurrent target=\(spaceID)")
            return .alreadyCurrent
        }

        let disposition = startSpaceSwitch(context, forceInstant: forceInstant, isManual: isManual)
        debugTrace(
            traceID,
            "switch request disposition=\(String(describing: disposition)), target=\(spaceID), liveAfterRequest=\(debugFormatSpaceMap(getCurrentSpaceIDsByDisplay()))"
        )
        return disposition
    }

    /// Resolves one adjacent space from a single managed-space snapshot. The
    /// gesture override uses this path so it does not first ask SpaceManager
    /// for the current space and then ask WindowServer for the same state again
    /// before emitting the synthetic gesture.
    @discardableResult
    static func switchToAdjacentSpace(
        direction: Int,
        onDisplayID requestedDisplayID: String? = nil,
        forceInstant: Bool = false,
        isManual: Bool = false
    ) -> SpaceSwitchRequestDisposition {
        guard direction != 0,
              let state = getSystemState(includeFullscreenAppMetadata: false) else {
            return .unavailable
        }

        let displayID = requestedDisplayID ?? state.displayID
        let liveCurrentSpaceID: String?
        if displayID == state.displayID {
            liveCurrentSpaceID = state.currentUUID
        } else {
            liveCurrentSpaceID = getCurrentSpaceID(for: displayID)
        }

        let displaySpaces = state.spaces
            .filter { $0.displayID == displayID }
            .sorted { $0.num < $1.num }

        guard let liveCurrentSpaceID,
              let currentIndex = displaySpaces.firstIndex(where: {
                  $0.id == liveCurrentSpaceID
              }) else {
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceHelper",
                level: "warning",
                "adjacent switch unavailable: display="
                    + displayID
                    + ", current="
                    + (liveCurrentSpaceID ?? "nil")
                    + ", direction="
                    + String(direction)
            )
            return .unavailable
        }

        let targetIndex = currentIndex + direction
        guard displaySpaces.indices.contains(targetIndex) else {
            return .unavailable
        }
        let targetSpace = displaySpaces[targetIndex]
        let context = makeSpaceSwitchContext(
            state: state,
            targetSpace: targetSpace,
            liveCurrentSpaceID: liveCurrentSpaceID
        )

        // If another request won the race after the snapshot, let the normal
        // absolute-target path coalesce this request instead of starting a
        // second primitive.
        if !forceInstant, switchTransactionCoordinator.active != nil {
            return switchToSpace(
                targetSpace.id,
                forceInstant: false,
                isManual: isManual
            )
        }

        if liveCurrentSpaceID == targetSpace.id {
            return .alreadyCurrent
        }
        return startSpaceSwitch(context, forceInstant: forceInstant, isManual: isManual)
    }

    static func makeSpaceSwitchContext(for spaceID: String) -> SpaceSwitchContext? {
        guard let state = getSystemState(),
              let targetSpace = state.spaces.first(where: { $0.id == spaceID }) else {
            return nil
        }

        let liveCurrentSpaceID = getCurrentSpaceID(for: targetSpace.displayID)
        if let liveCurrentSpaceID {
            print("SpaceHelper: switchToSpace check. Live ID: \(liveCurrentSpaceID), Target: \(spaceID)")
        }

        return makeSpaceSwitchContext(
            state: state,
            targetSpace: targetSpace,
            liveCurrentSpaceID: liveCurrentSpaceID
        )
    }

    private static func makeSpaceSwitchContext(
        state: (spaces: [DesktopSpace], currentUUID: String, displayID: String),
        targetSpace: DesktopSpace,
        liveCurrentSpaceID: String?
    ) -> SpaceSwitchContext {

        let currentSpaceIsFullscreen = state.spaces
            .first(where: { $0.id == liveCurrentSpaceID })?.isFullscreen ?? false
        let displaySpaces = state.spaces
            .filter { $0.displayID == targetSpace.displayID }
            .sorted { $0.num < $1.num }
        let steps: Int?
        if let liveCurrentSpaceID,
           let currentIndex = displaySpaces.firstIndex(where: { $0.id == liveCurrentSpaceID }),
           let targetIndex = displaySpaces.firstIndex(where: { $0.id == targetSpace.id }) {
            steps = targetIndex - currentIndex
        } else {
            steps = nil
        }

        return SpaceSwitchContext(
            spaces: state.spaces,
            currentUUID: state.currentUUID,
            targetSpace: targetSpace,
            liveCurrentSpaceID: liveCurrentSpaceID,
            targetNum: targetSpace.num,
            targetGlobalNum: targetSpace.globalShortcutNum,
            targetIsFullscreen: targetSpace.isFullscreen,
            currentSpaceIsFullscreen: currentSpaceIsFullscreen,
            steps: steps
        )
    }

    @discardableResult
    static func startSpaceSwitch(
        _ context: SpaceSwitchContext,
        forceInstant: Bool,
        isManual: Bool
    ) -> SpaceSwitchRequestDisposition {
        cancelPendingSwitchPromotion()

        let spaceID = context.targetSpace.id
        let displayID = context.targetSpace.displayID
        let traceID = debugTraceID()
        debugTrace(
            traceID,
            "startSpaceSwitch target=\(spaceID), display=\(displayID), from=\(context.liveCurrentSpaceID ?? "nil"), steps=\(context.steps.map(String.init) ?? "nil"), forceInstant=\(forceInstant), fullscreen=\(context.targetIsFullscreen)"
        )
        let generation: UInt64?

        if forceInstant {
            generation = nil
            isSwitching = false
            programmaticSwitchDestinationObserved = false
            programmaticSwitchNotificationObserved = false
            programmaticSwitchUsesExtendedSettle = false
            programmaticSwitchFastFollowUpRequested = false
        } else {
            let newGeneration = switchTransactionCoordinator.begin(
                spaceID: spaceID,
                isManual: isManual
            )
            generation = newGeneration
            isSwitching = true
            programmaticSwitchDestinationObserved = false
            programmaticSwitchNotificationObserved = false
            programmaticSwitchUsesExtendedSettle =
                context.targetIsFullscreen || context.currentSpaceIsFullscreen
            programmaticSwitchFastFollowUpRequested = false
            programmaticSwitchCompletionWorkItem?.cancel()
            programmaticSwitchCompletionWorkItem = nil
            programmaticSwitchTimeoutWorkItem?.cancel()
            programmaticSwitchTimeoutWorkItem = nil
            syntheticGestureRetryWorkItem?.cancel()
            syntheticGestureRetryWorkItem = nil
        }

        // Keep the timestamp available for the label cooling period from the
        // request boundary, but clear it if no primitive can be emitted. The
        // generation—not this timestamp—is the transaction identity used by
        // every asynchronous callback.
        lastProgrammaticSwitchTime = Date().timeIntervalSince1970
        lastProgrammaticTargetSpaceID = spaceID
        debugTrace(
            traceID,
            "switch transaction armed generation=\(generation.map(String.init) ?? "instant"), target=\(spaceID), display=\(displayID), liveBeforePrimitive=\(debugFormatSpaceMap(getCurrentSpaceIDsByDisplay()))"
        )

        // Gesture-based Space Switch handling. Keep the synthetic desktop
        // gesture as the primary path for fullscreen transitions too; the
        // WindowServer accepts it in the normal case and preserves the
        // native animation.
        if !isDragging, let steps = context.steps, steps != 0 {
            if let generation {
                DiagnosticEventLog.shared.record(
                    subsystem: "SpaceHelper",
                    level: "info",
                    "emit synthetic gesture: generation=\(generation), target=\(spaceID), steps=\(steps), display=\(displayID)"
                )
            }
            markProgrammaticSwitchStarted(
                spaceID: spaceID,
                generation: generation,
                isManual: isManual,
                forceInstant: forceInstant,
                displayID: displayID,
                isFullscreen: context.targetIsFullscreen
            )
            performSpaceSwitchGesture(
                steps: steps,
                targetDisplayID: displayID,
                forceInstant: forceInstant
            )
            if let generation {
                let involvesFullscreen =
                    context.targetIsFullscreen || context.currentSpaceIsFullscreen
                let retryDelay: TimeInterval = involvesFullscreen
                    ? 0.75
                    : max(0.75, min(targetDuration + 0.35, 1.35))
                scheduleSyntheticGestureRetry(
                    spaceID: spaceID,
                    displayID: displayID,
                    generation: generation,
                    attempt: 1,
                    scheduledDelay: retryDelay,
                    retryInterval: retryDelay,
                    maxAttempts: involvesFullscreen ? 2 : 1,
                    snapshotProbeAttempt: 0
                )
            }
            scheduleSpaceSwitchLabelSuppression(generation: generation)
            scheduleActiveLabelPreparation(spaceID: spaceID, generation: generation)
            return .started
        }

        var shouldUseShortcut = true
        // Note: Native shortcuts (Ctrl+1, Ctrl+2) only map to Desktops.
        if context.targetIsFullscreen {
            shouldUseShortcut = false
        } else {
            let spacesBefore = context.spaces.filter {
                $0.displayID == displayID && $0.num < context.targetSpace.num
            }
            if spacesBefore.contains(where: { $0.isFullscreen }) {
                shouldUseShortcut = false
            }
        }

        // Attempt to use system Desktop shortcuts (Control + Number).
        // This provides the smoothest transition when available.
        if shouldUseShortcut {
            if let globalNum = context.targetGlobalNum {
                if isShortcutEnabled(for: globalNum) && simulateDesktopShortcut(for: globalNum) {
                    markProgrammaticSwitchStarted(
                        spaceID: spaceID,
                        generation: generation,
                        isManual: isManual,
                        forceInstant: forceInstant,
                        displayID: displayID,
                        isFullscreen: context.targetIsFullscreen
                    )
                    scheduleSpaceSwitchLabelSuppression(generation: generation)
                    scheduleActiveLabelPreparation(spaceID: spaceID, generation: generation)
                    return .started
                }
            } else if let localNum = context.targetNum {
                // Fallback to local num if global is missing (should verify if this is ever needed/correct)
                if isShortcutEnabled(for: localNum) && simulateDesktopShortcut(for: localNum) {
                    markProgrammaticSwitchStarted(
                        spaceID: spaceID,
                        generation: generation,
                        isManual: isManual,
                        forceInstant: forceInstant,
                        displayID: displayID,
                        isFullscreen: context.targetIsFullscreen
                    )
                    scheduleSpaceSwitchLabelSuppression(generation: generation)
                    scheduleActiveLabelPreparation(spaceID: spaceID, generation: generation)
                    return .started
                }
            }
        }

        // If shortcuts didn't handle it, use our private window activation trick.
        if switchByActivatingOwnWindow(for: spaceID, isFullscreen: context.targetIsFullscreen) {

            markProgrammaticSwitchStarted(
                spaceID: spaceID,
                generation: generation,
                isManual: isManual,
                forceInstant: forceInstant,
                displayID: displayID,
                isFullscreen: context.targetIsFullscreen
            )

            scheduleSpaceSwitchLabelSuppression(generation: generation)
            scheduleActiveLabelPreparation(spaceID: spaceID, generation: generation)
            return .started
        }

        DiagnosticEventLog.shared.record(
            subsystem: "SpaceHelper",
            level: "warning",
            "switch started without an immediate switching primitive: target=\(spaceID)"
        )
        cancelActiveProgrammaticSwitch(reason: "no switching primitive")
        DiagnosticEventLog.shared.record(
            subsystem: "SpaceHelper",
            level: "warning",
            "switch request unavailable after transaction start: generation=\(generation.map(String.init) ?? "instant"), target=\(spaceID)"
        )
        return .unavailable
    }

}
