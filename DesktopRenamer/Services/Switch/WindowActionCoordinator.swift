import AppKit

@MainActor
enum WindowActionCoordinator {
    private static var operationTail: Task<Bool, Never>?

    private static func wait(_ nanoseconds: UInt64, operation: String) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: nanoseconds)
            return true
        } catch {
            DiagnosticEventLog.shared.record(
                subsystem: "WindowActions",
                level: "info",
                "Cancelled while waiting to " + operation + "."
            )
            return false
        }
    }

    @discardableResult
    private static func setAXValue(
        _ value: CFTypeRef,
        attribute: String,
        on window: AXUIElement
    ) -> Bool {
        AXUIElementSetAttributeValue(window, attribute as CFString, value) == .success
    }

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

    static func restoreWindowForMove(windowID: Int, pid: Int32) async -> Bool {
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.unhide()
        }
        if let axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid) {
            guard setAXValue(false as CFTypeRef, attribute: kAXMinimizedAttribute, on: axWindow) else {
                return false
            }
        }
        return await wait(300_000_000, operation: "restore the window")
    }

    static func reapplyVisibility(_ state: VisibilityState, windowID: Int, pid: Int32) async -> Bool {
        guard state.isMinimized || state.isHidden else { return true }

        if state.isMinimized {
            var axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid)
            if axWindow == nil {
                if let app = NSRunningApplication(processIdentifier: pid) {
                    app.activate(options: .activateIgnoringOtherApps)
                    guard await wait(400_000_000, operation: "find the minimized window") else {
                        return false
                    }
                    axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid)
                }
            }
            if let targetAXWindow = axWindow {
                guard setAXValue(true as CFTypeRef, attribute: kAXMinimizedAttribute, on: targetAXWindow) else {
                    return false
                }
            } else {
                return false
            }
        }

        if state.isHidden,
           let app = NSRunningApplication(processIdentifier: pid) {
            app.hide()
        }
        return true
    }

    @discardableResult
    static func moveWindow(
        windowID: Int,
        pid: Int32,
        fromSpaceID: String,
        targetSpaceID: String,
        preserveVisibility: Bool = true
    ) async -> Bool {
        let previousOperation = operationTail
        let operation = Task { @MainActor in
            _ = await previousOperation?.value
            guard !Task.isCancelled else { return false }
            return await performMoveWindow(
                windowID: windowID,
                pid: pid,
                fromSpaceID: fromSpaceID,
                targetSpaceID: targetSpaceID,
                preserveVisibility: preserveVisibility
            )
        }
        operationTail = operation

        return await withTaskCancellationHandler(operation: {
            await operation.value
        }, onCancel: {
            operation.cancel()
        })
    }

    private static func performMoveWindow(
        windowID: Int,
        pid: Int32,
        fromSpaceID: String,
        targetSpaceID: String,
        preserveVisibility: Bool
    ) async -> Bool {
        guard fromSpaceID != targetSpaceID else { return true }
        guard let manager = AppDelegate.shared.spaceManager,
              let sourceSpace = manager.spaceNameDict.first(where: { $0.id == fromSpaceID }),
              let targetSpace = manager.spaceNameDict.first(where: { $0.id == targetSpaceID }) else {
            return false
        }

        let originalVisibility = visibilityState(windowID: windowID, pid: pid)

        if manager.currentSpaceUUID != fromSpaceID {
            manager.switchToSpace(sourceSpace, forceInstant: true)
            guard await wait(600_000_000, operation: "switch to the source space") else {
                return false
            }
        }

        if originalVisibility.isMinimized || originalVisibility.isHidden {
            guard await restoreWindowForMove(windowID: windowID, pid: pid) else {
                return false
            }
        }

        SpaceHelper.focusWindow(id: windowID, pid: pid)
        guard await wait(250_000_000, operation: "focus the window") else {
            return false
        }

        if sourceSpace.isFullscreen || targetSpace.isFullscreen {
            if sourceSpace.isFullscreen {
                var axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid)
                if axWindow == nil {
                    if let app = NSRunningApplication(processIdentifier: pid) {
                        app.activate(options: .activateIgnoringOtherApps)
                        guard await wait(400_000_000, operation: "find the fullscreen window") else {
                            return false
                        }
                        axWindow = SpaceHelper.getAXWindow(id: windowID, pid: pid)
                    }
                }
                if let targetAXWindow = axWindow {
                    guard setAXValue(false as CFTypeRef, attribute: "AXFullScreen", on: targetAXWindow) else {
                        return false
                    }
                    guard await wait(1_200_000_000, operation: "exit fullscreen") else {
                        return false
                    }
                } else {
                    return false
                }
            }

            // Exiting fullscreen invalidates the cached source-space classification
            // before SpaceManager receives its reconciliation callback. Move the
            // specific window directly so the stale fullscreen guard cannot discard
            // the request.
            SpaceHelper.dragActiveWindow(to: targetSpaceID, forceInstant: true)
        } else {
            manager.moveActiveWindowToSpace(id: targetSpaceID)
        }
        guard await wait(500_000_000, operation: "move the window") else {
            return false
        }

        if preserveVisibility {
            guard await reapplyVisibility(originalVisibility, windowID: windowID, pid: pid) else {
                return false
            }
        }

        return true
    }
}
