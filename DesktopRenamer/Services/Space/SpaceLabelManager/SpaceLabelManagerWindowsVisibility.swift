import AppKit
import Combine
import Foundation


extension SpaceLabelManager {

    func applyVisibility(_ visibleUUIDs: Set<String>, forDisplay displayID: String? = nil) {
        let traceID = SpaceHelper.debugTraceID()
        let liveSpaceIDsByDisplay = SpaceHelper.getCurrentSpaceIDsByDisplay()
        let fenceDescription = displayID.flatMap {
            spaceManager?.confirmedSpaceObservationFence.confirmation(for: $0)
        }.map { $0.spaceID + "/g" + String($0.generation) } ?? "nil"
        SpaceHelper.debugTrace(
            traceID,
            "labels apply begin scope=\(displayID ?? "global"), visible=\(visibleUUIDs.sorted()), live=\(SpaceHelper.debugFormatSpaceMap(liveSpaceIDsByDisplay)), managerCurrent=\(spaceManager?.currentSpaceUUID ?? "nil"), managerByDisplay=\(SpaceHelper.debugFormatSpaceMap(spaceManager?.currentSpaceByDisplay ?? [:])), fence=\(fenceDescription), previewSuppressed=\(isPreviewTransitionSuppressed)"
        )
        // Every visibility refresh is also a source-independent transition
        // checkpoint. This closes the race where a refresh was queued before
        // NSWorkspace delivered its space-change notification (for example
        // after a notification click or an external app activation).
        let currentSpaceID = spaceManager?.currentSpaceUUID ?? ""
        let managerHasStaleCurrentSpace = !currentSpaceID.isEmpty
            && !visibleUUIDs.isEmpty
            && !visibleUUIDs.contains(currentSpaceID)
        let visibleSpaceSetChanged = recordVisibleSpaceIDs(visibleUUIDs)
        if hideWhenSwitching && (visibleSpaceSetChanged || managerHasStaleCurrentSpace) {
            // A changed visible-space set is the first destination snapshot,
            // not proof that the animation has finished. Keep previews hidden
            // until the current-space publisher confirms the destination and
            // the settling pass observes a stable WindowServer state.
            suppressPreviewLabelsForTransition(
                duration: 1.2,
                reason: "visibility refresh detected space transition",
                beginsNewTransition: visibleSpaceSetChanged
            )
        }

        if let id = displayID {
             print("SpaceLabelManager: applyVisibility(visibleUUIDs: \(visibleUUIDs)) SCOPED to display: \(id)")
        } else {
             print("SpaceLabelManager: applyVisibility(visibleUUIDs: \(visibleUUIDs)) GLOBAL refresh")
        }

        let suppressPreviews = isPreviewTransitionSuppressed
        // During a transition every preview is hidden regardless of fullscreen
        // metadata. Avoid another synchronous managed-space read on this hot
        // path; the stable refresh below still rechecks fullscreen metadata
        // when previews are allowed to return.
        let fullscreenDisplayIDs = suppressPreviews
            ? []
            : currentFullscreenDisplayIDs(
                visibleUUIDs: visibleUUIDs,
                displayID: displayID
            )
        let windowsSnapshot = self.createdWindows

        for (key, window) in windowsSnapshot {
            if let targetDisplay = displayID, window.displayID != targetDisplay {
                continue // Skip windows that are on a different display than the one we are updating
            }

            if suppressPreviews
                || visibleUUIDs.contains(key)
                || fullscreenDisplayIDs.contains(window.displayID) {
                // The active space has its own dedicated label window. Keep
                // the preview window bound to the space, but never visible on
                // the active desktop or over a fullscreen app.
                if shouldPreservePreviewWindowOrderingForSettings {
                    window.hideForSettingsActivation()
                } else {
                    window.hideImmediately()
                }
            } else {
                window.updateVisibility(animated: false, visibleSpaceIDs: visibleUUIDs)
            }
        }

        updateActiveWindowModes(for: visibleUUIDs, displayID: displayID)
        SpaceHelper.debugTrace(
            traceID,
            "labels apply end scope=\(displayID ?? "global"), visible=\(visibleUUIDs.sorted()), previewSuppressed=\(isPreviewTransitionSuppressed), activeWindows=\(activeWindows.count), previewWindows=\(createdWindows.count), live=\(SpaceHelper.debugFormatSpaceMap(SpaceHelper.getCurrentSpaceIDsByDisplay()))"
        )
    }

