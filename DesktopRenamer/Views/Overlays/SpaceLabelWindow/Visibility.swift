import Cocoa
import Combine
import QuartzCore

extension SpaceLabelWindow {

    func updateVisibility(animated: Bool) {
        pendingVisibilityTask?.cancel()
        pendingVisibilityTask = nil

        guard findTargetScreen() != nil else {
            self.alphaValue = 0.0
            self.orderOut(nil)
            return
        }

        let labelsEnabled = isActiveMode
            ? (labelManager?.showActiveLabels ?? true)
            : (labelManager?.showPreviewLabels ?? true)
        guard labelsEnabled else {
            pendingVisibilityTask?.cancel()
            pendingVisibilityTask = nil
            alphaValue = 0.0
            contentView?.alphaValue = 0.0
            orderOut(nil)
            return
        }

        var isVisuallyVisible = false
        if isActiveMode {
            isVisuallyVisible = labelManager?.showActiveLabels ?? true
        } else {
            isVisuallyVisible = labelManager?.showPreviewLabels ?? true
        }
        
        // Robust Fix: Suppress all labels during space transitions when hideWhenSwitching is enabled.
        // Previously only preview labels were suppressed, but the active label also needs to stay
        // hidden — switchByActivatingOwnWindow may have already ordered it front and made it key.
        // Use a longer cooling period on multi-display setups where animations
        // (especially on external displays) may take longer to complete.
        let coolingPeriod: TimeInterval = 0.3
        if labelManager?.hideWhenSwitching == true {
            let now = Date().timeIntervalSince1970
            let timeSinceSwitch = now - SpaceHelper.lastProgrammaticSwitchTime
            if timeSinceSwitch < coolingPeriod {
                print("SpaceLabelWindow[\(self.spaceId)]: Suppressing label visibility during switch transition (\(String(format: "%.2f", timeSinceSwitch))s).")
                isVisuallyVisible = false
                scheduleVisibilityRetry(delay: coolingPeriod - timeSinceSwitch + 0.1)
            }
        }

        print("SpaceLabelWindow[\(self.spaceId)]: updateVisibility. isVisible: \(self.isVisible), isVisuallyVisible: \(isVisuallyVisible), level: \(self.level.rawValue), isActiveMode: \(self.isActiveMode)")
        DiagnosticEventLog.shared.record(subsystem: "SpaceLabelWindow", "updateVisibility[\(self.spaceId)]: isVisible=\(self.isVisible), visually=\(isVisuallyVisible), level=\(self.level.rawValue), active=\(self.isActiveMode)")

        let shouldBeAnchor = !isVisuallyVisible
        if self.isInvisibleAnchorMode != shouldBeAnchor {
            self.isInvisibleAnchorMode = shouldBeAnchor
            updateLayout(isCurrentSpace: self.isActiveMode, updateFrame: animated)
        }

        if isVisuallyVisible {
            // MULTI-MONITOR STABILITY FIX: Check for programmatic switch cooling period.
            // If a switch was triggered recently, we DO NOT order front based on isVisible.
            // This is because isVisible might be false briefly during animations, 
            // and calling orderFrontRegardless on the WRONG monitor causes a "snap-back".
            let now = Date().timeIntervalSince1970
            let timeSinceSwitch = now - SpaceHelper.lastProgrammaticSwitchTime
            let coolingPeriod: TimeInterval = 0.3
            let inCoolingPeriod = timeSinceSwitch < coolingPeriod

            if self.isActiveMode {
                if !self.isVisible {
                    if !inCoolingPeriod {
                        print("SpaceLabelWindow[\(self.spaceId)]: orderFrontRegardless() for ACTIVE space.")
                        // Preview labels must not activate their owning space.
                        // orderFrontRegardless() can make macOS navigate to a
                        // background Space when the display topology is changing.
                        self.orderFront(nil)
                        self.bindToTargetSpace()
                        self.hasOrderedInOnce = true
                    } else {
                        print("SpaceLabelWindow[\(self.spaceId)]: Suppressing orderFrontRegardless (Active) during switch cooling period (\(String(format: "%.2f", timeSinceSwitch))s). Scheduling retry.")
                        scheduleVisibilityRetry(delay: coolingPeriod - timeSinceSwitch + 0.1)
                    }
                }
            } else if !hasOrderedInOnce {
                // For preview windows (on background spaces), we ONLY order front once.
                if !inCoolingPeriod {
                    // SAFETY GUARD: Only order front if the window is actually bound
                    // to its target space (or at least not on the current space).
                    // If CGSAddWindowsToSpaces failed silently, ordering front would
                    // place this label on the wrong (current) desktop, causing clustering.
                    if isBoundToTargetSpace() || !isOnCurrentSpace() {
                        print("SpaceLabelWindow[\(self.spaceId)]: Non-activating orderFront() for background preview.")
                        // Keep preview ordering non-activating; explicit space
                        // switches use SpaceHelper.switchByActivatingOwnWindow.
                        self.orderFront(nil)
                        self.bindToTargetSpace()
                        self.hasOrderedInOnce = true
                    } else {
                        print("SpaceLabelWindow[\(self.spaceId)]: Binding check failed — preview label would appear on wrong space. Staying hidden.")
                        DiagnosticEventLog.shared.record(subsystem: "SpaceLabelWindow", level: "warning", "BLOCKED orderFrontRegardless for preview label \(self.spaceId): bound=\(isBoundToTargetSpace()), onCurrent=\(isOnCurrentSpace())")
                        self.bindToTargetSpace()
                    }
                } else {
                    print("SpaceLabelWindow[\(self.spaceId)]: Suppressing orderFrontRegardless (Preview) during switch cooling period (\(String(format: "%.2f", timeSinceSwitch))s). Scheduling retry.")
                    scheduleVisibilityRetry(delay: coolingPeriod - timeSinceSwitch + 0.1)
                }
            } else if !self.isVisible {
                // Safety: Window was ordered out externally (e.g., by switchByActivatingOwnWindow
                // which hides other labels via orderOut during drag-based switching).
                // Preview labels only order front once, so re-order it now to recover.
                if !inCoolingPeriod {
                    if isBoundToTargetSpace() || !isOnCurrentSpace() {
                        print("SpaceLabelWindow[\(self.spaceId)]: Non-activating orderFront() for background preview.")
                        self.orderFrontRegardless()
                        self.bindToTargetSpace()
                    } else {
                        print("SpaceLabelWindow[\(self.spaceId)]: Re-order blocked — preview label would appear on wrong space.")
                        DiagnosticEventLog.shared.record(subsystem: "SpaceLabelWindow", level: "warning", "BLOCKED re-order for preview label \(self.spaceId): bound=\(isBoundToTargetSpace()), onCurrent=\(isOnCurrentSpace())")
                        self.bindToTargetSpace()
                    }
                } else {
                    scheduleVisibilityRetry(delay: coolingPeriod - timeSinceSwitch + 0.1)
                }
            }
        }

        if self.isVisible {
            self.bindToTargetSpace()
        }

        if isVisuallyVisible {
            self.alphaValue = 1.0
        }
        let targetContentAlpha: CGFloat = isVisuallyVisible ? 1.0 : 0.0

        if animated {
            self.contentView?.animator().alphaValue = targetContentAlpha
        } else {
            self.contentView?.alphaValue = targetContentAlpha
        }

        if isVisuallyVisible {
            updateInteractivity()
        } else {
            self.ignoresMouseEvents = true
        }
    }

    @objc func repositionWindow() {
        updateLayout(isCurrentSpace: isActiveMode)
        updateVisibility(animated: false)
    }

    private func scheduleVisibilityRetry(delay: TimeInterval) {
        let task = DispatchWorkItem { [weak self] in
            self?.updateVisibility(animated: false)
        }
        self.pendingVisibilityTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.01, delay), execute: task)
    }
}
