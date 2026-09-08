import AppKit
import Combine
import Foundation
import IOKit

extension GestureManager {

    // Analyzes touch frames to determine gesture intent.
    func handleTouches(touches: [MTTouch], numFingers: Int) {
        let now = Date().timeIntervalSince1970

        if numFingers == 0 {
            isWaitingForAllFingersToLift = false
            resetTrackingState()
            return
        }

        // After a recognized swipe, lifting only one or two fingers must not
        // arm another switch. Wait for a frame with no active contacts so a
        // long swipe cannot be mistaken for several independent gestures.
        guard !isWaitingForAllFingersToLift else { return }

        // Timeout Check.
        if now - lastTouchTime > touchTimeout {
            resetTrackingState()
        }
        lastTouchTime = now

        // Validate Finger Count.
        // Standard macOS space switching uses 3 or 4 fingers.
        // We will track BOTH of these counts for hiding purposes even if switchOverride fingerCount is different.
        let isHidingEligible = (numFingers == 3 || numFingers == 4)

        guard isHidingEligible else {
            resetTrackingState()
            return
        }

        // Validate Touches (Sanity Check).
        for touch in touches {
            if touch.normalizedVector.position.x < 0 || touch.normalizedVector.position.x > 1.0 {
                resetTrackingState()
                return
            }
        }

        // Initialize Start Position (Per Finger).
        if initialTouchPositions.isEmpty {
            for touch in touches {
                initialTouchPositions[touch.identifier] = touch.normalizedVector.position
            }
            return
        }

        // Validate Continuity.
        // Ensure the fingers on the pad match the IDs we started tracking
        let currentIDs = Set(touches.map { $0.identifier })
        let initialIDs = Set(initialTouchPositions.keys)

        if currentIDs != initialIDs {
            resetTrackingState()
            return
        }

        // Cooldown Check
        if now - lastSwitchTime < switchCooldown {
            return
        }

        // Calculate Average Deltas.
        var totalDX: Float = 0
        var totalDY: Float = 0

        for touch in touches {
            guard let startPos = initialTouchPositions[touch.identifier] else { continue }
            totalDX += (touch.normalizedVector.position.x - startPos.x)
            totalDY += (touch.normalizedVector.position.y - startPos.y)
        }

        let avgDX = totalDX / Float(numFingers)
        let avgDY = totalDY / Float(numFingers)

        // Pre-Trigger Logic: Overscroll Indicator.
        var isOverscroll = false

        // Only show overscroll indicator if we are the ones overriding the switch AND finger count matches
        if self.isEnabled && numFingers == self.fingerCount {
            // Only check horizontal dominance for indicator first
            if abs(avgDX) > abs(avgDY) {
                let direction: SwitchDirection = avgDX < 0 ? .next : .previous

                // Start the asynchronous boundary lookup as soon as intent is
                // clear, leaving enough time for it to finish before the
                // gesture reaches the trigger threshold.
                if abs(avgDX) >= consistencyThreshold {
                    scheduleBoundaryRefresh(direction: direction, mode: switchOverride)
                }

                let isNearSwitchThreshold = abs(avgDX) >= swipeThreshold * 0.75
                if isNearSwitchThreshold {
                    switch boundaryStatus(for: direction, now: now) {
                    case .boundary:
                        isOverscroll = true
                        let progress = Double(abs(avgDX) / swipeThreshold)
                        updateOverscrollIndicator(progress: progress, direction: direction)
                    case .unknown:
                        // The actual switch also requires the main queue. Wait
                        // for the already-scheduled lookup instead of treating
                        // an unresolved edge as an available destination.
                        return
                    case .available:
                        break
                    }
                }
            }
        }

        if isOverscroll {
            return
        } else {
            hideOverscrollIndicator()
        }

        // Trigger Logic.
        // Primary threshold check
        if abs(avgDX) > swipeThreshold {

            // Check for Horizontal Dominance (Must be more horizontal than vertical)
            if abs(avgDX) > abs(avgDY) {

                let direction: SwitchDirection = avgDX < 0 ? .next : .previous

                // Consistency Check (Anti-Tap Protection).
                // REQUIRE that EVERY finger has moved significantly in the target direction.
                // A tap usually has one finger anchor or fingers moving in opposition.
                var isConsistent = true

                for touch in touches {
                    guard let startPos = initialTouchPositions[touch.identifier] else { continue }
                    let dx = touch.normalizedVector.position.x - startPos.x

                    if direction == .next {
                        // Expect negative movement (Left Swipe)
                        // If any finger moved less than threshold (e.g. -0.01 or +0.1), fail.
                        if dx > -consistencyThreshold {
                            isConsistent = false
                            break
                        }
                    } else {
                        // Expect positive movement (Right Swipe)
                        if dx < consistencyThreshold {
                            isConsistent = false
                            break
                        }
                    }
                }

                if isConsistent {
                    // Lock Direction for this session
                    if lockedDirection == nil {
                        lockedDirection = direction
                    }

                    // Only act if matches locked direction
                    if lockedDirection == direction {
                        print("GestureManager: Triggered \(direction)")
                        isWaitingForAllFingersToLift = true
                        SpaceHelper.cancelPendingRawSpaceUUIDScan()

                        // Only perform the switch action if SwitchOverride is enabled AND finger count matches user preference
                        let performsSwitchOverride = numFingers == self.fingerCount && self.isEnabled

                        // Native macOS gestures still need an early label-hide
                        // notification. An overridden gesture hides previews
                        // at the actual SpaceHelper transaction boundary,
                        // avoiding a duplicate main-queue suppression pass.
                        if !performsSwitchOverride {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("SpaceSwitchRequested"), object: nil)
                        }

                        if performsSwitchOverride {
                            triggerSwitch(direction: direction)
                        }

                        // A new switch is armed only by the zero-contact frame
                        // at the start of handleTouches.
                        initialTouchPositions.removeAll()
                        lockedDirection = nil
                        invalidateBoundaryCache()
                    }
                }
            }
        }
    }

    func resetTrackingState() {
        initialTouchPositions.removeAll()
        lockedDirection = nil
        invalidateBoundaryCache()
        hideOverscrollIndicator()
    }

    private func invalidateBoundaryCache() {
        boundaryStateLock.lock()
        boundaryRefreshGeneration += 1
        let workItem = boundaryRefreshWorkItem
        boundaryRefreshWorkItem = nil
        cachedBoundaryDisplayID = nil
        cachedBoundaryDirection = nil
        cachedBoundaryMode = nil
        cachedBoundaryTime = 0
        boundaryStateLock.unlock()
        workItem?.cancel()
    }

}
