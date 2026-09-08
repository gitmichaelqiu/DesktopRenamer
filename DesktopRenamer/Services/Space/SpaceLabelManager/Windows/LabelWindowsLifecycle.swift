import AppKit
import Combine
import Foundation


extension SpaceLabelManager {

    func updateLabel(for spaceId: String, name: String, verifySpace: Bool = true) {
        guard spaceId != "FULLSCREEN" else { return }

        if !verifySpace {
            let actualDisplayID = spaceManager?.spaceNameDict.first(where: { $0.id == spaceId })?.displayID ?? spaceManager?.currentDisplayID ?? "Main"
            ensureWindow(for: spaceId, name: name, displayID: actualDisplayID)
            return
        }

        Task { @MainActor in
            // FIX: Increase delay to 0.5s (500ms) to ensure macOS space transition (swipe animation)
            // is fully complete before creating the window. This prevents the window from being
            // created on the 'source' desktop instead of the 'destination' fullscreen app.
            try? await Task.sleep(nanoseconds: 500_000_000)

            guard let state = SpaceHelper.getSystemState() else { return }
            if state.currentUUID == spaceId {
                self.ensureWindow(for: spaceId, name: name, displayID: state.displayID)
            }
        }
    }

    // Asserts that a window exists for the specified space, refreshing if already present.
    func ensureWindow(for spaceId: String, name: String, displayID: String, updateMode: Bool = true) {
        let existingWindows = [createdWindows[spaceId], activeWindows[spaceId]].compactMap { $0 }
        if existingWindows.count == 2 {
            if existingWindows.contains(where: { $0.findTargetScreen() == nil || $0.displayID != displayID }) {
                existingWindows.forEach {
                    $0.pendingVisibilityTask?.cancel()
                    $0.close()
                }
                createdWindows.removeValue(forKey: spaceId)
                activeWindows.removeValue(forKey: spaceId)
            } else {
                if updateMode {
                    existingWindows.forEach { $0.refreshAppearance() }
                }
                return
            }
        } else if !existingWindows.isEmpty {
            existingWindows.forEach {
                $0.pendingVisibilityTask?.cancel()
                $0.close()
            }
            createdWindows.removeValue(forKey: spaceId)
            activeWindows.removeValue(forKey: spaceId)
        }
        createWindow(for: spaceId, name: name, displayID: displayID)
    }

    func createWindow(for spaceId: String, name: String, displayID: String) {
        guard let spaceManager = spaceManager else { return }

        // Inherit fullscreen status from the space manager.
        let isFullscreen =
            spaceManager.spaceNameDict.first(where: { $0.id == spaceId })?.isFullscreen ?? false

        let previewWindow = SpaceLabelWindow(
            spaceId: spaceId, name: name, displayID: displayID, isFullscreen: isFullscreen,
            spaceManager: spaceManager, labelManager: self, isActiveLabel: false)
        let activeWindow = SpaceLabelWindow(
            spaceId: spaceId, name: name, displayID: displayID, isFullscreen: isFullscreen,
            spaceManager: spaceManager, labelManager: self, isActiveLabel: true)

        // Do not allow a label for an unavailable external display to fall
        // back onto the main display. A later topology pass will recreate it
        // when macOS exposes the screen.
        guard previewWindow.findTargetScreen() != nil,
              activeWindow.findTargetScreen() != nil else {
            previewWindow.close()
            activeWindow.close()
            return
        }

        createdWindows[spaceId] = previewWindow
        activeWindows[spaceId] = activeWindow

        // Assign both windows before any visibility call can order them. This
        // prevents a background preview from briefly belonging to the launch
        // Space and pulling the application there during startup.
        previewWindow.bindToTargetSpace()
        activeWindow.bindToTargetSpace()

        let isCurrent: Bool
        if let liveSpaceID = spaceManager.currentSpaceIDForLabels(onDisplayID: displayID) {
            isCurrent = liveSpaceID == spaceId
        } else {
            isCurrent = resolvedVisibleSpaceIDs().contains(spaceId)
        }
        activeWindow.setActiveVisibility(isCurrent, animated: false)
        self.recalculateUnifiedSize()
        previewWindow.refreshAppearance()
        if isCurrent {
            previewWindow.hideImmediately()
        }
    }

