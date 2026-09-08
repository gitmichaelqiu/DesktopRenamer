import AppKit
import Foundation
import SwiftUI
import WidgetKit


extension SpaceManager {

    func scheduleMonitorSpaceChange(
        rawUUID: String,
        isDesktop: Bool,
        ncCount: Int,
        displayID: String
    ) {
        pendingMonitorSpaceChange = (rawUUID, isDesktop, ncCount, displayID)
        let traceID = SpaceHelper.debugTraceID()
        SpaceHelper.debugTrace(
            traceID,
            "monitor observation queued raw=\(rawUUID), display=\(displayID), existingWork=\(monitorSpaceChangeWorkItem != nil), nextGeneration=\(monitorSpaceChangeGeneration + 1)"
        )
        guard monitorSpaceChangeWorkItem == nil else {
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceManager",
                level: "info",
                "coalesced monitor observation: display=\(displayID)"
            )
            return
        }

        monitorSpaceChangeGeneration += 1
        let generation = monitorSpaceChangeGeneration
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  generation == self.monitorSpaceChangeGeneration else {
                return
            }

            self.monitorSpaceChangeWorkItem = nil
            guard let pending = self.pendingMonitorSpaceChange else { return }
            self.pendingMonitorSpaceChange = nil
            SpaceHelper.debugTrace(
                traceID,
                "monitor observation executing generation=\(generation), raw=\(pending.rawUUID), display=\(pending.displayID)"
            )
            self.handleSpaceChange(
                pending.rawUUID,
                isDesktop: pending.isDesktop,
                ncCount: pending.ncCount,
                displayID: pending.displayID,
                source: "Monitor",
                bypassMonitorCoalescing: true
            )
        }

        monitorSpaceChangeWorkItem = workItem
        // A single short run-loop interval absorbs duplicate WindowServer
        // notifications but does not add a perceptible delay to a gesture.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: workItem)
    }

    func cancelPendingMonitorSpaceChange() {
        if monitorSpaceChangeWorkItem != nil || pendingMonitorSpaceChange != nil {
            SpaceHelper.debugTrace(
                SpaceHelper.debugTraceID(),
                "monitor observation canceled generation=\(monitorSpaceChangeGeneration), pendingRaw=\(pendingMonitorSpaceChange?.rawUUID ?? "nil"), pendingDisplay=\(pendingMonitorSpaceChange?.displayID ?? "nil")"
            )
        }
        monitorSpaceChangeGeneration += 1
        monitorSpaceChangeWorkItem?.cancel()
        monitorSpaceChangeWorkItem = nil
        pendingMonitorSpaceChange = nil
    }

    func scheduleSpaceChangeRetry(displayID: String? = nil) {
        guard !isSystemSleeping else { return }
        guard spaceChangeRetryCount < maxSpaceChangeRetries else { return }
        if let displayID {
            spaceChangeRetryDisplayID = displayID
        }
        spaceChangeRetryWorkItem?.cancel()
        spaceChangeRetryGeneration += 1
        let generation = spaceChangeRetryGeneration

        let delay = TimeInterval(0.3 + Double(spaceChangeRetryCount) * 0.2)
        spaceChangeRetryCount += 1
        let traceID = SpaceHelper.debugTraceID()
        SpaceHelper.debugTrace(
            traceID,
            "retry scheduled generation=\(generation), display=\(spaceChangeRetryDisplayID ?? "nil"), count=\(spaceChangeRetryCount), delay=\(String(format: "%.2f", delay)), fence=\(spaceChangeRetryDisplayID.flatMap { confirmedSpaceObservationFence.confirmation(for: $0)?.spaceID } ?? "nil")"
        )

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self,
                  generation == self.spaceChangeRetryGeneration else { return }
            SpaceHelper.debugTrace(
                traceID,
                "retry executing generation=\(generation), display=\(self.spaceChangeRetryDisplayID ?? "nil")"
            )
            self.performRetryDetection(generation: generation)
        }
        spaceChangeRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func cancelSpaceChangeRetry() {
        spaceChangeRetryWorkItem?.cancel()
        spaceChangeRetryWorkItem = nil
        spaceChangeRetryGeneration += 1
        spaceChangeRetryCount = 0
        spaceChangeRetryObservedSpaceID = nil
        spaceChangeRetryObservedPasses = 0
        spaceChangeRetryDisplayID = nil
    }

    private func performRetryDetection(generation: Int) {
        guard !isSystemSleeping,
              generation == spaceChangeRetryGeneration else { return }
        let traceID = SpaceHelper.debugTraceID()
        guard let cgsState = SpaceHelper.getSystemState(onDisplayID: spaceChangeRetryDisplayID) else {
            SpaceHelper.debugTrace(traceID, "retry decision=reschedule-no-cgs-state generation=\(generation)")
            scheduleSpaceChangeRetry()
            return
        }

        // A WindowServer query may overlap a newer monitor observation or a
        // newly started switch. Cancellation cannot stop a work item that is
        // already executing, so reject its result again after the read.
        guard generation == spaceChangeRetryGeneration else { return }
        let liveSpaceID = SpaceHelper.getCurrentSpaceID(for: cgsState.displayID)
        SpaceHelper.debugTrace(
            traceID,
            "retry snapshot generation=\(generation), cgsCurrent=\(cgsState.currentUUID), display=\(cgsState.displayID), live=\(liveSpaceID ?? "nil"), fence=\(confirmedSpaceObservationFence.confirmation(for: cgsState.displayID)?.spaceID ?? "nil"), modelCurrent=\(currentSpaceUUID)"
        )

        if confirmedSpaceObservationFence.shouldIgnore(
            displayID: cgsState.displayID,
            observedSpaceID: cgsState.currentUUID,
            liveSpaceID: liveSpaceID
        ) {
            let confirmedSpaceID = confirmedSpaceObservationFence.confirmation(
                for: cgsState.displayID
            )?.spaceID ?? "nil"
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceManager",
                level: "info",
                "Ignoring retry behind confirmed destination: display=\(cgsState.displayID), observed=\(cgsState.currentUUID), live=\(liveSpaceID ?? "nil"), confirmed=\(confirmedSpaceID)"
            )
            if spaceChangeRetryDisplayID == cgsState.displayID {
                cancelSpaceChangeRetry()
            }
            SpaceHelper.debugTrace(
                traceID,
                "retry decision=discard-behind-fence observed=\(cgsState.currentUUID), live=\(liveSpaceID ?? "nil"), confirmed=\(confirmedSpaceID)"
            )
            return
        }

        if shouldIgnoreStaleTransactionObservation(cgsState.currentUUID, source: "Retry") {
            SpaceHelper.debugTrace(traceID, "retry decision=discard-active-transaction observed=\(cgsState.currentUUID)")
            return
        }

        // A retry is specifically for a stale or incomplete monitor event.
        // Do not reconcile from a snapshot whose current space is not one of
        // the spaces WindowServer currently exposes as visible. During Dock
        // activation and animated switches these two CGS reads can briefly
        // disagree; accepting the older snapshot would move the model back to
        // the source space and reopen its preview label.
        let visibleSpaceIDs = SpaceHelper.getVisibleSystemSpaceIDs()
        guard generation == spaceChangeRetryGeneration else { return }
        guard !visibleSpaceIDs.isEmpty,
              visibleSpaceIDs.contains(cgsState.currentUUID) else {
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceManager",
                level: "info",
                "Ignoring inconsistent space retry: current=\(cgsState.currentUUID), visible=\(visibleSpaceIDs.sorted())"
            )
            scheduleSpaceChangeRetry()
            SpaceHelper.debugTrace(
                traceID,
                "retry decision=reschedule-not-visible current=\(cgsState.currentUUID), visible=\(visibleSpaceIDs.sorted())"
            )
            return
        }

        let independentlyObservedSpaceID = SpaceHelper.getCurrentSpaceID(for: cgsState.displayID)
        guard generation == spaceChangeRetryGeneration else { return }
        if let independentlyObservedSpaceID,
           independentlyObservedSpaceID != cgsState.currentUUID {
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceManager",
                level: "info",
                "Ignoring inconsistent space retry read: state=\(cgsState.currentUUID), independent=\(independentlyObservedSpaceID), display=\(cgsState.displayID)"
            )
            scheduleSpaceChangeRetry()
            SpaceHelper.debugTrace(
                traceID,
                "retry decision=reschedule-live-mismatch state=\(cgsState.currentUUID), independent=\(independentlyObservedSpaceID)"
            )
            return
        }

        if spaceChangeRetryObservedSpaceID == cgsState.currentUUID {
            spaceChangeRetryObservedPasses += 1
        } else {
            spaceChangeRetryObservedSpaceID = cgsState.currentUUID
            spaceChangeRetryObservedPasses = 1
        }

        guard spaceChangeRetryObservedPasses >= 2 else {
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceManager",
                level: "info",
                "Waiting for stable space retry candidate: current=\(cgsState.currentUUID), pass=\(spaceChangeRetryObservedPasses)/2"
            )
            scheduleSpaceChangeRetry()
            SpaceHelper.debugTrace(
                traceID,
                "retry decision=reschedule-unstable candidate=\(cgsState.currentUUID), pass=\(spaceChangeRetryObservedPasses)/2"
            )
            return
        }

        // Do not let an old retry commit after a transaction-start observer or
        // a newer retry chain invalidated it during the stability checks.
        guard generation == spaceChangeRetryGeneration else { return }

        if currentSpaceUUID != cgsState.currentUUID {
            handleSpaceChange(cgsState.currentUUID, isDesktop: true, ncCount: 0,
                             displayID: cgsState.displayID, source: "Retry")
        }
        cancelSpaceChangeRetry()
        SpaceHelper.debugTrace(
            traceID,
            "retry decision=complete generation=\(generation), candidate=\(cgsState.currentUUID), modelCurrentNow=\(currentSpaceUUID)"
        )
    }

    // Debounces widget updates to throttle system load.
    func scheduleWidgetUpdate() {
        widgetUpdateWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.performWidgetUpdate()
        }
        
        widgetUpdateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }
    
    struct WidgetSpace: Codable {
        let id: String
        let name: String
        let num: Int
        let displayID: String
    }

    private func performWidgetUpdate() {
        guard let defaults = UserDefaults(suiteName: SpaceManager.appGroupId) else { return }
        
        let name = getSpaceName(currentSpaceUUID)
        let num = getSpaceNum(currentSpaceUUID)
        // Check if current space is desktop
        let isDesktop = !(spaceNameDict.first(where: { $0.id == currentSpaceUUID })?.isFullscreen ?? false)
        
        // Prepare structured data for Widget
        let sortedSpaces = spaceNameDict.sorted {
            if $0.displayID != $1.displayID {
                return $0.displayID < $1.displayID
            }
            return $0.num < $1.num
        }
        
        let widgetSpaces = sortedSpaces.map { space in
            let defaultName = space.isFullscreen ? (space.appName ?? "Fullscreen") : String(format: NSLocalizedString("Space.DefaultName", comment: ""), space.num)
            return WidgetSpace(
                id: space.id,
                name: space.customName.isEmpty ? defaultName : space.customName,
                num: space.num,
                displayID: space.displayID
            )
        }
        
        if let data = try? JSONEncoder().encode(widgetSpaces) {
            defaults.set(data, forKey: "widget_spacesData")
        }
        
        // Some simple fields for basic widgets to use
        let allSpaceNames = sortedSpaces.map { space in
            if !space.customName.isEmpty { return space.customName }
            return space.isFullscreen ? (space.appName ?? "Fullscreen") : "\(space.num)"
        }
        defaults.set(allSpaceNames, forKey: "widget_allSpaces")
        
        defaults.set(name, forKey: "widget_spaceName")
        defaults.set(num, forKey: "widget_spaceNum")
        defaults.set(isDesktop, forKey: "widget_isDesktop")
        defaults.set(currentSpaceUUID, forKey: "widget_currentSpaceUUID")

        WidgetCenter.shared.reloadAllTimelines()
    }
    
    func prepareForTermination() {
        wakeRecoveryWorkItem?.cancel()
        spaceChangeRetryWorkItem?.cancel()
        stopPeriodicSpaceLayoutCheck()
        SpaceHelper.stopMonitoring()
        DistributedNotificationCenter.default().postNotificationName(SpaceAPI.apiToggleNotification, object: nil, userInfo: ["isEnabled": false], deliverImmediately: true)
    }
}
