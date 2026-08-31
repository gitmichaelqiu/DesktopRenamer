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

        let disposition = SpaceHelper.switchToSpace(
            space.id,
            forceInstant: forceInstant,
            isManual: isManual
        )

        // A monitor retry may have been scheduled from an earlier stale
        // snapshot. Cancel it after a real switch starts or a request is
        // rejected; a queued request must leave the active transaction's
        // verification retry intact.
        if case .started = disposition {
            cancelSpaceChangeRetry()
        } else if case .unavailable = disposition {
            cancelSpaceChangeRetry()
        }
        return disposition
    }

    @objc func handleProgrammaticSwitchStarted(_ notification: Notification) {
        guard let spaceID = notification.userInfo?["spaceID"] as? String else {
            return
        }

        let update = { [weak self] in
            guard let self else { return }
            let isManual = notification.userInfo?["isManual"] as? Bool == true
            let generation = notification.userInfo?["generation"] as? UInt64

            // This notification also arrives for a transaction promoted from
            // the pending queue. Cancel any retry belonging to the previous
            // transition before the new generation can be observed.
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
                "programmatic switch transaction started: target=\(spaceID), manual=\(isManual), generation=\(generation.map(String.init) ?? "instant")"
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
              let confirmed = notification.userInfo?["confirmed"] as? Bool else {
            return
        }

        let update = { [weak self] in
            guard let self else { return }

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
                self.scheduleSpaceChangeRetry()
            }

            DiagnosticEventLog.shared.record(
                subsystem: "SpaceManager",
                level: confirmed ? "info" : "warning",
                "programmatic switch finished: generation=\(generation), confirmed=\(confirmed), retry chain reset"
            )
        }

        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }
    
    func switchToPreviousSpace(onDisplayID displayID: String? = nil, forceInstant: Bool? = nil) {
        let targetDisplayID = displayID ?? spaceNameDict.first(where: { $0.id == currentSpaceUUID })?.displayID ?? currentDisplayID
        if let current = findBestCurrentSpace(for: targetDisplayID) {
            proceedToSwitch(from: current, on: targetDisplayID, direction: -1, forceInstant: forceInstant ?? false)
        }
    }

    func switchToNextSpace(onDisplayID displayID: String? = nil, forceInstant: Bool? = nil) {
        let targetDisplayID = displayID ?? spaceNameDict.first(where: { $0.id == currentSpaceUUID })?.displayID ?? currentDisplayID
        if let current = findBestCurrentSpace(for: targetDisplayID) {
            proceedToSwitch(from: current, on: targetDisplayID, direction: 1, forceInstant: forceInstant ?? false)
        }
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

    private func proceedToSwitch(from current: DesktopSpace, on targetDisplayID: String, direction: Int, forceInstant: Bool = false) {
        // Use spaces from the TARGET display
        let displaySpaces = spaceNameDict
            .filter { $0.displayID == targetDisplayID }
            .sorted { $0.num < $1.num }
        
        guard let currentIndex = displaySpaces.firstIndex(of: current) else { return }
        
        let targetIndex = currentIndex + direction
        guard targetIndex >= 0 && targetIndex < displaySpaces.count else { return }
        
        let target = displaySpaces[targetIndex]
        switchToSpace(target, forceInstant: forceInstant)
    }
}
