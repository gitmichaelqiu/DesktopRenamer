import AppKit
import Foundation
import SwiftUI
import WidgetKit

extension SpaceManager {

    // Space navigation and switching logic.
    @discardableResult
    func switchToSpace(
        _ space: DesktopSpace,
        forceInstant: Bool = false,
        isManual: Bool = true
    ) -> SpaceSwitchRequestDisposition {
        print("SpaceManager: switchToSpace(\(space.id)) on display \(space.displayID) forceInstant: \(forceInstant) isManual: \(isManual)")
        let traceID = SpaceHelper.debugTraceID()
        SpaceHelper.debugTrace(
            traceID,
            "manager switch request target=\(space.id), display=\(space.displayID), forceInstant=\(forceInstant), manual=\(isManual), modelCurrent=\(currentSpaceUUID), live=\(SpaceHelper.debugFormatSpaceMap(SpaceHelper.getCurrentSpaceIDsByDisplay()))"
        )

        // Every explicit request invalidates observations from the previous
        // destination before WindowServer can deliver another delayed read.
        // This also covers force-instant requests, which do not have a
        // transaction completion notification of their own.
        let observationGeneration = beginSpaceObservation(
            spaceID: space.id,
            displayID: space.displayID
        )

        let disposition = SpaceHelper.switchToSpace(
            space.id,
            forceInstant: forceInstant,
            isManual: isManual
        )

        switch disposition {
        case .alreadyCurrent:
            // A no-op selection must not leave a retry from an earlier
            // transition alive. If the live query agrees, it is also a valid
            // confirmed destination and should fence older snapshots.
            cancelPendingMonitorSpaceChange()
            cancelSpaceChangeRetry()
            if SpaceHelper.getCurrentSpaceID(for: space.displayID) == space.id {
                confirmSpaceObservation(
                    displayID: space.displayID,
                    spaceID: space.id,
                    generation: observationGeneration
                )
            }
        case .unavailable:
            cancelPendingMonitorSpaceChange()
            cancelSpaceChangeRetry()
            pendingProgrammaticSpaceSwitches.removeValue(forKey: space.displayID)
            confirmedSpaceObservationFence.invalidate(displayID: space.displayID)
        case .started:
            if let requestID = SpaceHelper.lastProgrammaticSwitchRequestID {
                latestProgrammaticSwitchRequestIDs[space.displayID] = max(
                    latestProgrammaticSwitchRequestIDs[space.displayID] ?? 0,
                    requestID
                )
            }

            // Force-instant switches do not emit a completion notification.
            // The switching primitive has been emitted by this point, so
            // protect its destination immediately while WindowServer drains
            // older monitor and retry snapshots.
            if forceInstant {
                confirmSpaceObservation(
                    displayID: space.displayID,
                    spaceID: space.id,
                    generation: observationGeneration
                )
            }
        case .queued:
            break
        }
        SpaceHelper.debugTrace(
            traceID,
            "manager switch result target=\(space.id), display=\(space.displayID), disposition=\(String(describing: disposition)), fence=\(confirmedSpaceObservationFence.confirmation(for: space.displayID).map { $0.spaceID + "/g" + String($0.generation) } ?? "nil"), modelCurrent=\(currentSpaceUUID), liveAfter=\(SpaceHelper.debugFormatSpaceMap(SpaceHelper.getCurrentSpaceIDsByDisplay()))"
        )
        return disposition
    }

    private func beginSpaceObservation(spaceID: String, displayID: String) -> UInt64 {
        nextSpaceObservationGeneration += 1
        let generation = nextSpaceObservationGeneration
        confirmedSpaceObservationFence.beginSwitch(
            displayID: displayID,
            generation: generation
        )
        pendingProgrammaticSpaceSwitches[displayID] = (
            spaceID: spaceID,
            generation: generation
        )
        cancelPendingMonitorSpaceChange()
        cancelSpaceChangeRetry()
        SpaceHelper.debugTrace(
            SpaceHelper.debugTraceID(),
            "manager observation fence begun display=\(displayID), target=\(spaceID), generation=\(generation), live=\(SpaceHelper.debugFormatSpaceMap(SpaceHelper.getCurrentSpaceIDsByDisplay()))"
        )
        return generation
    }