    private func currentFullscreenDisplayIDs(
        visibleUUIDs: Set<String>,
        displayID: String?
    ) -> Set<String> {
        guard let spaceManager = spaceManager else { return [] }

        var fullscreenDisplayIDs = Set<String>(
            spaceManager.spaceNameDict.compactMap { space in
                guard space.isFullscreen,
                      visibleUUIDs.contains(space.id),
                      displayID == nil || displayID == space.displayID else {
                    return nil
                }
                return space.displayID
            }
        )

        // Fullscreen metadata can lag behind the managed-space ID. Refresh the
        // live fallback only when the visible-space set changes; repeated label
        // refreshes during one transition can otherwise perform the same CGS
        // read once per window.
        if visibleUUIDs != lastLiveFullscreenVisibleSpaceIDs
            || displayID != lastLiveFullscreenDisplayScope {
            lastLiveFullscreenVisibleSpaceIDs = visibleUUIDs
            lastLiveFullscreenDisplayScope = displayID
            if let liveState = SpaceHelper.getSystemState() {
                lastLiveFullscreenDisplayIDs = Set<String>(liveState.spaces.compactMap { space in
                    guard space.isFullscreen,
                          visibleUUIDs.contains(space.id),
                          displayID == nil || displayID == space.displayID else {
                        return nil
                    }
                    return space.displayID
                })
            } else {
                lastLiveFullscreenDisplayIDs = []
            }
        }

        fullscreenDisplayIDs.formUnion(lastLiveFullscreenDisplayIDs)
        return fullscreenDisplayIDs
    }

    func hidePreviewLabel(for spaceId: String) {
        if let window = createdWindows[spaceId] {
            if shouldPreservePreviewWindowOrderingForSettings {
                window.hideForSettingsActivation()
            } else {
                window.hideImmediately()
            }
        }
    }

    func hideAllPreviewLabels() {
        DiagnosticEventLog.shared.record(subsystem: "Labels", level: "info", "hideAllPreviewLabels (windows=\(createdWindows.count))")
        for window in createdWindows.values {
            if shouldPreservePreviewWindowOrderingForSettings {
                window.hideForSettingsActivation()
            } else {
                window.hideImmediately()
            }
        }
    }

    func hideAllPreviewLabelsForSettingsActivation() {
        DiagnosticEventLog.shared.record(
            subsystem: "Labels",
            level: "info",
            "hideAllPreviewLabelsForSettingsActivation (windows=\(createdWindows.count))"
        )
        for window in createdWindows.values {
            window.hideForSettingsActivation()
        }
    }

    func restorePreviewLabelsAfterSettingsActivation() {
        guard isSettingsWindowOpen else { return }
        guard !SpaceHelper.isSwitching,
              !SpaceHelper.isProgrammaticSwitchPromotionPending,
              !isPreviewTransitionSuppressed else {
            scheduleSettingsPreviewRestore()
            return
        }

        settingsPreviewRestoreWorkItem = nil
        let visibleUUIDs = resolvedVisibleSpaceIDs()
        guard !visibleUUIDs.isEmpty else { return }

        let fullscreenDisplayIDs = currentFullscreenDisplayIDs(
            visibleUUIDs: visibleUUIDs,
            displayID: nil
        )
        for (spaceID, window) in createdWindows {
            if visibleUUIDs.contains(spaceID)
                || fullscreenDisplayIDs.contains(window.displayID) {
                window.hideForSettingsActivation()
            } else {
                // Existing previews remain ordered in their target Space, so
                // this only restores their alpha and interaction state. The
                // regular global reconciliation path is intentionally avoided
                // here because it can infer a transient stale current Space
                // during Settings activation and reorder windows.
                window.updateVisibility(animated: false, visibleSpaceIDs: visibleUUIDs)
            }
        }
    }

    func scheduleSettingsPreviewRestore() {
        guard isSettingsWindowOpen else { return }
        settingsPreviewRestoreWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.restorePreviewLabelsAfterSettingsActivation()
        }
        settingsPreviewRestoreWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }

}
