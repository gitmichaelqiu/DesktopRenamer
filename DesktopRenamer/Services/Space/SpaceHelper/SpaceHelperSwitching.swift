import AppKit
import CoreGraphics
import Foundation

extension SpaceHelper {

    private struct SpaceSwitchContext {
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

    private enum ProgrammaticSwitchEndReason {
        case confirmed
        case timedOut
    }

    private static func isSpaceCurrentAndVisible(_ spaceID: String) -> Bool {
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
        if forceInstant, switchTransactionCoordinator.active != nil {
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
            return .alreadyCurrent
        }

        return startSpaceSwitch(context, forceInstant: forceInstant, isManual: isManual)
    }

    private static func makeSpaceSwitchContext(for spaceID: String) -> SpaceSwitchContext? {
        guard let state = getSystemState(),
              let targetSpace = state.spaces.first(where: { $0.id == spaceID }) else {
            return nil
        }

        let liveCurrentSpaceID = getCurrentSpaceID(for: targetSpace.displayID)
        if let liveCurrentSpaceID {
            print("SpaceHelper: switchToSpace check. Live ID: \(liveCurrentSpaceID), Target: \(spaceID)")
        }

        let currentSpaceIsFullscreen = state.spaces
            .first(where: { $0.id == liveCurrentSpaceID })?.isFullscreen ?? false
        let displaySpaces = state.spaces
            .filter { $0.displayID == targetSpace.displayID }
            .sorted { $0.num < $1.num }
        let steps: Int?
        if let liveCurrentSpaceID,
           let currentIndex = displaySpaces.firstIndex(where: { $0.id == liveCurrentSpaceID }),
           let targetIndex = displaySpaces.firstIndex(where: { $0.id == spaceID }) {
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
    private static func startSpaceSwitch(
        _ context: SpaceSwitchContext,
        forceInstant: Bool,
        isManual: Bool
    ) -> SpaceSwitchRequestDisposition {
        cancelPendingSwitchPromotion()

        let spaceID = context.targetSpace.id
        let displayID = context.targetSpace.displayID
        let generation: UInt64?

        if forceInstant {
            generation = nil
            isSwitching = false
            programmaticSwitchDestinationObserved = false
            programmaticSwitchNotificationObserved = false
        } else {
            let newGeneration = switchTransactionCoordinator.begin(
                spaceID: spaceID,
                isManual: isManual
            )
            generation = newGeneration
            isSwitching = true
            programmaticSwitchDestinationObserved = false
            programmaticSwitchNotificationObserved = false
            programmaticSwitchCompletionWorkItem?.cancel()
            programmaticSwitchCompletionWorkItem = nil
            programmaticSwitchTimeoutWorkItem?.cancel()
            programmaticSwitchTimeoutWorkItem = nil
            fullscreenGestureRetryWorkItem?.cancel()
            fullscreenGestureRetryWorkItem = nil
        }

        // Keep the timestamp available for the label cooling period from the
        // request boundary, but clear it if no primitive can be emitted. The
        // generation—not this timestamp—is the transaction identity used by
        // every asynchronous callback.
        lastProgrammaticSwitchTime = Date().timeIntervalSince1970
        lastProgrammaticTargetSpaceID = spaceID
        lastProgrammaticSwitchUsedSLS = false

        // Prepare only the dedicated active label for the destination. Preview
        // labels still follow the existing hideWhenSwitching behavior.
        NotificationCenter.default.post(
            name: NSNotification.Name("SpaceSwitchTargetRequested"),
            object: nil,
            userInfo: ["spaceID": spaceID]
        )

        NotificationCenter.default.post(
            name: NSNotification.Name("SpaceSwitchRequested"), object: nil)

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
            if let generation,
               context.targetIsFullscreen || context.currentSpaceIsFullscreen {
                scheduleFullscreenGestureRetry(
                    spaceID: spaceID,
                    displayID: displayID,
                    generation: generation,
                    attempt: 1
                )
            }
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

            // High-priority fix for Fullscreen Focus:
            // When switching to a Fullscreen space via SpaceLabelWindow, DesktopRenamer initially gets focus.
            // This can cause the OS to revert to the previous space if we don't hand off focus immediately.
            // We must identify the "owner" app of the fullscreen space and activate it.
            // Since we just triggered the visual switch, activating the app now should correctly
            // prioritize the window on the target space (resolving the "multiple windows" ambiguity).
            if context.targetIsFullscreen {
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

    private static func markProgrammaticSwitchStarted(
        spaceID: String,
        generation: UInt64?,
        isManual: Bool,
        forceInstant: Bool,
        displayID: String,
        isFullscreen: Bool
    ) {
        lastProgrammaticSwitchTime = Date().timeIntervalSince1970
        lastProgrammaticTargetSpaceID = spaceID
        lastProgrammaticSwitchUsedSLS = false

        DiagnosticEventLog.shared.record(
            subsystem: "SpaceHelper",
            level: "info",
            "programmatic switch started: generation=\(generation.map(String.init) ?? "instant"), target=\(spaceID), display=\(displayID), fullscreen=\(isFullscreen)"
        )

        var startedUserInfo: [String: Any] = [
            "spaceID": spaceID,
            "isManual": isManual,
            "forceInstant": forceInstant
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

    private static func cancelPendingSwitchPromotion() {
        programmaticSwitchPromotionWorkItem?.cancel()
        programmaticSwitchPromotionWorkItem = nil
        programmaticSwitchPromotionRequest = nil
        programmaticSwitchPromotionGeneration = nil
    }

    private static func cancelActiveProgrammaticSwitch(reason: String) {
        guard let active = switchTransactionCoordinator.active else {
            switchTransactionCoordinator.cancelActive(dropPending: true)
            isSwitching = false
            programmaticSwitchDestinationObserved = false
            programmaticSwitchNotificationObserved = false
            programmaticSwitchCompletionWorkItem?.cancel()
            programmaticSwitchCompletionWorkItem = nil
            programmaticSwitchTimeoutWorkItem?.cancel()
            programmaticSwitchTimeoutWorkItem = nil
            fullscreenGestureRetryWorkItem?.cancel()
            fullscreenGestureRetryWorkItem = nil
            cancelPendingSwitchPromotion()
            lastProgrammaticSwitchTime = 0
            lastProgrammaticTargetSpaceID = nil
            lastProgrammaticSwitchUsedSLS = false
            return
        }

        programmaticSwitchCompletionWorkItem?.cancel()
        programmaticSwitchCompletionWorkItem = nil
        programmaticSwitchTimeoutWorkItem?.cancel()
        programmaticSwitchTimeoutWorkItem = nil
        fullscreenGestureRetryWorkItem?.cancel()
        fullscreenGestureRetryWorkItem = nil
        cancelPendingSwitchPromotion()
        switchTransactionCoordinator.cancelActive(dropPending: true)
        isSwitching = false
        programmaticSwitchDestinationObserved = false
        programmaticSwitchNotificationObserved = false
        lastProgrammaticSwitchTime = 0
        lastProgrammaticTargetSpaceID = nil
        lastProgrammaticSwitchUsedSLS = false

        DiagnosticEventLog.shared.record(
            subsystem: "SpaceHelper",
            level: "warning",
            "programmatic switch canceled: generation=\(active.generation), target=\(active.request.spaceID), reason=\(reason)"
        )
    }

    private static func scheduleProgrammaticSwitchTimeout(spaceID: String, generation: UInt64) {
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
    /// WindowServer state. The active-space notification is also required
    /// before the transition is considered complete.
    static func markProgrammaticSwitchComplete(at spaceID: String) {
        guard let active = switchTransactionCoordinator.active,
              isSwitching,
              active.request.spaceID == spaceID else { return }
        guard isSpaceCurrentAndVisible(spaceID) else {
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceHelper",
                level: "info",
                "programmatic destination is not current and visible yet at space \(spaceID); waiting for a consistent WindowServer read"
            )
            return
        }
        programmaticSwitchDestinationObserved = true
        guard programmaticSwitchNotificationObserved else {
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceHelper",
                level: "info",
                "programmatic destination observed at space \(spaceID); waiting for active-space notification"
            )
            return
        }

        finishProgrammaticSwitch(at: spaceID, generation: active.generation)
    }

    /// Records the completion signal emitted by NSWorkspace when the active
    /// space changes. SpaceManager may have observed the destination first, so
    /// either ordering is accepted.
    static func noteActiveSpaceDidChange() {
        guard let active = switchTransactionCoordinator.active, isSwitching else { return }
        programmaticSwitchNotificationObserved = true
        guard programmaticSwitchDestinationObserved else { return }

        finishProgrammaticSwitch(at: active.request.spaceID, generation: active.generation)
    }

    private static func finishProgrammaticSwitch(at spaceID: String, generation: UInt64) {
        guard programmaticSwitchCompletionWorkItem == nil else { return }

        // The first matching WindowServer read and the active-space
        // notification can both arrive before the visual swipe has finished.
        // Keep the transition open for one settling interval, then notify the
        // label manager so it can perform its own stable-state verification.
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
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
        fullscreenGestureRetryWorkItem?.cancel()
        fullscreenGestureRetryWorkItem = nil

        let pendingRequest = switchTransactionCoordinator.endActive()
        isSwitching = false
        programmaticSwitchDestinationObserved = false
        programmaticSwitchNotificationObserved = false

        switch reason {
        case .confirmed:
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceHelper",
                level: "info",
                "programmatic switch confirmed: generation=\(generation), target=\(spaceID)"
            )
            NotificationCenter.default.post(
                name: NSNotification.Name("SpaceProgrammaticSwitchFinished"),
                object: nil,
                userInfo: [
                    "spaceID": spaceID,
                    "generation": generation,
                    "confirmed": true
                ]
            )
            NotificationCenter.default.post(
                name: NSNotification.Name("SpaceProgrammaticSwitchSettled"),
                object: nil,
                userInfo: ["spaceID": spaceID, "generation": generation]
            )
        case .timedOut:
            // The target was not confirmed. Do not leave its timestamp and ID
            // available to classify a later external switch as ours.
            lastProgrammaticSwitchTime = 0
            lastProgrammaticTargetSpaceID = nil
            lastProgrammaticSwitchUsedSLS = false
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceHelper",
                level: "warning",
                "programmatic switch timed out: generation=\(generation), target=\(spaceID)"
            )
            NotificationCenter.default.post(
                name: NSNotification.Name("SpaceProgrammaticSwitchFinished"),
                object: nil,
                userInfo: [
                    "spaceID": spaceID,
                    "generation": generation,
                    "confirmed": false
                ]
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

    private static func switchByActivatingOwnWindow(for spaceID: String, isFullscreen: Bool) -> Bool
    {
        var targetWindow: SpaceLabelWindow? = nil
        var windowsToHide: [SpaceLabelWindow] = []

        // Identify target and potential conflicting windows.
        for window in NSApp.windows {
            if let labelWindow = window as? SpaceLabelWindow {
                if labelWindow.spaceId == spaceID {
                    // Use the preview window as the activation anchor. The
                    // active label is managed independently by the manager.
                    if !labelWindow.isActiveMode || targetWindow == nil {
                        targetWindow = labelWindow
                    }
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

    private static func scheduleFullscreenGestureRetry(
        spaceID: String,
        displayID: String,
        generation: UInt64,
        attempt: Int
    ) {
        fullscreenGestureRetryWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            guard let active = switchTransactionCoordinator.active,
                  isSwitching,
                  active.generation == generation,
                  active.request.spaceID == spaceID,
                  getCurrentSpaceID(for: displayID) != spaceID,
                  let state = getSystemState(),
                  let liveCurrentID = getCurrentSpaceID(for: displayID) else {
                return
            }
            fullscreenGestureRetryWorkItem = nil

            let displaySpaces = state.spaces
                .filter { $0.displayID == displayID }
                .sorted { $0.num < $1.num }
            guard let currentIndex = displaySpaces.firstIndex(where: { $0.id == liveCurrentID }),
                  let targetIndex = displaySpaces.firstIndex(where: { $0.id == spaceID }) else {
                return
            }

            let steps = targetIndex - currentIndex
            guard steps != 0 else { return }

            DiagnosticEventLog.shared.record(
                subsystem: "SpaceHelper",
                level: "warning",
                "Fullscreen gesture has not reached "
                    + spaceID
                    + " for generation "
                    + String(generation)
                    + "; retrying synthetic gesture (attempt "
                    + String(attempt)
                    + ")"
            )
            performSpaceSwitchGesture(
                steps: steps,
                targetDisplayID: displayID,
                forceInstant: false
            )

            if attempt < 2 {
                scheduleFullscreenGestureRetry(
                    spaceID: spaceID,
                    displayID: displayID,
                    generation: generation,
                    attempt: attempt + 1
                )
            }
        }
        fullscreenGestureRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: workItem)
    }
}
