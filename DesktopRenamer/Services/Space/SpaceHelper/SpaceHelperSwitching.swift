import AppKit
import CoreGraphics
import Foundation

extension SpaceHelper {

    // Core space switching implementation.
    static func switchToSpace(_ spaceID: String, forceInstant: Bool = false) {
        DiagnosticEventLog.shared.record(subsystem: "SpaceHelper", level: "info", "switchToSpace(\(spaceID), forceInstant=\(forceInstant))")
        let switchStartedAt = Date().timeIntervalSince1970

        if !forceInstant {
            guard !isSwitching else { return }
            programmaticSwitchCompletionWorkItem?.cancel()
            programmaticSwitchCompletionWorkItem = nil
            isSwitching = true
            programmaticSwitchDestinationObserved = false
            programmaticSwitchNotificationObserved = false
        }

        lastProgrammaticSwitchTime = switchStartedAt
        lastProgrammaticTargetSpaceID = spaceID
        lastProgrammaticSwitchUsedSLS = false

        // Prepare only the dedicated active label for the destination. Preview
        // labels still follow the existing hideWhenSwitching behavior.
        NotificationCenter.default.post(
            name: NSNotification.Name("SpaceSwitchTargetRequested"),
            object: nil,
            userInfo: ["spaceID": spaceID]
        )

        defer {
            if !forceInstant {
                // SpaceManager normally clears this when WindowServer confirms
                // the destination. Keep a guarded fallback for notifications
                // that macOS drops, without allowing an older switch to clear a
                // newer request's state.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    guard isSwitching,
                          lastProgrammaticSwitchTime == switchStartedAt,
                          lastProgrammaticTargetSpaceID == spaceID else {
                        return
                    }
                    programmaticSwitchCompletionWorkItem?.cancel()
                    programmaticSwitchCompletionWorkItem = nil
                    isSwitching = false
                    programmaticSwitchDestinationObserved = false
                    programmaticSwitchNotificationObserved = false
                }
            }
        }

        NotificationCenter.default.post(
            name: NSNotification.Name("SpaceSwitchRequested"), object: nil)

        // Resolve target space information.
        var targetNum: Int? = nil
        var targetGlobalNum: Int? = nil
        var shouldUseShortcut = true
        var targetIsFullscreen = false

        if let state = getSystemState() {
            if let targetSpace = state.spaces.first(where: { $0.id == spaceID }) {
                targetNum = targetSpace.num
                targetGlobalNum = targetSpace.globalShortcutNum
                targetIsFullscreen = targetSpace.isFullscreen
                
                // CRITICAL FIX: To check if we are ALREADY on the target space, 
                // we must check the current space of the TARGET display, 
                // not the global active display.
                if let liveCurrentID = getCurrentSpaceID(for: targetSpace.displayID) {
                    print("SpaceHelper: switchToSpace check. Live ID: \(liveCurrentID), Target: \(spaceID)")
                    if liveCurrentID == spaceID {
                        print("SpaceHelper: Already on target space \(spaceID). Stopping.")
                        return 
                    }
                }
            }

            // If we are already on the target space, stop.
            if state.currentUUID == spaceID { return }
            
            // Gesture-based Space Switch handling
            // We use the gesture method for all normal switches (no window moving).
            if !isDragging, let targetSpace = state.spaces.first(where: { $0.id == spaceID }) {
                let displayID = targetSpace.displayID
                if let liveCurrentID = getCurrentSpaceID(for: displayID) {
                    let displaySpaces = state.spaces
                        .filter { $0.displayID == displayID }
                        .sorted { $0.num < $1.num }

                    if let currentIndex = displaySpaces.firstIndex(where: { $0.id == liveCurrentID }),
                       let targetIndex = displaySpaces.firstIndex(where: { $0.id == spaceID }) {
                        let steps = targetIndex - currentIndex
                        if steps != 0 {
                            performSpaceSwitchGesture(steps: steps, targetDisplayID: displayID, forceInstant: forceInstant)
                            return
                        }
                    }
                }
            }
        }
        


        if let state = getSystemState(),
            let targetSpace = state.spaces.first(where: { $0.id == spaceID })
        {
            // Note: Native shortcuts (Ctrl+1, Ctrl+2) only map to Desktops.
            if targetSpace.isFullscreen {
                shouldUseShortcut = false
            } else {
                let spacesBefore = state.spaces.filter {
                    $0.displayID == targetSpace.displayID && $0.num < targetSpace.num
                }
                if spacesBefore.contains(where: { $0.isFullscreen }) {
                    shouldUseShortcut = false
                }
            }
        }

        // Attempt to use system Desktop shortcuts (Control + Number).
        // This provides the smoothest transition when available.
        if shouldUseShortcut {
            if let globalNum = targetGlobalNum {
                if isShortcutEnabled(for: globalNum) && simulateDesktopShortcut(for: globalNum) {
                    return
                }
            } else if let localNum = targetNum {
                // Fallback to local num if global is missing (should verify if this is ever needed/correct)
                if isShortcutEnabled(for: localNum) && simulateDesktopShortcut(for: localNum) {
                    return
                }
            }
        }

