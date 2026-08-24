import Cocoa
import Combine
import QuartzCore

extension SpaceLabelWindow {

    // Full layout and visibility update.
    func updateLayout(isCurrentSpace: Bool, updateFrame: Bool = true) {
        guard let targetScreen = findTargetScreen() else {
            self.close()
            return
        }

        var newSize: NSSize
        var newOrigin: NSPoint
        var targetCenter = NSPoint.zero

        let showHandle = isCurrentSpace && isDocked && (labelManager?.showOnDesktop == true)
        let isHiddenCornerMode =
            isCurrentSpace && !showHandle && !(labelManager?.showOnDesktop == true)

        // Determine Dimensions.
        var isSmallModeForFont = false
        var shouldUseHandle = false

        if self.isInvisibleAnchorMode {
            // Anchor Mode: 1x1 Pixel
            newSize = NSSize(width: 1, height: 1)
        } else if showHandle {
            shouldUseHandle = true
            if self.dockEdge == .minX || self.dockEdge == .maxX {
                newSize = SpaceLabelWindow.handleSize
            } else {
                newSize = NSSize(
                    width: SpaceLabelWindow.handleSize.height,
                    height: SpaceLabelWindow.handleSize.width)
            }
        } else if isCurrentSpace {
            isSmallModeForFont = true
            newSize = calculateActiveSize()
        } else {
            isSmallModeForFont = false
            newSize = previewSize
        }

        // Determine Position.
        if self.isInvisibleAnchorMode {
            // Anchor Mode: Center of Screen
            newOrigin = NSPoint(x: targetScreen.frame.midX, y: targetScreen.frame.midY)
        } else if isCurrentSpace {
            targetCenter = getAbsoluteTargetCenter(on: targetScreen, forSize: newSize)

            if showHandle {
                newOrigin = calculateCenteredOrigin(
                    forSize: newSize, onEdge: self.dockEdge, centerPoint: targetCenter,
                    screenFrame: targetScreen.visibleFrame, clampToScreen: true
                )
            } else if isHiddenCornerMode {
                newOrigin = findBestOffscreenPosition(targetScreen: targetScreen, size: newSize)
            } else {
                newOrigin = calculateCenteredOrigin(
                    forSize: newSize, onEdge: self.dockEdge, centerPoint: targetCenter,
                    screenFrame: targetScreen.visibleFrame, clampToScreen: false,
                    isDocked: self.isDocked
                )
            }
        } else {
            // Preview Mode
            targetCenter = NSPoint(x: targetScreen.frame.midX, y: targetScreen.frame.midY)
            newOrigin = NSPoint(
                x: targetCenter.x - newSize.width / 2, y: targetCenter.y - newSize.height / 2)
        }

        // Execution Phase.
        let updateVisuals = {
            self.backgroundColor = .clear  // RE-ASSERT TRANSPARENCY

            if self.isInvisibleAnchorMode {
                if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 {
                    self.level = .floating // On macOS 27+, keep floating at all times to prevent replication/stacking
                } else {
                    self.level = .normal  // CRITICAL: Floating windows don't switch spaces. Normal windows do.
                }
                self.label.isHidden = true
                self.handleView.isHidden = true
                self.contentView?.layer?.cornerRadius = 0
                self.contentView?.isHidden = true  // EXPLICITLY HIDE CONTENT
            } else if shouldUseHandle {
                self.level = .floating  // Restore for visibility
                self.label.isHidden = true
                self.handleView.isHidden = false
                self.handleView.edge = self.dockEdge
                self.contentView?.layer?.cornerRadius = 12
                self.contentView?.isHidden = false
            } else {
                // macOS < 27: Use .normal for preview labels so they don't float above
                // app windows if CGS space isolation fails. macOS 27+ keeps .floating
                // since SLS operations handle space transitions correctly.
                if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 {
                    self.level = .floating
                } else {
                    self.level = self.isActiveMode ? .floating : .normal
                }
                self.label.isHidden = false
                self.handleView.isHidden = true
                self.contentView?.layer?.cornerRadius = 20
                self.updateLabelFont(for: newSize, isSmallMode: isSmallModeForFont)
                self.contentView?.isHidden = false
            }
            self.contentView?.needsDisplay = true
            self.invalidateShadow()
        }

        if updateFrame {
            if isHiddenCornerMode && !self.isInvisibleAnchorMode {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.08
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    self.contentView?.animator().alphaValue = 0.0
                } completionHandler: {
                    updateVisuals()
                    self.setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
                    self.contentView?.alphaValue = 1.0
                }
            } else {
                updateVisuals()
                self.animator().setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
            }
        } else {
            updateVisuals()
            self.setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
        }
    }

    // Geometry utilities for layout calculations.

    func calculateCenteredOrigin(
        forSize size: NSSize, onEdge edge: NSRectEdge, centerPoint: NSPoint, screenFrame: NSRect,
        clampToScreen: Bool, isDocked: Bool = true
    ) -> NSPoint {
        if !isDocked {
            var origin = NSPoint(x: centerPoint.x - size.width / 2, y: centerPoint.y - size.height / 2)
            // Mandatory Clamping to prevent clipping
            origin.x = max(screenFrame.minX, min(origin.x, screenFrame.maxX - size.width))
            origin.y = max(screenFrame.minY, min(origin.y, screenFrame.maxY - size.height))
            return origin
        }

        var origin = NSPoint.zero
        switch edge {
        case .minX: origin = NSPoint(x: screenFrame.minX, y: centerPoint.y - size.height / 2)
        case .maxX:
            origin = NSPoint(x: screenFrame.maxX - size.width, y: centerPoint.y - size.height / 2)
        case .minY: origin = NSPoint(x: centerPoint.x - size.width / 2, y: screenFrame.minY)
        case .maxY:
            origin = NSPoint(x: centerPoint.x - size.width / 2, y: screenFrame.maxY - size.height)
        @unknown default:
            origin = NSPoint(x: centerPoint.x - size.width / 2, y: centerPoint.y - size.height / 2)
        }

        if clampToScreen {
            if edge == .minX || edge == .maxX {
                origin.y = max(screenFrame.minY, min(origin.y, screenFrame.maxY - size.height))
            } else {
                origin.x = max(screenFrame.minX, min(origin.x, screenFrame.maxX - size.width))
            }
        }
        return origin
    }

    func calculateActiveSize() -> NSSize {
        let scaleF = CGFloat(labelManager?.activeFontScale ?? 1.0)
        let scaleP = CGFloat(labelManager?.activePaddingScale ?? 1.0)
        return calculateSize(
            baseFont: SpaceLabelWindow.baseActiveFontSize * scaleF, paddingScale: scaleP,
            basePadH: 60, basePadV: 40)
    }

    private func calculateSize(
        baseFont: CGFloat, paddingScale: CGFloat, basePadH: CGFloat, basePadV: CGFloat
    ) -> NSSize {
        let name = self.label.stringValue
        let font = NSFont.systemFont(ofSize: baseFont, weight: .bold)
        let size = name.size(withAttributes: [.font: font])
        return NSSize(
            width: size.width + (basePadH * paddingScale),
            height: size.height + (basePadV * paddingScale))
    }

    private func updateLabelFont(for size: NSSize, isSmallMode: Bool) {
        let name = self.label.stringValue
        let paddingScale: CGFloat
        let fontScale: CGFloat
        let baseSize: CGFloat

        if isSmallMode {
            paddingScale = CGFloat(labelManager?.activePaddingScale ?? 1.0)
            fontScale = CGFloat(labelManager?.activeFontScale ?? 1.0)
            baseSize = SpaceLabelWindow.baseActiveFontSize
        } else {
            paddingScale = CGFloat(labelManager?.previewPaddingScale ?? 1.0)
            fontScale = CGFloat(labelManager?.previewFontScale ?? 1.0)
            baseSize = SpaceLabelWindow.basePreviewFontSize
        }

        let paddingH: CGFloat = (size.width * 0.1) * paddingScale
        let paddingV: CGFloat = (size.height * 0.15) * paddingScale
        let maxWidth = size.width - paddingH
        let maxHeight = size.height - paddingV

        var fontSize = baseSize * fontScale
        var font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        var sSize = name.size(withAttributes: [.font: font])

        while (sSize.width > maxWidth || sSize.height > maxHeight) && fontSize > 10 {
            fontSize -= 2
            font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
            sSize = name.size(withAttributes: [.font: font])
        }

        self.label.font = font
        let displayHeight = sSize.height + 4
        self.label.frame = NSRect(
            x: 0, y: (size.height - displayHeight) / 2, width: size.width, height: displayHeight)
    }

    func findTargetScreen() -> NSScreen? {
        SpaceLabelWindow.screen(matching: displayID)
    }

    private func findBestOffscreenPosition(targetScreen: NSScreen, size: NSSize) -> NSPoint {
        let f = targetScreen.frame
        let allScreens = NSScreen.screens

        let candidates: [NSPoint] = [
            NSPoint(x: f.minX - size.width + 1, y: f.maxY - 1),  // Top-Left
            NSPoint(x: f.maxX - 1, y: f.maxY - 1),  // Top-Right
            NSPoint(x: f.minX - size.width + 1, y: f.minY - size.height + 1),  // Bottom-Left
            NSPoint(x: f.maxX - 1, y: f.minY - size.height + 1),  // Bottom-Right
        ]

        var bestCandidate: NSPoint = candidates[0]
        var maxMinDist: CGFloat = -2.0

        for origin in candidates {
            let rect = NSRect(origin: origin, size: size)
            var minDist: CGFloat = 100000.0
            var intersects = false

            for other in allScreens {
                if other == targetScreen { continue }
                let otherFrame = other.frame
                if otherFrame.intersects(rect) {
                    intersects = true
                    break
                }
                let dx = max(otherFrame.minX - rect.maxX, rect.minX - otherFrame.maxX, 0)
                let dy = max(otherFrame.minY - rect.maxY, rect.minY - otherFrame.maxY, 0)
                let dist = sqrt(dx * dx + dy * dy)
                if dist < minDist { minDist = dist }
            }

            if intersects { minDist = -1.0 }
            if minDist > maxMinDist {
                maxMinDist = minDist
                bestCandidate = origin
            }
        }
        return bestCandidate
    }

    func findNearestEdgePosition(targetScreen: NSScreen, forRect rect: NSRect) -> NSPoint {
        let size = rect.size
        let sFrame = targetScreen.visibleFrame
        let distLeft = abs(rect.minX - sFrame.minX)
        let distRight = abs(rect.maxX - sFrame.maxX)
        let distTop = abs(rect.maxY - sFrame.maxY)
        let distBottom = abs(rect.minY - sFrame.minY)
        let minDist = min(distLeft, distRight, distTop, distBottom)

        var finalOrigin = rect.origin
        if minDist == distLeft {
            finalOrigin.x = sFrame.minX
            self.dockEdge = .minX
        } else if minDist == distRight {
            finalOrigin.x = sFrame.maxX - size.width
            self.dockEdge = .maxX
        } else if minDist == distTop {
            finalOrigin.y = sFrame.maxY - size.height
            self.dockEdge = .maxY
        } else {
            finalOrigin.y = sFrame.minY
            self.dockEdge = .minY
        }

        if minDist == distLeft || minDist == distRight {
            finalOrigin.y = max(sFrame.minY, min(finalOrigin.y, sFrame.maxY - size.height))
        } else {
            finalOrigin.x = max(sFrame.minX, min(finalOrigin.x, sFrame.maxX - size.width))
        }
        return finalOrigin
    }
}
