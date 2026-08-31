import AppKit
import Combine
import Foundation
import IOKit

extension GestureManager {

    // Analyzes touch frames to determine gesture intent.
    func handleTouches(touches: [MTTouch], numFingers: Int) {
        let now = Date().timeIntervalSince1970

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

                // Determine target display to check boundaries
                var targetDisplayID: String? = nil
                if self.switchOverride == .cursor {
                    targetDisplayID = SpaceHelper.getCursorDisplayID()
                }
                // If .activeWindow, we leave nil, relying on SpaceManager's default context

                if direction == .previous {
                    if spaceManager?.isFirstSpace(onDisplayID: targetDisplayID) == true {
                        isOverscroll = true
                        // avgDX is positive here.
                        let progress = Double(abs(avgDX) / swipeThreshold)
                        // Previous means going "Left". Wall is on Left. Edge is .leading.
                        DispatchQueue.main.async {
                            OverscrollOverlayManager.shared.update(progress: progress, edge: .leading)
                        }
                    }
                } else {  // .next
                    if spaceManager?.isLastSpace(onDisplayID: targetDisplayID) == true {
                        isOverscroll = true
                        // avgDX is negative here.
                        let progress = Double(abs(avgDX) / swipeThreshold)
                        // Next means going "Right". Wall is on Right. Edge is .trailing.
                        DispatchQueue.main.async {
                            OverscrollOverlayManager.shared.update(progress: progress, edge: .trailing)
                        }
                    }
                }
            }
        }

        if isOverscroll {
            return
        } else {
            DispatchQueue.main.async {
                OverscrollOverlayManager.shared.hide()
            }
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

                        // Fire a nil-target SpaceSwitchRequested so SpaceLabelManager can hide all active Preview Labels.
                        // SpaceHelper owns its programmatic-switch timestamp; the gesture marker must not
                        // overwrite the active transaction's identity while WindowServer is settling.
                        NotificationCenter.default.post(
                            name: NSNotification.Name("SpaceSwitchRequested"), object: nil)

                        // Only perform the switch action if SwitchOverride is enabled AND finger count matches user preference
                        if numFingers == self.fingerCount && self.isEnabled {
                            triggerSwitch(direction: direction)
                        }

                        // CRITICAL: Reset anchors to current position to allow consecutive swipes
                        initialTouchPositions.removeAll()
                        for touch in touches {
                            initialTouchPositions[touch.identifier] =
                                touch.normalizedVector.position
                        }
                    }
                }
            }
        }
    }

    func resetTrackingState() {
        initialTouchPositions.removeAll()
        lockedDirection = nil

        DispatchQueue.main.async {
            OverscrollOverlayManager.shared.hide()
        }
    }

    enum SwitchDirection {
        case next
        case previous
    }

    func triggerSwitch(direction: SwitchDirection) {
        DiagnosticEventLog.shared.record(subsystem: "GestureManager", level: "info", "triggerSwitch(\(direction))")
        lastSwitchTime = Date().timeIntervalSince1970
        guard let sm = spaceManager, self.isEnabled else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let isHoldingOption = NSEvent.modifierFlags.contains(.option)
            if self.moveWindowOnOption && isHoldingOption {
                // If the current space is a fullscreen app, just exit fullscreen.
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
            } else {
                let targetDisplayID = (self.switchOverride == .cursor) ? SpaceHelper.getCursorDisplayID() : nil
                switch direction {
                case .next:
                    sm.switchToNextSpace(onDisplayID: targetDisplayID)
                case .previous:
                    sm.switchToPreviousSpace(onDisplayID: targetDisplayID)
                }
            }
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
