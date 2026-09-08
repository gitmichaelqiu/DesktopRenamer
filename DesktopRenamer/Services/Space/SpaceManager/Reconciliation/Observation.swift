import AppKit
import Foundation
import SwiftUI
import WidgetKit


extension SpaceManager {


    /// WindowServer can briefly report a neighboring space while a synthetic
    /// gesture is still settling. The transaction coordinator is authoritative
    /// during that interval; a timestamp is not sufficient because the retry
    /// window can outlive the manual-attribution window.
    func shouldIgnoreStaleTransactionObservation(_ observedSpaceID: String, source: String) -> Bool {
        guard SpaceHelper.isSwitching,
              let activeTargetSpaceID = SpaceHelper.activeProgrammaticSwitchTargetSpaceID,
              observedSpaceID != activeTargetSpaceID else {
            return false
        }

        let generation = SpaceHelper.activeProgrammaticSwitchGeneration.map(String.init) ?? "nil"
        print("SpaceManager: Stale space \(observedSpaceID) detected during active switch to \(activeTargetSpaceID) (source: \(source)). Ignoring.")
        DiagnosticEventLog.shared.record(
            subsystem: "SpaceManager",
            level: "info",
            "Ignoring stale transaction observation: generation=\(generation), observed=\(observedSpaceID), target=\(activeTargetSpaceID), source=\(source)"
        )

        // Do not schedule a SpaceManager retry while the transaction is still
        // active. The transaction's generation-scoped completion or timeout
        // owns recovery; a retry created here can outlive the transaction and
        // publish the stale observation that was just rejected.
        return true
    }

    /// Handles the active-space notification before the delayed raw-space scan
    /// runs. This is the only path allowed to release a confirmed destination
    /// fence: monitor and retry reads can repeat an old WindowServer snapshot,
    /// while an ordered active-space notification represents a new transition.
    func handleAuthoritativeSpaceChange(_ spacesByDisplay: [String: String]) {
        let traceID = SpaceHelper.debugTraceID()
        SpaceHelper.debugTrace(
            traceID,
            "manager authoritative notification received snapshot=\(SpaceHelper.debugFormatSpaceMap(spacesByDisplay)), modelCurrent=\(currentSpaceUUID), fences=\(confirmedSpaceObservationFence.confirmations.mapValues { $0.spaceID + "/g" + String($0.generation) })"
        )
        let update = { [weak self] in
            guard let self else { return }
            let liveSpacesByDisplay = SpaceHelper.getCurrentSpaceIDsByDisplay()

            for (displayID, spaceID) in spacesByDisplay {
                guard let confirmation = self.confirmedSpaceObservationFence.confirmation(
                    for: displayID
                ) else {
                    SpaceHelper.debugTrace(
                        traceID,
                        "manager authoritative display=\(displayID), space=\(spaceID), decision=no-fence"
                    )
                    continue
                }

                let liveSpaceID = liveSpacesByDisplay[displayID]
                if spaceID == confirmation.spaceID,
                   liveSpaceID == confirmation.spaceID {
                    self.currentSpaceByDisplay[displayID] = spaceID
                    SpaceHelper.debugTrace(
                        traceID,
                        "manager authoritative display=\(displayID), space=\(spaceID), decision=confirm-destination generation=\(confirmation.generation)"
                    )
                    continue
                }

                // Use a fresh WindowServer read to distinguish a genuinely
                // newer Space from a delayed active-space notification. This
                // also handles the case where the notification for the
                // confirmed destination was lost.
                guard self.confirmedSpaceObservationFence.clearForExternalObservation(
                    displayID: displayID,
                    spaceID: liveSpaceID ?? spaceID,
                    liveSpaceID: liveSpaceID
                ) else {
                    SpaceHelper.debugTrace(
                        traceID,
                        "manager authoritative display=\(displayID), space=\(spaceID), live=\(liveSpaceID ?? "nil"), decision=ignore-confirmed-fence confirmed=\(confirmation.spaceID)"
                    )
                    DiagnosticEventLog.shared.record(
                        subsystem: "SpaceManager",
                        level: "info",
                        "Ignoring active-space observation behind confirmed destination: display=\(displayID), observed=\(spaceID), live=\(liveSpaceID ?? "nil"), confirmed=\(confirmation.spaceID)"
                    )
                    continue
                }

                DiagnosticEventLog.shared.record(
                    subsystem: "SpaceManager",
                    level: "info",
                    "Cleared confirmed-space fence after external transition: display=\(displayID), observed=\(liveSpaceID ?? spaceID), previous=\(confirmation.spaceID)"
                )
                if self.spaceChangeRetryDisplayID == displayID {
                    self.cancelSpaceChangeRetry()
                }
                SpaceHelper.debugTrace(
                    traceID,
                    "manager authoritative display=\(displayID), space=\(liveSpaceID ?? spaceID), decision=clear-fence previous=\(confirmation.spaceID)"
                )
            }
        }

        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }

