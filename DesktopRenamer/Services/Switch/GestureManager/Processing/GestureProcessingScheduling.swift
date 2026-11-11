import AppKit
import Combine
import Foundation
import IOKit

private let maxPendingGestureSwitchSteps = 128

extension GestureManager {

    enum SwitchDirection: Equatable {
        case next
        case previous
    }

    enum BoundaryStatus {
        case unknown
        case boundary
        case available
    }

    func boundaryStatus(
        for direction: SwitchDirection,
        now: TimeInterval
    ) -> BoundaryStatus {
        let mode = switchOverride

        boundaryStateLock.lock()
        if cachedBoundaryDirection == direction,
           cachedBoundaryMode == mode,
           now - cachedBoundaryTime < boundaryCacheDuration {
            let status: BoundaryStatus = cachedBoundaryValue ? .boundary : .available
            boundaryStateLock.unlock()
            return status
        }
        boundaryStateLock.unlock()

        // The multitouch driver invokes handleTouches synchronously on its
        // callback thread. Do not call WindowServer or AppKit here: even one
        // boundary query can stall the callback immediately before the swipe
        // crosses the trigger threshold. Refresh the optional overscroll
        // affordance on the main queue and let the real switch request decide
        // whether an adjacent space exists.
        scheduleBoundaryRefresh(direction: direction, mode: mode)
        return .unknown
    }

    func scheduleBoundaryRefresh(
        direction: SwitchDirection,
        mode: SwitchOverrideMode
    ) {
        boundaryStateLock.lock()
        let now = Date().timeIntervalSince1970
        if cachedBoundaryDirection == direction,
           cachedBoundaryMode == mode,
           now - cachedBoundaryTime < boundaryCacheDuration {
            boundaryStateLock.unlock()
            return
        }
        guard boundaryRefreshWorkItem == nil else {
            boundaryStateLock.unlock()
            return
        }

        let generation = boundaryRefreshGeneration
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.switchOverride == mode else {
                self.boundaryStateLock.lock()
                if generation == self.boundaryRefreshGeneration {
                    self.boundaryRefreshWorkItem = nil
                }
                self.boundaryStateLock.unlock()
                return
            }

            let targetDisplayID: String?
            if mode == .cursor {
                let displayID = SpaceHelper.getCursorDisplayID()
                self.cachedBoundaryDisplayID = displayID
                targetDisplayID = displayID
            } else {
                targetDisplayID = nil
            }

            let value: Bool
            if direction == .previous {
                value = self.spaceManager?.isFirstSpace(onDisplayID: targetDisplayID) == true
            } else {
                value = self.spaceManager?.isLastSpace(onDisplayID: targetDisplayID) == true
            }

            self.boundaryStateLock.lock()
            guard generation == self.boundaryRefreshGeneration else {
                self.boundaryStateLock.unlock()
                return
            }
            self.boundaryRefreshWorkItem = nil
            self.cachedBoundaryDirection = direction
            self.cachedBoundaryMode = mode
            self.cachedBoundaryValue = value
            self.cachedBoundaryTime = Date().timeIntervalSince1970
            self.boundaryStateLock.unlock()
        }

