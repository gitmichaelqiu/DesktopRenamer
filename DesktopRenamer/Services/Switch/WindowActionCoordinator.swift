import AppKit

@MainActor
enum WindowActionCoordinator {
    struct VisibilityState {
        let isMinimized: Bool
        let isHidden: Bool
    }

    static func visibilityState(windowID: Int, pid: Int32) -> VisibilityState {
        var isMinimized = false
        let isHidden = NSRunningApplication(processIdentifier: pid)?.isHidden ?? false

        if let axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid) {
            var minimizedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
               let minimized = minimizedRef as? Bool {
                isMinimized = minimized
            }
        }

        return VisibilityState(isMinimized: isMinimized, isHidden: isHidden)
    }

    static func restoreWindowForMove(windowID: Int, pid: Int32) async {
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.unhide()
        }
        if let axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid) {
            AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, false as CFTypeRef)
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
    }

    static func reapplyVisibility(_ state: VisibilityState, windowID: Int, pid: Int32) async {
        guard state.isMinimized || state.isHidden else { return }

        if state.isMinimized {
            var axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid)
            if axWindow == nil {
                if let app = NSRunningApplication(processIdentifier: pid) {
                    app.activate(options: .activateIgnoringOtherApps)
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid)
                }
            }
            if let targetAXWindow = axWindow {
                AXUIElementSetAttributeValue(targetAXWindow, kAXMinimizedAttribute as CFString, true as CFTypeRef)
            }
        }

        if state.isHidden,
           let app = NSRunningApplication(processIdentifier: pid) {
            app.hide()
        }
    }

    @discardableResult
    static func moveWindow(
        windowID: Int,
        pid: Int32,
        fromSpaceID: String,
        targetSpaceID: String,
        preserveVisibility: Bool = true
    ) async -> Bool {
        guard fromSpaceID != targetSpaceID else { return true }
        guard let manager = AppDelegate.shared.spaceManager,
              let sourceSpace = manager.spaceNameDict.first(where: { $0.id == fromSpaceID }),
              let targetSpace = manager.spaceNameDict.first(where: { $0.id == targetSpaceID }),
              !targetSpace.isFullscreen else {
            return false
        }

        let originalVisibility = visibilityState(windowID: windowID, pid: pid)

        if manager.currentSpaceUUID != fromSpaceID {
            manager.switchToSpace(sourceSpace, forceInstant: true)
            try? await Task.sleep(nanoseconds: 600_000_000)
        }

        if originalVisibility.isMinimized || originalVisibility.isHidden {
            await restoreWindowForMove(windowID: windowID, pid: pid)
        }

        SpaceHelper.focusWindow(id: windowID, pid: pid)
        try? await Task.sleep(nanoseconds: 250_000_000)

        if sourceSpace.isFullscreen {
            var axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid)
            if axWindow == nil {
                if let app = NSRunningApplication(processIdentifier: pid) {
                    app.activate(options: .activateIgnoringOtherApps)
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid)
                }
            }
            if let targetAXWindow = axWindow {
                AXUIElementSetAttributeValue(targetAXWindow, "AXFullScreen" as CFString, false as CFTypeRef)
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            }
        }

        manager.moveActiveWindowToSpace(id: targetSpaceID)
        try? await Task.sleep(nanoseconds: 500_000_000)

        if preserveVisibility {
            await reapplyVisibility(originalVisibility, windowID: windowID, pid: pid)
        }

        return true
    }
}
