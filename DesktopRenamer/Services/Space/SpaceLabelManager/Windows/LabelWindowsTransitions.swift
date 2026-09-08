import AppKit
import Combine
import Foundation


extension SpaceLabelManager {


    @objc func handleSpaceChangeWillReconcile() {
        guard hideWhenSwitching else { return }

        // SpaceManager publishes spaceNameDict before currentSpaceUUID. This
        // boundary keeps window creation and dictionary-driven refreshes inside
        // the same suppression state as the actual switch.
        suppressPreviewLabelsForTransition(
            duration: 1.2,
            reason: "space reconciliation",
            beginsNewTransition: true
        )
    }

    func suppressPreviewLabelsForTransition(
        duration: TimeInterval,
        reason: String,
        beginsNewTransition: Bool = false,
        transitionCompleted: Bool = false
    ) {
        let now = Date()
        let hasPendingTransition = previewTransitionRestoreWorkItem != nil
            || previewLabelsSuppressedUntil != nil
        let shouldBeginNewTransition = beginsNewTransition || !hasPendingTransition

        previewTransitionRestoreWorkItem?.cancel()
        previewTransitionRestoreWorkItem = nil
        previewTransitionGeneration += 1
        let generation = previewTransitionGeneration

        if shouldBeginNewTransition {
            previewTransitionRestoreAttempt = 0
            previewTransitionStablePasses = 0
            previewTransitionLastVisibleUUIDs = nil
            previewTransitionCompletionObserved = false
            previewTransitionFallbackDeadline = now.addingTimeInterval(duration)
        } else if !previewTransitionCompletionObserved {
            // Extend an unconfirmed transition when another WindowServer
            // reconciliation pass arrives, but never extend a transition after
            // its active-space notification has confirmed completion.
            let requestedFallback = now.addingTimeInterval(duration)
            previewTransitionFallbackDeadline = max(
                previewTransitionFallbackDeadline ?? .distantPast,
                requestedFallback
            )
        }

        if transitionCompleted {
            let wasAlreadyCompleted = previewTransitionCompletionObserved
            previewTransitionCompletionObserved = true
            if !wasAlreadyCompleted {
                previewTransitionStablePasses = 0
                previewTransitionLastVisibleUUIDs = nil
            }

            // The notification is the completion boundary. Keep a short
            // settling interval for the final WindowServer snapshot instead of
            // waiting out the original blind suppression delay.
            previewLabelsSuppressedUntil = now.addingTimeInterval(0.15)
        } else if !previewTransitionCompletionObserved {
            let requestedSuppressionEnd = now.addingTimeInterval(duration)
            let existingSuppressionEnd = previewLabelsSuppressedUntil ?? .distantPast
            previewLabelsSuppressedUntil = max(existingSuppressionEnd, requestedSuppressionEnd)
        }

        hideAllPreviewLabels()

        DiagnosticEventLog.shared.record(
            subsystem: "Labels",
            level: "info",
            "\(reason) — hiding previews during transition"
        )

        let delay = max(0.01, previewLabelsSuppressedUntil?.timeIntervalSinceNow ?? duration)
        schedulePreviewTransitionRestore(
            after: delay,
            generation: generation,
            reason: reason
        )
    }

    private func schedulePreviewTransitionRestore(
        after delay: TimeInterval,
        generation: Int,
        reason: String
    ) {
        let workItem = DispatchWorkItem { [weak self] in
            self?.attemptPreviewTransitionRestore(generation: generation, reason: reason)
        }
        previewTransitionRestoreWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(0.01, delay),
            execute: workItem
        )
    }

    private func attemptPreviewTransitionRestore(generation: Int, reason: String) {
        guard generation == previewTransitionGeneration else { return }
        guard let suppressionEnd = previewLabelsSuppressedUntil else {
            previewTransitionRestoreWorkItem = nil
            return
        }

        let now = Date()
        if suppressionEnd > now {
            schedulePreviewTransitionRestore(
                after: suppressionEnd.timeIntervalSince(now),
                generation: generation,
                reason: reason
            )
            return
        }

        // If the active-space notification has not arrived yet, keep the
        // previews hidden until the bounded fallback deadline. The short
        // minimum suppression interval above is not a completion signal.
        if !previewTransitionCompletionObserved,
           let fallbackDeadline = previewTransitionFallbackDeadline,
           fallbackDeadline > now {
            schedulePreviewTransitionRestore(
                after: fallbackDeadline.timeIntervalSince(now),
                generation: generation,
                reason: reason
            )
            return
        }

        let visibleUUIDs = resolvedVisibleSpaceIDs()
        let currentSpaceID = spaceManager?.currentSpaceUUID ?? ""
        let hasKnownCurrentSpace = !currentSpaceID.isEmpty
        let currentSpaceIsVisible = !hasKnownCurrentSpace || visibleUUIDs.contains(currentSpaceID)
        let liveStateIsStable = !visibleUUIDs.isEmpty
            && currentSpaceIsVisible
            && !SpaceHelper.isSwitching

        if liveStateIsStable && previewTransitionLastVisibleUUIDs == visibleUUIDs {
            previewTransitionStablePasses += 1
        } else {
            previewTransitionStablePasses = 0
        }
        previewTransitionLastVisibleUUIDs = visibleUUIDs
        previewTransitionRestoreAttempt += 1

        // Require two identical, non-transitioning WindowServer snapshots.
        // This prevents a late visibility refresh from reopening previews while
        // macOS is still publishing the destination space. Never fall through
        // to restoration after a fixed number of attempts: doing so reopens
        // previews precisely when a Dock/app activation transition is still
        // reporting stale state.
        let requiredStablePasses = 2
        if previewTransitionStablePasses < requiredStablePasses {
            schedulePreviewTransitionRestore(
                after: liveStateIsStable ? 0.15 : 0.25,
                generation: generation,
                reason: reason
            )
            return
        }

        previewLabelsSuppressedUntil = nil
        previewTransitionRestoreWorkItem = nil
        previewTransitionLastVisibleUUIDs = nil
        previewTransitionCompletionObserved = false
        previewTransitionFallbackDeadline = nil
        DiagnosticEventLog.shared.record(
            subsystem: "Labels",
            level: "info",
            "\(reason) transition settled — restoring previews"
        )
        updateAllWindowModes()
    }

    @objc func handleSpaceSwitchTargetRequested(_ notification: Notification) {
        let prepareActiveLabel = { [weak self] in
            guard let self = self,
                  let spaceID = notification.userInfo?["spaceID"] as? String,
                  let window = self.activeWindows[spaceID] else { return }

            // This window is already bound to the destination space. Showing
            // it now lets WindowServer reveal it with the destination rather
            // than waiting for a later reconciliation pass.
            window.setActiveVisibility(true, animated: false)
            self.scheduleActiveLabelSynchronization()
        }

        if Thread.isMainThread {
            prepareActiveLabel()
        } else {
            DispatchQueue.main.sync(execute: prepareActiveLabel)
        }
    }

    @objc func handleSpaceRearrangementCompleted() {
        guard showPreviewLabels else { return }

        // Reordering does not change currentSpaceUUID, so the normal space-change
        // observer cannot restore preview labels hidden during the operation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.updateAllWindowModes()
        }
    }

}
