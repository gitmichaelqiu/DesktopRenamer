import Cocoa
import Combine
import QuartzCore

extension SpaceLabelWindow {

    func updateName(_ name: String) {
        self.label.stringValue = name
        self.updateLayout(isCurrentSpace: self.isActiveMode)
    }

    func hideImmediately() {
        let wasVisible = isVisible

        // A preview may have a delayed retry queued from the switch cooldown.
        // Cancel it before hiding so the retry cannot reveal the preview again
        // after the manager has determined that this is the current space.
        pendingVisibilityTask?.cancel()
        pendingVisibilityTask = nil

        // updateVisibility(animated:) uses the content view's animator. A
        // pending fade-to-visible animation can otherwise complete after this
        // call and paint the preview back in during a space transition.
        contentView?.layer?.removeAllAnimations()
        contentContainer.layer?.removeAllAnimations()
        self.alphaValue = 0.0
        self.contentView?.alphaValue = 0.0

        // A transparent managed window is still represented by Mission
        // Control, which leaves a large empty frame for the hidden preview.
        // Ordering it out removes that frame without changing its assigned
        // Space; updateVisibility() orders it back in when the preview is
        // allowed to show again.
        if wasVisible {
            self.orderOut(nil)
        }
    }

    // Interaction handling for mouse events.
    override func mouseDown(with event: NSEvent) {
        guard let manager = labelManager, manager.showOnDesktop, isActiveMode else {
            super.mouseDown(with: event)
            return
        }

        // A delayed launch-space recovery must never override an explicit
        // interaction with the active label. This is especially important for
        // the first drag after launch, when label seeding may still have a
        // queued recovery task.
        manager.cancelLaunchSpaceRestoreForUserInteraction()

        var startMouseLocation = NSEvent.mouseLocation
        let startWindowOrigin = self.frame.origin
        var mouseOffset = NSPoint(
            x: startMouseLocation.x - startWindowOrigin.x,
            y: startMouseLocation.y - startWindowOrigin.y)
        var hasDragged = false

        while true {
            guard
                let nextEvent = self.nextEvent(
                    matching: [.leftMouseDragged, .leftMouseUp],
                    until: .distantFuture,
                    inMode: .eventTracking,
                    dequeue: true)
            else { break }

            if nextEvent.type == .leftMouseUp {
                if !hasDragged {
                    toggleDockState()
                } else {
                    pushToGlobalState()
                }
                break
            } else if nextEvent.type == .leftMouseDragged {
                let currentMouseLocation = NSEvent.mouseLocation

                if !hasDragged {
                    let dx = currentMouseLocation.x - startMouseLocation.x
                    let dy = currentMouseLocation.y - startMouseLocation.y
                    if hypot(dx, dy) > 5.0 { hasDragged = true }
                }

                if hasDragged {
                    var targetOrigin = NSPoint(
                        x: currentMouseLocation.x - mouseOffset.x,
                        y: currentMouseLocation.y - mouseOffset.y)

                    if let screen = self.screen {
                        let screenFrame = screen.visibleFrame
                        var didStateChange = false

                        let distLeft = abs(currentMouseLocation.x - screenFrame.minX)
                        let distRight = abs(currentMouseLocation.x - screenFrame.maxX)
                        let distTop = abs(currentMouseLocation.y - screenFrame.maxY)
                        let distBottom = abs(currentMouseLocation.y - screenFrame.minY)
                        let minMouseEdgeDist = min(distLeft, distRight, distTop, distBottom)

                        // Toggle Logic
                        if !isDocked {
                            if minMouseEdgeDist < 15.0 {
                                isDocked = true
                                didStateChange = true
                                if minMouseEdgeDist == distLeft {
                                    self.dockEdge = .minX
                                } else if minMouseEdgeDist == distRight {
                                    self.dockEdge = .maxX
                                } else if minMouseEdgeDist == distTop {
                                    self.dockEdge = .maxY
                                } else {
                                    self.dockEdge = .minY
                                }
                            }
                        } else {
                            if minMouseEdgeDist > 50.0 {
                                isDocked = false
                                didStateChange = true
                            }
                        }

                        if didStateChange {
                            updateLayout(isCurrentSpace: true, updateFrame: false)
                            let newSize = self.frame.size

                            let rootedOrigin = calculateCenteredOrigin(
                                forSize: newSize,
                                onEdge: self.dockEdge,
                                centerPoint: NSPoint(
                                    x: currentMouseLocation.x, y: currentMouseLocation.y),
                                screenFrame: screenFrame,
                                clampToScreen: isDocked,
                                isDocked: isDocked
                            )
                            targetOrigin = rootedOrigin

                            self.setFrameOrigin(targetOrigin)
                            mouseOffset = NSPoint(
                                x: currentMouseLocation.x - targetOrigin.x,
                                y: currentMouseLocation.y - targetOrigin.y)
                            startMouseLocation = currentMouseLocation

                            pushToGlobalState()
                            continue
                        }

                        if isDocked {
                            let rawRect = NSRect(origin: targetOrigin, size: self.frame.size)
                            let snappedOrigin = findNearestEdgePosition(
                                targetScreen: screen, forRect: rawRect)
                            self.setFrameOrigin(snappedOrigin)
                        } else {
                            self.setFrameOrigin(targetOrigin)
                        }
                    }
                }
            }
        }
    }

    private func toggleDockState() {
        if self.isDocked {
            self.isDocked = false

            if let screen = self.screen {
                let currentCenter = NSPoint(x: self.frame.midX, y: self.frame.midY)
                let newSize = calculateActiveSize()
                let rootedOrigin = calculateCenteredOrigin(
                    forSize: newSize,
                    onEdge: self.dockEdge,
                    centerPoint: currentCenter,
                    screenFrame: screen.visibleFrame,
                    clampToScreen: false,
                    isDocked: false
                )
                let newCenter = NSPoint(
                    x: rootedOrigin.x + newSize.width / 2, y: rootedOrigin.y + newSize.height / 2)

                let sFrame = screen.visibleFrame
                let relX = (newCenter.x - sFrame.minX) / sFrame.width
                let relY = (newCenter.y - sFrame.minY) / sFrame.height

                if let manager = labelManager {
                    manager.updateGlobalState(
                        isDocked: false,
                        edge: self.dockEdge,
                        center: NSPoint(x: relX, y: relY),
                        sourceWindow: self
                    )
                }
            }
            animateFrameChange()

        } else {
            if let screen = self.screen {
                _ = findNearestEdgePosition(targetScreen: screen, forRect: self.frame)
            }
            self.isDocked = true
            pushToGlobalState()
            animateFrameChange()
        }
    }

    private func animateFrameChange() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            updateLayout(isCurrentSpace: true)
        }
    }

    func updateInteractivity() {
        let isInteractive = (labelManager?.showOnDesktop == true) && isActiveMode
        self.ignoresMouseEvents = !isInteractive
        self.isMovableByWindowBackground = false
    }

}
