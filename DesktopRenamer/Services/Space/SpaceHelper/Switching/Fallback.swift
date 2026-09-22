import AppKit
import CoreGraphics
import Foundation


extension SpaceHelper {

    static func switchByActivatingOwnWindow(for spaceID: String, isFullscreen: Bool) -> Bool
    {
        var targetWindow: SpaceLabelWindow? = nil
        var windowsToHide: [SpaceLabelWindow] = []

        // Identify target and potential conflicting windows.
        for window in NSApp.windows {
            if let labelWindow = window as? SpaceLabelWindow {
                if labelWindow.spaceId == spaceID {
                    // Preview labels are nonactivating panels and must never
                    // be used as the explicit switch anchor. Prefer the
                    // target space's active label; it temporarily becomes
                    // activation-capable only for this intentional switch.
                    if labelWindow.isActiveMode || targetWindow == nil {
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

        // Force window activation. Active labels are nonactivating during
        // normal interaction, so this is the only path that opts into app and
        // Space activation.
        DiagnosticEventLog.shared.record(subsystem: "SpaceHelper", level: "info", "switchByActivatingOwnWindow space=\(spaceID)")
        window.activateForSpaceSwitch()

        return true
    }

    static func scheduleSyntheticGestureRetry(
        spaceID: String,
        displayID: String,
        sourceSpaceID: String?,
        generation: UInt64,
        forceInstant: Bool,
        gestureLayout: String,
        attempt: Int,
        scheduledDelay: TimeInterval,
        retryInterval: TimeInterval,
        maxAttempts: Int,
        snapshotProbeAttempt: Int
    ) {
        syntheticGestureRetryWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            guard let active = switchTransactionCoordinator.active,
                  isSwitching,
                  active.generation == generation,
                  active.request.spaceID == spaceID else {
                return
            }
            syntheticGestureRetryWorkItem = nil

            guard let liveCurrentID = getCurrentSpaceID(for: displayID) else {
                scheduleSyntheticGestureSnapshotProbe(
                    spaceID: spaceID,
                    displayID: displayID,
                    sourceSpaceID: sourceSpaceID,
                    generation: generation,
                    forceInstant: forceInstant,
                    gestureLayout: gestureLayout,
                    attempt: attempt,
                    retryInterval: retryInterval,
                    maxAttempts: maxAttempts,
                    snapshotProbeAttempt: snapshotProbeAttempt
                )
                return
            }

            if liveCurrentID == spaceID {
                // The monitor callback is lossy under sustained switching.
                // Complete from the authoritative WindowServer read instead
                // of holding every later gesture until the timeout.
                if !programmaticSwitchDestinationObserved {
                    print(
                        "SpaceHelper: Watchdog confirmed synthetic gesture at "
                            + spaceID
                            + " after a missed monitor completion"
                    )
                }
                confirmGestureDirection(for: displayID, layout: gestureLayout)
                markProgrammaticSwitchComplete(at: spaceID)
                if !programmaticSwitchDestinationObserved {
                    scheduleSyntheticGestureSnapshotProbe(
                        spaceID: spaceID,
                        displayID: displayID,
                        sourceSpaceID: sourceSpaceID,
                        generation: generation,
                        forceInstant: forceInstant,
                        gestureLayout: gestureLayout,
                        attempt: attempt,
                        retryInterval: retryInterval,
                        maxAttempts: maxAttempts,
                        snapshotProbeAttempt: snapshotProbeAttempt
                    )
                }
                return
            }

            guard let state = getSystemState() else {
                scheduleSyntheticGestureSnapshotProbe(
                    spaceID: spaceID,
                    displayID: displayID,
                    sourceSpaceID: sourceSpaceID,
                    generation: generation,
                    forceInstant: forceInstant,
                    gestureLayout: gestureLayout,
                    attempt: attempt,
                    retryInterval: retryInterval,
                    maxAttempts: maxAttempts,
                    snapshotProbeAttempt: snapshotProbeAttempt
                )
                return
            }

            let displaySpaces = state.spaces
                .filter { $0.displayID == displayID }
                .sorted { $0.num < $1.num }
            guard let currentIndex = displaySpaces.firstIndex(where: { $0.id == liveCurrentID }),
                  let targetIndex = displaySpaces.firstIndex(where: { $0.id == spaceID }) else {
                scheduleSyntheticGestureSnapshotProbe(
                    spaceID: spaceID,
                    displayID: displayID,
                    sourceSpaceID: sourceSpaceID,
                    generation: generation,
                    forceInstant: forceInstant,
                    gestureLayout: gestureLayout,
                    attempt: attempt,
                    retryInterval: retryInterval,
                    maxAttempts: maxAttempts,
                    snapshotProbeAttempt: snapshotProbeAttempt
                )
                return
            }

            let steps = targetIndex - currentIndex
            guard steps != 0 else { return }
            guard attempt <= maxAttempts else { return }

            let directionFromSource: Int? = sourceSpaceID.flatMap { sourceID in
                guard let sourceIndex = displaySpaces.firstIndex(where: { $0.id == sourceID }) else {
                    return nil
                }
                return currentIndex - sourceIndex
            }
            let requestedDirectionFromSource: Int? = sourceSpaceID.flatMap { sourceID in
                guard let sourceIndex = displaySpaces.firstIndex(where: { $0.id == sourceID }) else {
                    return nil
                }
                return targetIndex - sourceIndex
            }
            let movedInOppositeDirection: Bool
            if let directionFromSource,
               let requestedDirectionFromSource,
               directionFromSource != 0,
               requestedDirectionFromSource != 0 {
                movedInOppositeDirection =
                    (directionFromSource > 0) != (requestedDirectionFromSource > 0)
            } else {
                movedInOppositeDirection = false
            }
            let isStillAtSource = directionFromSource.map { $0 == 0 } ?? true
            let directionAnomaly = movedInOppositeDirection || isStillAtSource
            if directionAnomaly {
                flipGestureDirection(for: displayID, layout: gestureLayout)
            }
            let inverted = gestureDirectionIsInverted(for: displayID, layout: gestureLayout)

            if directionAnomaly {
                DiagnosticEventLog.shared.record(
                    subsystem: "SpaceHelper",
                    level: "warning",
                    "Synthetic gesture direction anomaly for "
                        + spaceID
                        + " in generation "
                        + String(generation)
                        + "; retrying with flipped direction (attempt "
                        + String(attempt)
                        + "), inverted="
                        + String(inverted)
                )
                print(
                    "SpaceHelper: Retrying synthetic gesture to "
                        + spaceID
                        + " with flipped direction (attempt "
                        + String(attempt)
                        + ", inverted="
                        + String(inverted)
                        + ")"
                )
                performSpaceSwitchGesture(
                    steps: steps,
                    targetDisplayID: displayID,
                    forceInstant: forceInstant,
                    gestureLayout: gestureLayout
                )
            } else {
                DiagnosticEventLog.shared.record(
                    subsystem: "SpaceHelper",
                    level: "info",
                    "Synthetic gesture is moving toward "
                        + spaceID
                        + "; waiting for target confirmation"
                )
            }

            // Continue verification even when the normal monitor callback is
            // unavailable. No additional gesture is emitted unless the
            // authoritative read identifies a direction anomaly.
            let followUpDelay =
                attempt == maxAttempts ? min(retryInterval, 0.5) : retryInterval
            scheduleSyntheticGestureRetry(
                spaceID: spaceID,
                displayID: displayID,
                sourceSpaceID: sourceSpaceID,
                generation: generation,
                forceInstant: forceInstant,
                gestureLayout: gestureLayout,
                attempt: attempt + 1,
                scheduledDelay: followUpDelay,
                retryInterval: retryInterval,
                maxAttempts: maxAttempts,
                snapshotProbeAttempt: 0
            )
        }
        syntheticGestureRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + scheduledDelay, execute: workItem)
    }

    private static func scheduleSyntheticGestureSnapshotProbe(
        spaceID: String,
        displayID: String,
        sourceSpaceID: String?,
        generation: UInt64,
        forceInstant: Bool,
        gestureLayout: String,
        attempt: Int,
        retryInterval: TimeInterval,
        maxAttempts: Int,
        snapshotProbeAttempt: Int
    ) {
        let snapshotProbeLimit = 4
        guard snapshotProbeAttempt < snapshotProbeLimit else {
            print(
                "SpaceHelper: Synthetic gesture watchdog could not obtain a stable snapshot for "
                    + spaceID
            )
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceHelper",
                level: "warning",
                "Synthetic gesture watchdog exhausted transient snapshot probes: generation=\(generation), target=\(spaceID)"
            )
            return
        }

        DiagnosticEventLog.shared.record(
            subsystem: "SpaceHelper",
            level: "info",
            "Synthetic gesture watchdog retrying transient snapshot: generation=\(generation), target=\(spaceID), probe=\(snapshotProbeAttempt + 1)"
        )
        scheduleSyntheticGestureRetry(
            spaceID: spaceID,
            displayID: displayID,
            sourceSpaceID: sourceSpaceID,
            generation: generation,
            forceInstant: forceInstant,
            gestureLayout: gestureLayout,
            attempt: attempt,
            scheduledDelay: 0.12,
            retryInterval: retryInterval,
            maxAttempts: maxAttempts,
            snapshotProbeAttempt: snapshotProbeAttempt + 1
        )
    }
}