    /// Returns the space that label windows should treat as current for a
    /// display. A confirmed programmatic destination takes precedence only
    /// while the independent live query still agrees or is unavailable.
    func currentSpaceIDForLabels(onDisplayID displayID: String) -> String? {
        currentSpaceIDsForLabels()[displayID]
    }

    /// Reads the visible Space for every display once, then overlays any
    /// confirmed programmatic destinations. Label windows otherwise perform
    /// several independent CGS reads during one refresh and can combine an
    /// old display snapshot with a new one.
    func currentSpaceIDsForLabels() -> [String: String] {
        var currentSpaceIDs = SpaceHelper.getCurrentSpaceIDsByDisplay()
        for displayID in Set(spaceNameDict.map(\.displayID)) {
            if let confirmation = confirmedSpaceObservationFence.confirmation(for: displayID) {
                // The fence may outlive the active-space notification. Only
                // overlay it while the live query is missing or still agrees;
                // a different live Space must remain visible to labels.
                if currentSpaceIDs[displayID] == nil
                    || currentSpaceIDs[displayID] == confirmation.spaceID {
                    currentSpaceIDs[displayID] = confirmation.spaceID
                }
            } else if currentSpaceIDs[displayID] == nil,
                      let cachedSpaceID = currentSpaceByDisplay[displayID] {
                currentSpaceIDs[displayID] = cachedSpaceID
            }
        }
        return currentSpaceIDs
    }

    /// Resolves one visible space per display while preserving a confirmed
    /// destination over a stale WindowServer snapshot. This keeps all label
    /// refresh paths on the same authority as SpaceManager reconciliation.
    func visibleSpaceIDsForLabels() -> Set<String> {
        let currentSpaceIDs = currentSpaceIDsForLabels()
        var visibleSpaceIDs = Set(currentSpaceIDs.values)
        if visibleSpaceIDs.isEmpty {
            visibleSpaceIDs = SpaceHelper.getVisibleSystemSpaceIDs()
        }
        let spacesByDisplay = Dictionary(grouping: spaceNameDict, by: \.displayID)

        for (displayID, spaces) in spacesByDisplay {
            guard let currentSpaceID = currentSpaceIDs[displayID] else {
                continue
            }
            visibleSpaceIDs.subtract(spaces.map(\.id))
            visibleSpaceIDs.insert(currentSpaceID)
        }

        return visibleSpaceIDs
    }

    func refreshConnectedDisplays() {
        self.connectedDisplayUUIDs = Set(SpaceHelper.getAllDisplayUUIDs().map { $0.uppercased() })
        // print("SpaceManager: Refreshed connected displays: \(connectedDisplayUUIDs)")
    }
    
    func refreshSpaceState() {
        guard !isSystemSleeping else { return }
        SpaceHelper.getRawSpaceUUID { [weak self] rawUUID, isDesktop, ncCnt, displayID in
            self?.handleSpaceChange(rawUUID, isDesktop: isDesktop, ncCount: ncCnt, displayID: displayID, source: "Refresh")
        }
    }
    
}