        // If shortcuts didn't handle it, use our private window activation trick.
        if switchByActivatingOwnWindow(for: spaceID, isFullscreen: targetIsFullscreen) {

            // High-priority fix for Fullscreen Focus:
            // When switching to a Fullscreen space via SpaceLabelWindow, DesktopRenamer initially gets focus.
            // This can cause the OS to revert to the previous space if we don't hand off focus immediately.
            // We must identify the "owner" app of the fullscreen space and activate it.
            // Since we just triggered the visual switch, activating the app now should correctly
            // prioritize the window on the target space (resolving the "multiple windows" ambiguity).
            if targetIsFullscreen {
                if let pid = getOwnerPID(for: spaceID),
                    let app = NSRunningApplication(processIdentifier: pid)
                {

                    // A very short delay ensures the Window Server registers the space switch intent
                    // before we force the app activation.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        app.activate(options: .activateIgnoringOtherApps)
                    }
                }
            }
            return
        }


    }

    /// Records that SpaceManager has read the requested destination from live
    /// WindowServer state. The active-space notification is also required
    /// before the transition is considered complete.
    static func markProgrammaticSwitchComplete(at spaceID: String) {
        guard isSwitching, lastProgrammaticTargetSpaceID == spaceID else { return }
        guard getVisibleSystemSpaceIDs().contains(spaceID) else {
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceHelper",
                level: "info",
                "programmatic destination snapshot is not visible yet at space \(spaceID); waiting for a consistent WindowServer read"
            )
            return
        }
        programmaticSwitchDestinationObserved = true
        guard programmaticSwitchNotificationObserved else {
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceHelper",
                level: "info",
                "programmatic destination observed at space \(spaceID); waiting for active-space notification"
            )
            return
        }

        finishProgrammaticSwitch(at: spaceID)
    }

    /// Records the completion signal emitted by NSWorkspace when the active
    /// space changes. SpaceManager may have observed the destination first, so
    /// either ordering is accepted.
    static func noteActiveSpaceDidChange() {
        guard isSwitching else { return }
        programmaticSwitchNotificationObserved = true
        guard programmaticSwitchDestinationObserved,
              let targetSpaceID = lastProgrammaticTargetSpaceID else { return }

        finishProgrammaticSwitch(at: targetSpaceID)
    }

    private static func finishProgrammaticSwitch(at spaceID: String) {
        guard programmaticSwitchCompletionWorkItem == nil else { return }

        // The first matching WindowServer read and the active-space
        // notification can both arrive before the visual swipe has finished.
        // Keep the transition open for one settling interval, then notify the
        // label manager so it can perform its own stable-state verification.
        let switchStartedAt = lastProgrammaticSwitchTime
        let workItem = DispatchWorkItem {
            programmaticSwitchCompletionWorkItem = nil
            guard isSwitching,
                  lastProgrammaticSwitchTime == switchStartedAt,
                  lastProgrammaticTargetSpaceID == spaceID else {
                return
            }

            isSwitching = false
            programmaticSwitchDestinationObserved = false
            programmaticSwitchNotificationObserved = false
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceHelper",
                level: "info",
                "programmatic switch confirmed at space \(spaceID)"
            )
            NotificationCenter.default.post(
                name: NSNotification.Name("SpaceProgrammaticSwitchSettled"),
                object: nil,
                userInfo: ["spaceID": spaceID]
            )
        }
        programmaticSwitchCompletionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private static func switchByActivatingOwnWindow(for spaceID: String, isFullscreen: Bool) -> Bool
    {
        var targetWindow: SpaceLabelWindow? = nil
        var windowsToHide: [SpaceLabelWindow] = []

        // Identify target and potential conflicting windows.
        for window in NSApp.windows {
            if let labelWindow = window as? SpaceLabelWindow {
                if labelWindow.spaceId == spaceID {
                    // Use the preview window as the activation anchor. The
                    // active label is managed independently by the manager.
                    if !labelWindow.isActiveMode || targetWindow == nil {
                        targetWindow = labelWindow
                    }
                } else if labelWindow.isVisible {
                    // CRITICAL MULTI-MONITOR FIX: Only hide windows on the SAME display.
                    // Hiding windows on other displays causes them to lose focus state
                    // and triggers "snap-back" issues when they are automatically restored.
                    if let target = targetWindow, labelWindow.displayID == target.displayID {
                        windowsToHide.append(labelWindow)
                    } else if targetWindow == nil {
                        // If we haven't found the target yet, we'll collect all visible ones
                        // and filter them after the loop.
                        windowsToHide.append(labelWindow)
                    }
                }
            }
        }
        
        // Final filter if we collected them before finding target
        if let target = targetWindow {
            windowsToHide = windowsToHide.filter { $0.displayID == target.displayID }
        }

        guard let window = targetWindow else { return false }

        // Manage conflicting windows to remove focus ambiguity.
        // For Desktop targets: We hide other windows to remove ambiguity about "Last Active Space".
        // This forces the OS to switch to the target window.
        // For Fullscreen targets: We MUST NOT hide the desktop window. Doing so removes the app's
        // anchor on the main desktop, causing the OS to panic and revert to the previous space.
        // During drag operations labels are already alpha=0 from hideImmediately, so skip.
        if !isFullscreen, !isDragging {
            for other in windowsToHide {
                other.orderOut(nil)
            }
        }

        // Force window activation.
        DiagnosticEventLog.shared.record(subsystem: "SpaceHelper", level: "info", "switchByActivatingOwnWindow space=\(spaceID)")
        window.orderFrontRegardless()
        window.canBecomeKeyOverride = true
        window.makeKey()
        window.canBecomeKeyOverride = false
        NSApp.activate(ignoringOtherApps: true)

        return true
    }
}
