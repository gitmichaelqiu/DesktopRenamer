import Cocoa
import Combine
import QuartzCore

extension SpaceLabelWindow {

    /// Temporarily makes this label activation-capable for an intentional
    /// programmatic Space switch. Normal label interaction remains
    /// non-activating so clicking or dragging a label cannot select its Space.
    func activateForSpaceSwitch() {
        let originalStyleMask = self.styleMask
        var activationStyleMask = originalStyleMask
        activationStyleMask.remove(.nonactivatingPanel)
        self.styleMask = activationStyleMask

        defer {
            self.canBecomeKeyOverride = false
            self.styleMask = originalStyleMask
        }

        self.orderFrontRegardless()
        self.canBecomeKeyOverride = true
        self.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Shows a preview label without activating the application or making the
    /// label's Space current.
    func orderPreviewWithoutActivating() {
        guard windowNumber > 0 else { return }
        let traceID = SpaceHelper.debugTraceID()
        let beforeSpaces = SpaceHelper.getWindowCurrentSpaces(windowID: windowNumber)
        let beforeCurrentSpaces = SpaceHelper.getCurrentSpaceIDsByDisplay()
        SpaceHelper.debugTrace(
            traceID,
            "label order-preview begin label=\(spaceId), window=\(windowNumber), windowSpaces=\(beforeSpaces.sorted()), live=\(SpaceHelper.debugFormatSpaceMap(beforeCurrentSpaces)), visible=\(isVisible), key=\(isKeyWindow)"
        )
        // orderFront(_:) can ask WindowServer to select the Space containing a
        // managed window even when the panel is nonactivating. orderWindow is
        // the non-key ordering operation: it makes the panel visible and
        // changes its z-order without requesting application activation.
        order(.above, relativeTo: 0)
        let afterSpaces = SpaceHelper.getWindowCurrentSpaces(windowID: windowNumber)
        let afterCurrentSpaces = SpaceHelper.getCurrentSpaceIDsByDisplay()
        SpaceHelper.debugTrace(
            traceID,
            "label order-preview end label=\(spaceId), window=\(windowNumber), windowSpaces=\(afterSpaces.sorted()), live=\(SpaceHelper.debugFormatSpaceMap(afterCurrentSpaces)), visible=\(isVisible), key=\(isKeyWindow)"
        )
    }

    // Binds the window to a specific space via private APIs.
    func bindToTargetSpace() {
        let cid = _CGSDefaultConnection()
        guard let targetSpaceInt = Int(self.spaceId) else { return }

        let winID = [NSNumber(value: self.windowNumber)] as CFArray
        let targetSpaces = [NSNumber(value: targetSpaceInt)] as CFArray
        let currentSpacesCF = CGSCopySpacesForWindows(cid, 7, winID)
        let currentSpaces = (currentSpacesCF as? [NSNumber])?.map { $0.intValue } ?? []
        let traceID = SpaceHelper.debugTraceID()

        // Rebinding an already-correct label is a synchronous WindowServer
        // operation. Visibility and active-label synchronization can call
        // this method several times during one transition, so avoid changing
        // the window's space assignment when there is nothing to repair.
        if currentSpaces == [targetSpaceInt] {
            SpaceHelper.debugTrace(
                traceID,
                "label bind skipped label=\(spaceId), window=\(windowNumber), target=\(targetSpaceInt), windowSpaces=\(currentSpaces), reason=already-bound"
            )
            return
        }

        CGSAddWindowsToSpaces(cid, winID, targetSpaces)
        let spacesAfterAddCF = CGSCopySpacesForWindows(cid, 7, winID)
        let spacesAfterAdd = (spacesAfterAddCF as? [NSNumber])?.map { $0.intValue } ?? []

        print("SpaceLabelWindow[\(self.spaceId)]: bindToTargetSpace. Window Number: \(self.windowNumber). Current spaces: \(currentSpaces). Target space: \(targetSpaceInt)")
        DiagnosticEventLog.shared.record(subsystem: "SpaceLabelWindow", "bindToTargetSpace[\(self.spaceId)]: win=\(self.windowNumber), currentSpaces=\(currentSpaces), target=\(targetSpaceInt)")

        let spacesToRemove = currentSpaces.filter { $0 != targetSpaceInt }
        if !spacesToRemove.isEmpty {
            print("SpaceLabelWindow[\(self.spaceId)]: Removing window \(self.windowNumber) from spaces: \(spacesToRemove)")
            let removeCF = spacesToRemove.map { NSNumber(value: $0) } as CFArray
            CGSRemoveWindowsFromSpaces(cid, winID, removeCF)
        }
        let finalSpacesCF = CGSCopySpacesForWindows(cid, 7, winID)
        let finalSpaces = (finalSpacesCF as? [NSNumber])?.map { $0.intValue } ?? []
        SpaceHelper.debugTrace(
            traceID,
            "label bind end label=\(spaceId), window=\(windowNumber), target=\(targetSpaceInt), before=\(currentSpaces), afterAdd=\(spacesAfterAdd), removed=\(spacesToRemove), final=\(finalSpaces), live=\(SpaceHelper.debugFormatSpaceMap(SpaceHelper.getCurrentSpaceIDsByDisplay()))"
        )
    }

    /// Returns true if this window is currently assigned to its target space by the CGS window server.
    func isBoundToTargetSpace() -> Bool {
        guard windowNumber > 0 else { return false }
        let currentSpaces = SpaceHelper.getWindowCurrentSpaces(windowID: windowNumber)
        let bound = currentSpaces.contains(spaceId)
        SpaceHelper.debugTrace(
            SpaceHelper.debugTraceID(),
            "label binding check label=\(spaceId), window=\(windowNumber), target=\(spaceId), bound=\(bound), windowSpaces=\(currentSpaces.sorted()), live=\(SpaceHelper.debugFormatSpaceMap(SpaceHelper.getCurrentSpaceIDsByDisplay()))"
        )
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
            isDocked: self.isDocked,
            edge: self.dockEdge,
            center: NSPoint(x: relX, y: relY),
            sourceWindow: self
        )
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