    func confirmSpaceObservation(
        displayID: String,
        spaceID: String,
        generation: UInt64
    ) {
        confirmedSpaceObservationFence.confirm(
            displayID: displayID,
            spaceID: spaceID,
            generation: generation
        )
        SpaceHelper.debugTrace(
            SpaceHelper.debugTraceID(),
            "manager observation fence confirmed display=\(displayID), target=\(spaceID), generation=\(generation), live=\(SpaceHelper.debugFormatSpaceMap(SpaceHelper.getCurrentSpaceIDsByDisplay()))"
        )
        guard let pending = pendingProgrammaticSpaceSwitches[displayID],
              pending.spaceID == spaceID,
              pending.generation == generation else {
            return
        }
        pendingProgrammaticSpaceSwitches.removeValue(forKey: displayID)
    }

    @objc func handleProgrammaticSwitchStarted(_ notification: Notification) {
        guard let spaceID = notification.userInfo?["spaceID"] as? String else {
            return
        }

        let update = { [weak self] in
            guard let self else { return }
            let isManual = notification.userInfo?["isManual"] as? Bool == true
            let forceInstant = notification.userInfo?["forceInstant"] as? Bool == true
            let generation = notification.userInfo?["generation"] as? UInt64
            let requestID = notification.userInfo?["requestID"] as? UInt64
            let displayID = notification.userInfo?["displayID"] as? String
                ?? self.spaceNameDict.first(where: { $0.id == spaceID })?.displayID
                ?? self.currentDisplayID
            SpaceHelper.debugTrace(
                SpaceHelper.debugTraceID(),
                "manager received programmatic-start target=\(spaceID), display=\(displayID), request=\(requestID.map(String.init) ?? "nil"), generation=\(generation.map(String.init) ?? "instant"), forceInstant=\(forceInstant), manual=\(isManual), live=\(SpaceHelper.debugFormatSpaceMap(SpaceHelper.getCurrentSpaceIDsByDisplay()))"
            )

            if let requestID {
                if let latestRequestID = self.latestProgrammaticSwitchRequestIDs[displayID],
                   requestID < latestRequestID {
                    DiagnosticEventLog.shared.record(
                        subsystem: "SpaceManager",
                        level: "info",
                        "Ignoring stale programmatic switch start: display=\(displayID), request=\(requestID), latest=\(latestRequestID), target=\(spaceID)"
                    )
                    return
                }
                self.latestProgrammaticSwitchRequestIDs[displayID] = max(
                    self.latestProgrammaticSwitchRequestIDs[displayID] ?? 0,
                    requestID
                )
            }

            // SpaceHelper can be called directly by a service, without going
            // through SpaceManager.switchToSpace. Give that request the same
            // per-display fence as manager-owned switches. A newer manager
            // request already occupying this display remains authoritative.
            var ownsObservation = false
            if let pending = self.pendingProgrammaticSpaceSwitches[displayID] {
                if pending.spaceID != spaceID {
                    DiagnosticEventLog.shared.record(
                        subsystem: "SpaceManager",
                        level: "info",
                        "Keeping newer pending observation: display=\(displayID), pending=\(pending.spaceID), started=\(spaceID)"
                    )
                } else {
                    ownsObservation = true
                }
            } else {
                _ = self.beginSpaceObservation(
                    spaceID: spaceID,
                    displayID: displayID
                )
                ownsObservation = true
            }

            if forceInstant,
               ownsObservation,
               let pending = self.pendingProgrammaticSpaceSwitches[displayID] {
                self.confirmSpaceObservation(
                    displayID: displayID,
                    spaceID: spaceID,
                    generation: pending.generation
                )
            }

            // This notification also arrives for a transaction promoted from
            // the pending queue. Cancel any retry belonging to the previous
            // transition before the new generation can be observed.
            self.cancelPendingMonitorSpaceChange()
            self.cancelSpaceChangeRetry()
            self.activeProgrammaticSwitchGeneration = generation

            if isManual {
                self.lastManualSwitchTime = Date().timeIntervalSince1970
                self.lastManualSwitchTargetUUID = spaceID
            } else {
                // A non-manual transaction supersedes any short-lived manual
                // attribution left by an earlier gesture.
                self.lastManualSwitchTime = 0
                self.lastManualSwitchTargetUUID = nil
            }
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceManager",
                level: "info",
                "programmatic switch transaction started: target=\(spaceID), display=\(displayID), manual=\(isManual), generation=\(generation.map(String.init) ?? "instant")"
            )
            SpaceHelper.debugTrace(
                SpaceHelper.debugTraceID(),
                "manager programmatic-start applied target=\(spaceID), display=\(displayID), activeGeneration=\(self.activeProgrammaticSwitchGeneration.map(String.init) ?? "nil"), fence=\(self.confirmedSpaceObservationFence.confirmation(for: displayID).map { $0.spaceID + "/g" + String($0.generation) } ?? "nil")"
            )
        }

        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }

    @objc func handleProgrammaticSwitchFinished(_ notification: Notification) {
        guard let generation = notification.userInfo?["generation"] as? UInt64,
              let spaceID = notification.userInfo?["spaceID"] as? String,
              let confirmed = notification.userInfo?["confirmed"] as? Bool else {
            return
        }

        let update = { [weak self] in
            guard let self else { return }

            let displayID = notification.userInfo?["displayID"] as? String
                ?? self.spaceNameDict.first(where: { $0.id == spaceID })?.displayID
                ?? self.currentDisplayID
            SpaceHelper.debugTrace(
                SpaceHelper.debugTraceID(),
                "manager received programmatic-finish target=\(spaceID), display=\(displayID), generation=\(generation), confirmed=\(confirmed), live=\(SpaceHelper.debugFormatSpaceMap(SpaceHelper.getCurrentSpaceIDsByDisplay()))"
            )

            guard self.activeProgrammaticSwitchGeneration == generation else {
                DiagnosticEventLog.shared.record(
                    subsystem: "SpaceManager",
                    level: "info",
                    "Ignoring stale programmatic switch completion: generation=\(generation), active=\(self.activeProgrammaticSwitchGeneration.map(String.init) ?? "nil")"
                )
                return
            }

            // A retry scheduled from a transaction is no longer allowed to
            // publish its old WindowServer snapshot after that transaction has
            // ended. A timed-out transaction gets a new, unassociated retry
            // chain below so a genuine destination change is still recovered.
            self.activeProgrammaticSwitchGeneration = nil
            self.cancelSpaceChangeRetry()
            if !confirmed {
                if let pending = self.pendingProgrammaticSpaceSwitches[displayID],
                   pending.spaceID == spaceID {
                    self.pendingProgrammaticSpaceSwitches.removeValue(forKey: displayID)
                    self.confirmedSpaceObservationFence.invalidate(displayID: displayID)
                }
                self.scheduleSpaceChangeRetry(displayID: displayID)
            } else {
                // A newer queued request may already own this display. Do not
                // let the older completion recreate its fence.
                if let pending = self.pendingProgrammaticSpaceSwitches[displayID],
                   pending.spaceID == spaceID {
                    self.confirmSpaceObservation(
                        displayID: displayID,
                        spaceID: spaceID,
                        generation: pending.generation
                    )
                }

                if !self.applyConfirmedSpace(spaceID) {
                    // A newly created fullscreen space may not be in the
                    // cached list yet. Fall back to the normal topology
                    // reconciliation in that case.
                    self.refreshSpaceState()
                }
            }

            DiagnosticEventLog.shared.record(
                subsystem: "SpaceManager",
                level: confirmed ? "info" : "warning",
                "programmatic switch finished: generation=\(generation), display=\(displayID), confirmed=\(confirmed), retry chain reset"
            )
        }

        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }

    /// Publishes a destination only after SpaceHelper has completed its
    /// independent WindowServer settle verification. Existing spaces already
    /// have all metadata needed by the status bar, so another asynchronous raw
    /// space query would only add latency to the visible update.
    private func applyConfirmedSpace(_ spaceID: String) -> Bool {
        guard let space = spaceNameDict.first(where: { $0.id == spaceID }) else {
            return false
        }

        currentDisplayID = space.displayID
        currentRawSpaceUUID = spaceID
        currentSpaceByDisplay[space.displayID] = spaceID
        currentIsDesktop = !space.isFullscreen

        if currentSpaceUUID != spaceID {
            currentSpaceUUID = spaceID
            scheduleWidgetUpdate()
        }
        return true
    }
    
    @discardableResult
    func switchToPreviousSpace(
        onDisplayID displayID: String? = nil,
        forceInstant: Bool? = nil
    ) -> SpaceSwitchRequestDisposition {
        let targetDisplayID = displayID ?? spaceNameDict.first(where: { $0.id == currentSpaceUUID })?.displayID ?? currentDisplayID
        guard let current = findBestCurrentSpace(for: targetDisplayID) else {
            return .unavailable
        }
        return proceedToSwitch(
            from: current,
            on: targetDisplayID,
            direction: -1,
            forceInstant: forceInstant ?? false
        )
    }

    @discardableResult
    func switchToNextSpace(
        onDisplayID displayID: String? = nil,
        forceInstant: Bool? = nil
    ) -> SpaceSwitchRequestDisposition {
        let targetDisplayID = displayID ?? spaceNameDict.first(where: { $0.id == currentSpaceUUID })?.displayID ?? currentDisplayID
        guard let current = findBestCurrentSpace(for: targetDisplayID) else {
            return .unavailable
        }
        return proceedToSwitch(
            from: current,
            on: targetDisplayID,
            direction: 1,
            forceInstant: forceInstant ?? false
        )
    }

    private func findBestCurrentSpace(for displayID: String) -> DesktopSpace? {
        // Identify the visible space for the specified monitor.
        if let liveID = SpaceHelper.getCurrentSpaceID(for: displayID),
           let space = spaceNameDict.first(where: { $0.id == liveID && $0.displayID == displayID }) {
            // Update cache while we're at it
            currentSpaceByDisplay[displayID] = liveID
            return space
        }

        // Fallback: check the per-display cache.
        if let cachedID = currentSpaceByDisplay[displayID],
           let space = spaceNameDict.first(where: { $0.id == cachedID && $0.displayID == displayID }) {
            return space
        }
        
        // Fallback: check if the globally focused space is on this display.
        if let global = spaceNameDict.first(where: { $0.id == currentSpaceUUID && $0.displayID == displayID }) {
            return global
        }
        
        // Fallback: default to the first available space on this monitor.
        return spaceNameDict.first(where: { $0.displayID == displayID })
    }

    @discardableResult
    private func proceedToSwitch(
        from current: DesktopSpace,
        on targetDisplayID: String,
        direction: Int,
        forceInstant: Bool = false
    ) -> SpaceSwitchRequestDisposition {
        // Use spaces from the TARGET display
        let displaySpaces = spaceNameDict
            .filter { $0.displayID == targetDisplayID }
            .sorted { $0.num < $1.num }
        
        guard let currentIndex = displaySpaces.firstIndex(of: current) else {
            return .unavailable
        }
        
        let targetIndex = currentIndex + direction
        guard targetIndex >= 0 && targetIndex < displaySpaces.count else {
            return .unavailable
        }
        
        let target = displaySpaces[targetIndex]
        return switchToSpace(target, forceInstant: forceInstant)
    }
}
