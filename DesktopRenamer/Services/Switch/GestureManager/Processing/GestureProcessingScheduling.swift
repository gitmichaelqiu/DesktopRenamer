import AppKit
import Combine
import Foundation
import IOKit

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
        var shouldSchedule = false
        let disposition: String
        let transactionActive: Bool
        let pendingCount: Int

        gestureSwitchStateLock.lock()
        if isGestureSwitchActionScheduled
            || isGestureSwitchOperationInFlight
            || isGestureSwitchTransactionActive {
            pendingGestureSwitchDirections.append(direction)
            disposition = "queued"
            transactionActive = isGestureSwitchTransactionActive
        } else {
            isGestureSwitchActionScheduled = true
            shouldSchedule = true
            disposition = "scheduled"
            transactionActive = false
        }
        pendingCount = pendingGestureSwitchDirections.count
        gestureSwitchStateLock.unlock()

        DiagnosticEventLog.shared.record(
            subsystem: "GestureManager",
            level: "info",
            "gesture switch request \(disposition): direction=\(direction), transactionActive=\(transactionActive), pending=\(pendingCount)"
        )

        if transactionActive {
            DispatchQueue.main.async {
                SpaceHelper.requestFastFollowUpSwitch()
            }
        }

        guard shouldSchedule else { return }
        let execute: () -> Void = { [weak self] in
            guard let self else { return }
            self.performScheduledGestureSwitch(initialDirection: direction)
        }

        // The multitouch callback is delivered by the private driver on a
        // worker thread. Never block that callback while the main thread is
        // reconciling WindowServer state. The gate preserves ordering and
        // queues any additional directions before this work item runs.
        if Thread.isMainThread {
            execute()
        } else {
            DispatchQueue.main.async(execute: execute)
        }
    }

    private func performScheduledGestureSwitch(initialDirection: SwitchDirection) {
        guard let direction = takeScheduledGestureDirection(initialDirection) else {
            return
        }

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
                switch direction {
                case .next:
                    sm.moveActiveWindowToNextSpace()
                case .previous:
                    sm.moveActiveWindowToPreviousSpace()
                }
            }
            completeGestureSwitchOperation(transactionStarted: false)
            return
        }

        // Avoid doing the expensive adjacent-space lookup while another
        // transaction is settling. The direction is retained and resolved
        // against the live space only after promotion has completed.
        if SpaceHelper.isSwitching {
            retainGestureSwitchForActiveTransaction(direction)
            return
        }

        let targetDisplayID = (switchOverride == .cursor) ? SpaceHelper.getCursorDisplayID() : nil
        let step = direction == .next ? 1 : -1
        let disposition = SpaceHelper.switchToAdjacentSpace(
            direction: step,
            onDisplayID: targetDisplayID,
            isManual: true
        )
        print("GestureManager: Dispatched \(direction) (\(disposition))")

        let transactionStarted = disposition == .started || disposition == .queued
        DiagnosticEventLog.shared.record(
            subsystem: "GestureManager",
            level: "info",
            "gesture switch executed: direction=\(direction), disposition=\(disposition), transactionStarted=\(transactionStarted)"
        )
        completeGestureSwitchOperation(transactionStarted: transactionStarted)
    }

    private func takeScheduledGestureDirection(_ initialDirection: SwitchDirection) -> SwitchDirection? {
        gestureSwitchStateLock.lock()
        guard isGestureSwitchActionScheduled else {
            gestureSwitchStateLock.unlock()
            return nil
        }

        isGestureSwitchActionScheduled = false
        isGestureSwitchOperationInFlight = true
        gestureSwitchStateLock.unlock()
        return initialDirection
    }

    private func retainGestureSwitchForActiveTransaction(_ direction: SwitchDirection) {
        gestureSwitchStateLock.lock()
        isGestureSwitchOperationInFlight = false
        isGestureSwitchTransactionActive = true
        // This operation was already accepted before any directions currently
        // in the queue, so keep it at the front when an external SpaceHelper
        // transaction temporarily prevents it from starting.
        pendingGestureSwitchDirections.insert(direction, at: 0)
        gestureSwitchStateLock.unlock()

        DiagnosticEventLog.shared.record(
            subsystem: "GestureManager",
            level: "info",
            "gesture switch deferred by active transaction: direction=\(direction)"
        )
        SpaceHelper.requestFastFollowUpSwitch()
        scheduleGestureSwitchResumeProbe()
    }

    private func completeGestureSwitchOperation(transactionStarted: Bool) {
        var nextDirection: SwitchDirection?

        gestureSwitchStateLock.lock()
        isGestureSwitchOperationInFlight = false
        isGestureSwitchTransactionActive = transactionStarted

        if !transactionStarted,
           !isGestureSwitchActionScheduled,
           !pendingGestureSwitchDirections.isEmpty {
            let pendingDirection = pendingGestureSwitchDirections.removeFirst()
            isGestureSwitchActionScheduled = true
            nextDirection = pendingDirection
        }
        gestureSwitchStateLock.unlock()

        if transactionStarted {
            scheduleGestureSwitchResumeProbe()
        } else if let nextDirection {
            DiagnosticEventLog.shared.record(
                subsystem: "GestureManager",
                level: "info",
                "resuming pending gesture switch after \(transactionStarted ? "transaction" : "rejected request"): direction=\(nextDirection)"
            )
            DispatchQueue.main.async { [weak self] in
                self?.performScheduledGestureSwitch(initialDirection: nextDirection)
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

        var nextDirection: SwitchDirection?
        gestureSwitchStateLock.lock()
        guard isGestureSwitchTransactionActive,
              !isGestureSwitchActionScheduled,
              !isGestureSwitchOperationInFlight else {
            gestureSwitchStateLock.unlock()
            return
        }

        isGestureSwitchTransactionActive = false
        if !pendingGestureSwitchDirections.isEmpty {
            let pendingDirection = pendingGestureSwitchDirections.removeFirst()
            isGestureSwitchActionScheduled = true
            nextDirection = pendingDirection
        }
        gestureSwitchStateLock.unlock()

        gestureSwitchResumeWorkItem?.cancel()
        gestureSwitchResumeWorkItem = nil

        guard let nextDirection else {
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
            "promoting pending gesture direction: direction=\(nextDirection)"
        )
        DispatchQueue.main.async { [weak self] in
            self?.performScheduledGestureSwitch(initialDirection: nextDirection)
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