    func reloadAllWindows() {
        reloadWorkItem?.cancel()
        reloadGeneration += 1
        let generation = reloadGeneration
        removeAllWindows()

        // Display attachment can deliver this command before WindowServer has
        // published the new screens and managed spaces. Refresh the model and
        // rebuild labels in several short, cancellable passes so a stale
        // snapshot cannot become the final label state.
        let workItem = DispatchWorkItem { [weak self] in
            self?.performReloadPass(remainingPasses: 4, generation: generation)
        }
        reloadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }

    private func performReloadPass(remainingPasses: Int, generation: Int) {
        guard generation == reloadGeneration else { return }
        spaceManager?.refreshConnectedDisplays()
        spaceManager?.refreshSpaceState()

        let pass = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard generation == self.reloadGeneration else { return }
            self.syncWindowsWithDict()
            self.updateAllWindowModes()

            guard remainingPasses > 0 else {
                self.reloadWorkItem = nil
                return
            }

            self.performReloadPass(remainingPasses: remainingPasses - 1, generation: generation)
        }
        reloadWorkItem = pass
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: pass)
    }

    /// Removes label windows while WindowServer is rebuilding spaces or displays.
    /// Existing windows can retain stale CGS assignments after sleep/wake, so
    /// they must be recreated after the layout has been reconciled.
    func resetForSystemTransition() {
        delayedRestoreWorkItem?.cancel()
        delayedRestoreWorkItem = nil
        applicationActivationTransitionCheckWorkItem?.cancel()
        applicationActivationTransitionCheckWorkItem = nil
        applicationActivationTransitionGeneration += 1
        previewTransitionRestoreWorkItem?.cancel()
        previewTransitionRestoreWorkItem = nil
        previewTransitionGeneration += 1
        previewTransitionRestoreAttempt = 0
        previewTransitionStablePasses = 0
        previewTransitionLastVisibleUUIDs = nil
        previewTransitionCompletionObserved = false
        previewTransitionFallbackDeadline = nil
        previewLabelsSuppressedUntil = nil
        settingsPreviewRestoreWorkItem?.cancel()
        settingsPreviewRestoreWorkItem = nil
        arePreviewLabelsSuppressedForSettings = false
        isSettingsWindowOpen = false
        activeSyncWorkItems.forEach { $0.cancel() }
        activeSyncWorkItems.removeAll()
        reloadWorkItem?.cancel()
        reloadWorkItem = nil
        reloadGeneration += 1
        removeAllWindows()
    }

    func removeAllWindows() {
        var windows = Array(createdWindows.values) + Array(activeWindows.values)
        let registeredIDs = Set(windows.map(ObjectIdentifier.init))
        for window in NSApp.windows.compactMap({ $0 as? SpaceLabelWindow })
            where !registeredIDs.contains(ObjectIdentifier(window)) {
            windows.append(window)
        }

        for window in windows {
            window.pendingVisibilityTask?.cancel()
            window.pendingVisibilityTask = nil
            window.close()
        }
        createdWindows.removeAll()
        activeWindows.removeAll()
    }


    func seedAllLabels() {
        guard let spaceManager = spaceManager else { return }
        let traceID = SpaceHelper.debugTraceID()
        SpaceHelper.debugTrace(
            traceID,
            "labels seed begin spaces=\(spaceManager.spaceNameDict.map(\.id).joined(separator: ",")), live=\(SpaceHelper.debugFormatSpaceMap(SpaceHelper.getCurrentSpaceIDsByDisplay())), modelCurrent=\(spaceManager.currentSpaceUUID)"
        )
        print("SpaceLabelManager: Background seeding all labels for Mission Control...")
        let allSpaces = spaceManager.spaceNameDict
        for space in allSpaces {
            ensureWindow(for: space.id, name: space.customName, displayID: space.displayID)
        }
        updateAllWindowModes()
        SpaceHelper.debugTrace(
            traceID,
            "labels seed end live=\(SpaceHelper.debugFormatSpaceMap(SpaceHelper.getCurrentSpaceIDsByDisplay())), modelCurrent=\(spaceManager.currentSpaceUUID)"
        )
        restoreLaunchSpaceIfNeeded()

        // SAFETY: 2 seconds after seeding, verify no labels are stranded on the
        // wrong space. Preview labels that failed CGS binding would otherwise
        // cluster on the current desktop.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.verifyLabelBinding()
        }
    }

    private func restoreLaunchSpaceIfNeeded() {
        guard launchSpaceRestoreIsPending else { return }
        guard let launchDisplayID,
              let launchSpaceID,
              !launchDisplayID.isEmpty,
              !launchSpaceID.isEmpty,
              let liveSpaceID = SpaceHelper.getCurrentSpaceID(for: launchDisplayID),
              liveSpaceID != launchSpaceID,
              !SpaceHelper.isSwitching else {
            launchSpaceRestoreIsPending = false
            return
        }

        launchSpaceRestoreIsPending = false
        DiagnosticEventLog.shared.record(
            subsystem: "Labels",
            level: "warning",
            "Initial label setup changed the launch space from \(launchSpaceID) to \(liveSpaceID); restoring the launch space."
        )

        // Label creation can order managed windows on a background Space. Only
        // restore while the same changed Space is still current; a user or app
        // activation that changes Spaces during this handoff must win.
        let workItem = DispatchWorkItem { [weak self, weak spaceManager] in
            guard let self,
                  spaceManager != nil,
                  !SpaceHelper.isSwitching,
                  SpaceHelper.getCurrentSpaceID(for: launchDisplayID) == liveSpaceID else {
                return
            }
            DiagnosticEventLog.shared.record(
                subsystem: "Labels",
                level: "info",
                "Restoring launch space \(launchSpaceID) after initial label setup"
            )
            SpaceHelper.switchToSpace(launchSpaceID, forceInstant: true)
            self.launchSpaceRestoreWorkItem = nil
        }
        launchSpaceRestoreWorkItem?.cancel()
        launchSpaceRestoreWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }

    /// Verifies that preview label windows are assigned to their correct space.
    /// If a preview label is detected on the current space (binding failure),
    /// it is hidden to prevent visual clustering.
    func verifyLabelBinding() {
        guard let currentSpaceID = spaceManager?.currentSpaceUUID else { return }
        for (spaceId, window) in createdWindows {
            guard !window.isActiveMode, window.windowNumber > 0 else { continue }
            let currentSpaces = SpaceHelper.getWindowCurrentSpaces(windowID: window.windowNumber)
            if currentSpaces.isEmpty { continue }
            if currentSpaces.contains(currentSpaceID) && spaceId != currentSpaceID {
                print("SpaceLabelManager: Safety — preview label \(spaceId) found on current space. Hiding.")
                DiagnosticEventLog.shared.record(subsystem: "SpaceLabelManager", level: "warning", "Safety: preview label \(spaceId) on wrong space (current=\(currentSpaceID)). Hiding.")
                if shouldPreservePreviewWindowOrderingForSettings {
                    window.hideForSettingsActivation()
                } else {
                    window.hideImmediately()
                }
            }
        }
    }

    func toggleActiveLabels() {
        showActiveLabels.toggle()
    }

    func togglePreviewLabels() {
        showPreviewLabels.toggle()
    }

    func toggleShowOnDesktop() {
        showOnDesktop.toggle()
    }
}
