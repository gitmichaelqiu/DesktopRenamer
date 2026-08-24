import Cocoa
import Combine
import QuartzCore

extension SpaceLabelWindow {

    /// Orders a preview label through WindowServer without asking AppKit to
    /// activate the application or select the label's space.
    func orderPreviewWithoutActivating() {
        guard windowNumber > 0 else { return }
        _ = CGSOrderWindow(_CGSDefaultConnection(), UInt32(windowNumber), 0, 0)
    }

    // Binds the window to a specific space via private APIs.
    func bindToTargetSpace() {
        let cid = _CGSDefaultConnection()
        guard let targetSpaceInt = Int(self.spaceId) else { return }

        let winID = [NSNumber(value: self.windowNumber)] as CFArray
        let targetSpaces = [NSNumber(value: targetSpaceInt)] as CFArray

        CGSAddWindowsToSpaces(cid, winID, targetSpaces)

        let currentSpacesCF = CGSCopySpacesForWindows(cid, 7, winID)
        let currentSpaces = (currentSpacesCF as? [NSNumber])?.map { $0.intValue } ?? []

        print("SpaceLabelWindow[\(self.spaceId)]: bindToTargetSpace. Window Number: \(self.windowNumber). Current spaces: \(currentSpaces). Target space: \(targetSpaceInt)")
        DiagnosticEventLog.shared.record(subsystem: "SpaceLabelWindow", "bindToTargetSpace[\(self.spaceId)]: win=\(self.windowNumber), currentSpaces=\(currentSpaces), target=\(targetSpaceInt)")

        let spacesToRemove = currentSpaces.filter { $0 != targetSpaceInt }
        if !spacesToRemove.isEmpty {
            print("SpaceLabelWindow[\(self.spaceId)]: Removing window \(self.windowNumber) from spaces: \(spacesToRemove)")
            let removeCF = spacesToRemove.map { NSNumber(value: $0) } as CFArray
            CGSRemoveWindowsFromSpaces(cid, winID, removeCF)
        }
    }

    /// Returns true if this window is currently assigned to its target space by the CGS window server.
    func isBoundToTargetSpace() -> Bool {
        guard windowNumber > 0 else { return false }
        let currentSpaces = SpaceHelper.getWindowCurrentSpaces(windowID: windowNumber)
        let bound = currentSpaces.contains(spaceId)
        DiagnosticEventLog.shared.record(subsystem: "SpaceLabelWindow", level: "info", "isBoundToTargetSpace[\(self.spaceId)]: win=\(self.windowNumber), bound=\(bound), spaces=\(currentSpaces.sorted().joined(separator: ","))")
        return bound
    }

    /// Returns true if this window currently belongs to the active space.
    func isOnCurrentSpace() -> Bool {
        guard windowNumber > 0 else { return false }
        let currentSpaces = SpaceHelper.getWindowCurrentSpaces(windowID: windowNumber)
        let onCurrent = currentSpaces.contains(spaceManager.currentSpaceUUID)
        DiagnosticEventLog.shared.record(subsystem: "SpaceLabelWindow", level: "info", "isOnCurrentSpace[\(self.spaceId)]: win=\(self.windowNumber), onCurrent=\(onCurrent), currentSpace=\(spaceManager.currentSpaceUUID)")
        return onCurrent
    }

    // Workaround to maintain window rendering during space transitions.
    func setupLiveBackgroundUpdate() {
        guard let layer = self.contentView?.layer else { return }
        let key = "forceRedrawLoop"
        if layer.animation(forKey: key) == nil {
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = 1.0
            anim.toValue = 0.9999
            anim.duration = 1.0
            anim.autoreverses = true
            anim.repeatCount = .infinity
            anim.isRemovedOnCompletion = false
            layer.add(anim, forKey: key)
        }
    }

    // Keeping everything in sync with the manager
    func syncFromGlobalState() {
        guard let manager = labelManager, let _ = self.screen else { return }
        self.isDocked = manager.globalIsDocked
        self.dockEdge = manager.globalDockEdge

        if let point = manager.globalCenterPoint {
            if point.x > 2.0 || point.y > 2.0 {
                let defaultRelative = NSPoint(x: 1.0, y: 0.5)
                manager.updateGlobalState(isDocked: true, edge: .maxX, center: defaultRelative)
                self.dockEdge = .maxX
                self.isDocked = true
            }
        } else {
            let defaultRelative = NSPoint(x: 1.0, y: 0.5)
            manager.updateGlobalState(isDocked: true, edge: .maxX, center: defaultRelative)
            self.dockEdge = .maxX
            self.isDocked = true
        }
    }

    func pushToGlobalState() {
        guard let manager = labelManager, let screen = self.screen else { return }
        let sFrame = screen.visibleFrame
        let currentAbsCenter = NSPoint(x: self.frame.midX, y: self.frame.midY)

        var relX: CGFloat = (currentAbsCenter.x - sFrame.minX) / sFrame.width
        var relY: CGFloat = (currentAbsCenter.y - sFrame.minY) / sFrame.height

        if self.isDocked {
            // For docked handles, force relative center to respect the edge
            // so that if we undock on another space, it appears at the edge.
            switch self.dockEdge {
            case .minX: relX = 0.0
            case .maxX: relX = 1.0
            case .minY: relY = 0.0
            case .maxY: relY = 1.0
            default: break
            }
        } else {
            // For floating labels, use exact 0.0/1.0 if near edges (clamped or close)
            // to ensure consistent edge alignment across labels of different widths.
            let snapThreshold: CGFloat = 20.0
            if abs(self.frame.minX - sFrame.minX) < snapThreshold { relX = 0.0 }
            else if abs(self.frame.maxX - sFrame.maxX) < snapThreshold { relX = 1.0 }

            if abs(self.frame.minY - sFrame.minY) < snapThreshold { relY = 0.0 }
            else if abs(self.frame.maxY - sFrame.maxY) < snapThreshold { relY = 1.0 }
        }

        manager.updateGlobalState(
            isDocked: self.isDocked, edge: self.dockEdge, center: NSPoint(x: relX, y: relY))
    }

    // Calculates the target center point based on docking and layout settings.
    func getAbsoluteTargetCenter(on screen: NSScreen, forSize size: NSSize) -> NSPoint {
        let relativePoint = labelManager?.globalCenterPoint ?? NSPoint(x: 1.0, y: 0.5)
        let sFrame = screen.visibleFrame

        var absX: CGFloat
        var absY: CGFloat

        // Interpret relative 0.0 and 1.0 as absolute "Flush to Edge" alignment
        if relativePoint.x == 0.0 {
            absX = sFrame.minX + (size.width / 2)
        } else if relativePoint.x == 1.0 {
            absX = sFrame.maxX - (size.width / 2)
        } else {
            absX = sFrame.minX + (sFrame.width * relativePoint.x)
        }

        if relativePoint.y == 0.0 {
            absY = sFrame.minY + (size.height / 2)
        } else if relativePoint.y == 1.0 {
            absY = sFrame.maxY - (size.height / 2)
        } else {
            absY = sFrame.minY + (sFrame.height * relativePoint.y)
        }

        if isDocked {
            switch self.dockEdge {
            case .minX: absX = sFrame.minX + (size.width / 2)
            case .maxX: absX = sFrame.maxX - (size.width / 2)
            case .minY: absY = sFrame.minY + (size.height / 2)
            case .maxY: absY = sFrame.maxY - (size.height / 2)
            default: break
            }
        }

        return NSPoint(x: absX, y: absY)
    }

    // Public interface for window management.
}