        boundaryRefreshWorkItem = workItem
        boundaryStateLock.unlock()
        DispatchQueue.main.async(execute: workItem)
    }

    func updateOverscrollIndicator(progress: Double, direction: SwitchDirection) {
        let progressChanged = !isOverscrollIndicatorActive
            || lastOverscrollDirection != direction
            || abs(progress - lastOverscrollProgress) >= 0.04
        guard progressChanged else { return }

        isOverscrollIndicatorActive = true
        lastOverscrollDirection = direction
        lastOverscrollProgress = progress
        let edge: OverscrollIndicatorView.Edge = direction == .previous ? .leading : .trailing
        overscrollUpdateGeneration += 1
        let generation = overscrollUpdateGeneration
        overscrollUpdateWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  generation == self.overscrollUpdateGeneration,
                  self.isOverscrollIndicatorActive else {
                return
            }
            self.overscrollUpdateWorkItem = nil
            OverscrollOverlayManager.shared.update(progress: progress, edge: edge)
        }
        overscrollUpdateWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    func hideOverscrollIndicator() {
        guard isOverscrollIndicatorActive else { return }
        isOverscrollIndicatorActive = false
        lastOverscrollDirection = nil
        lastOverscrollProgress = 0
        overscrollUpdateGeneration += 1
        let generation = overscrollUpdateGeneration
        overscrollUpdateWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  generation == self.overscrollUpdateGeneration else {
                return
            }
            self.overscrollUpdateWorkItem = nil
            OverscrollOverlayManager.shared.hide()
        }
        overscrollUpdateWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    func triggerSwitch(direction: SwitchDirection) {
        DiagnosticEventLog.shared.record(
            subsystem: "GestureManager",
            level: "info",
            "triggerSwitch(\(direction))"
        )
        lastSwitchTime = Date().timeIntervalSince1970
        guard spaceManager != nil, self.isEnabled else { return }

        enqueueGestureSwitchRequest(direction)
    }

    private func enqueueGestureSwitchRequest(_ direction: SwitchDirection) {
        let stepCount = direction == .next ? 1 : -1
        var shouldSchedule = false
        let disposition: String
        let transactionActive: Bool
        let pendingSteps: Int

        gestureSwitchStateLock.lock()
        if isGestureSwitchActionScheduled
            || isGestureSwitchOperationInFlight
            || isGestureSwitchTransactionActive {
            accumulatePendingGestureSwitchSteps(stepCount)
            disposition = "queued"
            transactionActive = isGestureSwitchTransactionActive
        } else {
            isGestureSwitchActionScheduled = true
            shouldSchedule = true
            disposition = "scheduled"
            transactionActive = false
        }
        pendingSteps = pendingGestureSwitchStepCount
        gestureSwitchStateLock.unlock()

        DiagnosticEventLog.shared.record(
            subsystem: "GestureManager",
            level: "info",
            "gesture switch request \(disposition): direction=\(direction), transactionActive=\(transactionActive), pendingSteps=\(pendingSteps)"
        )

        if transactionActive {
            DispatchQueue.main.async {
                SpaceHelper.requestFastFollowUpSwitch()
            }
        }

        guard shouldSchedule else { return }
        let execute: () -> Void = { [weak self] in
            guard let self else { return }
            self.performScheduledGestureSwitch(initialStepCount: stepCount)
        }

        // The multitouch callback is delivered by the private driver on a
        // worker thread. Never block that callback while the main thread is
        // reconciling WindowServer state. The gate coalesces any additional
        // swipes received before this work item runs.
        if Thread.isMainThread {
            execute()
        } else {
            DispatchQueue.main.async(execute: execute)
        }
    }

    private func performScheduledGestureSwitch(initialStepCount: Int) {
        guard let stepCount = takeScheduledGestureStepCount(initialStepCount) else {
            return
        }
        guard stepCount != 0 else {
            completeGestureSwitchOperation(transactionStarted: false)
            return
        }
        let direction: SwitchDirection = stepCount > 0 ? .next : .previous

        guard let sm = spaceManager, self.isEnabled else {
            completeGestureSwitchOperation(transactionStarted: false)
            return
        }

        let isHoldingOption = NSEvent.modifierFlags.contains(.option)
        if moveWindowOnOption && isHoldingOption {
            // Window moves and fullscreen exit have their own asynchronous
            // cleanup and do not emit SpaceProgrammaticSwitchFinished.
            // Keep them outside the serialized space-switch gate.
            if sm.spaceNameDict.first(where: { $0.id == sm.currentSpaceUUID })?.isFullscreen == true {
                Task { @MainActor in
                    await Self.exitFullscreen()
                }
            } else {
                for _ in 0..<abs(stepCount) {
                    switch direction {
                    case .next:
                        sm.moveActiveWindowToNextSpace()
                    case .previous:
                        sm.moveActiveWindowToPreviousSpace()
                    }
                }
            }
            completeGestureSwitchOperation(transactionStarted: false)
            return
        }

        // Avoid doing the expensive adjacent-space lookup while another
        // transaction is settling. The relative step count is retained and
        // resolved against the live space only after promotion has completed.
        if SpaceHelper.isSwitching {
            retainGestureSwitchForActiveTransaction(stepCount)
            return
        }

        let targetDisplayID = (switchOverride == .cursor) ? SpaceHelper.getCursorDisplayID() : nil
        let disposition = SpaceHelper.switchByRelativeSteps(
            stepCount: stepCount,
            onDisplayID: targetDisplayID,
            isManual: true
        )
        print("GestureManager: Dispatched \(direction) x\(abs(stepCount)) (\(disposition))")

        let transactionStarted = disposition == .started || disposition == .queued
        DiagnosticEventLog.shared.record(
            subsystem: "GestureManager",
            level: "info",
            "gesture switch executed: direction=\(direction), disposition=\(disposition), transactionStarted=\(transactionStarted)"
        )
        completeGestureSwitchOperation(transactionStarted: transactionStarted)
    }

    private func takeScheduledGestureStepCount(_ initialStepCount: Int) -> Int? {
        gestureSwitchStateLock.lock()
        guard isGestureSwitchActionScheduled else {
            gestureSwitchStateLock.unlock()
            return nil
        }

        isGestureSwitchActionScheduled = false
        isGestureSwitchOperationInFlight = true
        let (combinedSteps, overflow) = initialStepCount.addingReportingOverflow(
            pendingGestureSwitchStepCount
        )
        let stepCount: Int
        if overflow {
            stepCount = initialStepCount > 0
                ? maxPendingGestureSwitchSteps
                : -maxPendingGestureSwitchSteps
        } else {
            stepCount = min(
                max(-maxPendingGestureSwitchSteps, combinedSteps),
                maxPendingGestureSwitchSteps
            )
        }
        pendingGestureSwitchStepCount = 0
        gestureSwitchStateLock.unlock()
        return stepCount
    }

    private func retainGestureSwitchForActiveTransaction(_ stepCount: Int) {
        gestureSwitchStateLock.lock()
        isGestureSwitchOperationInFlight = false
        isGestureSwitchTransactionActive = true
        accumulatePendingGestureSwitchSteps(stepCount)
        let pendingSteps = pendingGestureSwitchStepCount
        gestureSwitchStateLock.unlock()

        DiagnosticEventLog.shared.record(
            subsystem: "GestureManager",
            level: "info",
            "gesture switch deferred by active transaction: steps=\(stepCount), pendingSteps=\(pendingSteps)"
        )
        SpaceHelper.requestFastFollowUpSwitch()
        scheduleGestureSwitchResumeProbe()
    }

    private func accumulatePendingGestureSwitchSteps(_ stepCount: Int) {
        let (sum, overflow) = pendingGestureSwitchStepCount.addingReportingOverflow(stepCount)
        if overflow {
            pendingGestureSwitchStepCount = stepCount > 0
                ? maxPendingGestureSwitchSteps
                : -maxPendingGestureSwitchSteps
        } else {
            pendingGestureSwitchStepCount = min(
                max(-maxPendingGestureSwitchSteps, sum),
                maxPendingGestureSwitchSteps
            )
        }
    }

    private func completeGestureSwitchOperation(transactionStarted: Bool) {
        var nextStepCount: Int?

        gestureSwitchStateLock.lock()
        isGestureSwitchOperationInFlight = false
        isGestureSwitchTransactionActive = transactionStarted

        if !transactionStarted,
           !isGestureSwitchActionScheduled,
           pendingGestureSwitchStepCount != 0 {
            nextStepCount = pendingGestureSwitchStepCount
            pendingGestureSwitchStepCount = 0
            isGestureSwitchActionScheduled = true
        }
        gestureSwitchStateLock.unlock()

        if transactionStarted {
            scheduleGestureSwitchResumeProbe()
        } else if let nextStepCount {
            DiagnosticEventLog.shared.record(
                subsystem: "GestureManager",
                level: "info",
                "resuming coalesced gesture switch after rejected request: steps=\(nextStepCount)"
            )
            DispatchQueue.main.async { [weak self] in
                self?.performScheduledGestureSwitch(initialStepCount: nextStepCount)
            }
        } else {
            gestureSwitchResumeWorkItem?.cancel()
            gestureSwitchResumeWorkItem = nil
        }
    }

    func schedulePendingGestureSwitchResume() {
        // The completion notification is posted before SpaceHelper promotes
        // its own pending destination. Two main-queue turns put this check
        // after that promotion without adding a fixed delay to the switch.
        DispatchQueue.main.async { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.resumePendingGestureSwitchIfPossible()
            }
        }
    }

    private func scheduleGestureSwitchResumeProbe() {
        gestureSwitchResumeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.resumePendingGestureSwitchIfPossible()
        }
        gestureSwitchResumeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    private func resumePendingGestureSwitchIfPossible() {
        guard !SpaceHelper.isSwitching,
              !SpaceHelper.isProgrammaticSwitchPromotionPending else {
            scheduleGestureSwitchResumeProbe()
            return
        }

        var nextStepCount: Int?
        gestureSwitchStateLock.lock()
        guard isGestureSwitchTransactionActive,
              !isGestureSwitchActionScheduled,
              !isGestureSwitchOperationInFlight else {
            gestureSwitchStateLock.unlock()
            return
        }

        isGestureSwitchTransactionActive = false
        if pendingGestureSwitchStepCount != 0 {
            nextStepCount = pendingGestureSwitchStepCount
            pendingGestureSwitchStepCount = 0
            isGestureSwitchActionScheduled = true
        }
        gestureSwitchStateLock.unlock()

        gestureSwitchResumeWorkItem?.cancel()
        gestureSwitchResumeWorkItem = nil

        guard let nextStepCount else {
            DiagnosticEventLog.shared.record(
                subsystem: "GestureManager",
                level: "info",
                "gesture switch gate idle: no pending direction"
            )
            return
        }

        DiagnosticEventLog.shared.record(
            subsystem: "GestureManager",
            level: "info",
            "promoting coalesced gesture direction: steps=\(nextStepCount)"
        )
        DispatchQueue.main.async { [weak self] in
            self?.performScheduledGestureSwitch(initialStepCount: nextStepCount)
        }
    }

    @MainActor
    static func exitFullscreen() async {
        guard let activeInfo = SpaceHelper.getActiveWindowInfo() else { return }

        var axWindow = SpaceHelper.getAXWindow(id: activeInfo.id, pid: activeInfo.pid)
        if axWindow == nil {
            if let app = NSRunningApplication(processIdentifier: activeInfo.pid) {
                app.activate(options: .activateIgnoringOtherApps)
                try? await Task.sleep(nanoseconds: 400_000_000)
                axWindow = SpaceHelper.getAXWindow(id: activeInfo.id, pid: activeInfo.pid)
            }
        }
        if let targetAXWindow = axWindow {
            AXUIElementSetAttributeValue(targetAXWindow, "AXFullScreen" as CFString, false as CFTypeRef)
        }
    }
}
