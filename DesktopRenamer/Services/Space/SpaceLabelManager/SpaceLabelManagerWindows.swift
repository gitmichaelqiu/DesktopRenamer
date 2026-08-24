import AppKit
import Combine
import Foundation

extension SpaceLabelManager {

    func updateGlobalState(isDocked: Bool, edge: NSRectEdge, center: NSPoint) {
        self.globalIsDocked = isDocked
        self.globalDockEdge = edge
        self.globalCenterPoint = center

        UserDefaults.standard.set(isDocked, forKey: kGlobalIsDocked)
        UserDefaults.standard.set(Int(edge.rawValue), forKey: kGlobalDockEdge)
        UserDefaults.standard.set(center.x, forKey: kGlobalCenterX)
        UserDefaults.standard.set(center.y, forKey: kGlobalCenterY)
    }

    func saveSettings() {
        UserDefaults.standard.set(activeFontScale, forKey: kActiveFontScale)
        UserDefaults.standard.set(activePaddingScale, forKey: kActivePaddingScale)
        UserDefaults.standard.set(previewFontScale, forKey: kPreviewFontScale)
        UserDefaults.standard.set(previewPaddingScale, forKey: kPreviewPaddingScale)

        UserDefaults.standard.set(showPreviewLabels, forKey: kShowPreviewLabels)
        UserDefaults.standard.set(hideWhenSwitching, forKey: kHideWhenSwitching)
        UserDefaults.standard.set(showActiveLabels, forKey: kShowActiveLabels)
        UserDefaults.standard.set(disablePreviewLiquidGlass, forKey: kDisablePreviewLiquidGlass)
        UserDefaults.standard.set(disableActiveLiquidGlass, forKey: kDisableActiveLiquidGlass)
        UserDefaults.standard.set(showOnDesktop, forKey: kShowOnDesktop)
    }

    func updateWindows() {
        let windows = Array(createdWindows.values)
        for window in windows {
            window.refreshAppearance()
        }
    }


    func setupObservers() {
        guard let spaceManager = spaceManager else { return }

        spaceManager.$currentSpaceUUID
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                // Cancel any pending delayed restore from a previous rapid switch
                // so the old restore doesn't fire in the middle of a new transition.
                self.delayedRestoreWorkItem?.cancel()
                self.delayedRestoreWorkItem = nil

                let isRecentProgrammaticSwitch =
                    Date().timeIntervalSince1970 - SpaceHelper.lastProgrammaticSwitchTime < 1.0
                if self.hideWhenSwitching && isRecentProgrammaticSwitch {
                    self.preserveActiveLabelsDuringSwitch()
                }

                if self.hideWhenSwitching {
                    if isRecentProgrammaticSwitch {
                        DiagnosticEventLog.shared.record(subsystem: "Labels", level: "info", "programmatic switch — hiding labels")
                        self.hideAllPreviewLabels()
                    } else {
                        DiagnosticEventLog.shared.record(subsystem: "Labels", level: "info", "native switch — restoring immediately")
                        self.updateAllWindowModes(forDisplay: self.spaceManager?.currentDisplayID)
                    }
                } else {
                    self.updateAllWindowModes(forDisplay: self.spaceManager?.currentDisplayID)
                }

                let workItem = DispatchWorkItem { [weak self] in
                    // Restore ALL displays — hideAllPreviewLabels hid previews on
                    // every display, and the current display was not restored
                    // either. This unfiltered call is the sole restore point.
                    DiagnosticEventLog.shared.record(subsystem: "Labels", level: "info", "delayed restore firing")
                    self?.updateAllWindowModes()
                    // Allow former active labels to follow normal preview
                    // visibility rules after the transition has settled.
                    DispatchQueue.main.async { [weak self] in
                        self?.createdWindows.values.forEach {
                            $0.preserveVisibilityDuringSwitch = false
                        }
                    }
                }
                self.delayedRestoreWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: workItem)
            }
            .store(in: &cancellables)

        spaceManager.$spaceNameDict
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recalculateUnifiedSize()
                // When hideWhenSwitching is on, don't restore labels here —
                // the settling delay in the currentSpaceUUID observer is
                // the sole restore point. syncWindowsWithDict still creates
                // and removes windows, it just skips the final updateAllWindowModes.
                self?.syncWindowsWithDict(updateModes: self?.hideWhenSwitching != true)
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSpaceSwitchRequested),
            name: NSNotification.Name("SpaceSwitchRequested"), object: nil)

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSpaceSwitchTargetRequested(_:)),
            name: NSNotification.Name("SpaceSwitchTargetRequested"), object: nil)

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSpaceRearrangementCompleted),
            name: NSNotification.Name("SpaceRearrangementCompleted"), object: nil)

    }

    @objc private func handleSpaceSwitchRequested() {
        // Cancel any pending delayed restore from a previous switch at the START
        // of each new switch (before currentSpaceUUID changes), so the old
        // restore never fires mid-transition of the next switch.
        // This may be called from a background thread (GestureManager's MT callback),
        // so dispatch to main for thread-safe access.
        let preserveAndHide = { [weak self] in
            guard let self = self else { return }
            self.delayedRestoreWorkItem?.cancel()
            self.delayedRestoreWorkItem = nil

            // Snapshot active labels before SpaceManager changes their mode to
            // preview. They must remain visible for the duration of the switch.
            self.preserveActiveLabelsDuringSwitch()

            if self.hideWhenSwitching {
                self.hideAllPreviewLabels()
            }
        }

        // GestureManager posts this notification before starting the switch,
        // often from its input thread. Complete the snapshot synchronously so
        // the current active label cannot be reclassified and hidden first.
        if Thread.isMainThread {
            preserveAndHide()
        } else {
            DispatchQueue.main.sync(execute: preserveAndHide)
        }
    }

    @objc private func handleSpaceSwitchTargetRequested(_ notification: Notification) {
        let prepareDestination = { [weak self] in
            guard let self = self,
                  let spaceID = notification.userInfo?["spaceID"] as? String,
                  let window = self.createdWindows[spaceID] else { return }

            window.isTransitionDestination = true
            DiagnosticEventLog.shared.record(
                subsystem: "Labels",
                level: "info",
                "prepared destination label for switch: \(spaceID)"
            )
            // The target is already bound to its destination space. Restore its
            // content now so it is ready when WindowServer reveals that space.
            window.updateVisibility(animated: false)
        }

        if Thread.isMainThread {
            prepareDestination()
        } else {
            DispatchQueue.main.sync(execute: prepareDestination)
        }
    }

    private func preserveActiveLabelsDuringSwitch() {
        for window in createdWindows.values where window.isActiveMode {
            window.preserveVisibilityDuringSwitch = true
        }
    }

    @objc private func handleSpaceRearrangementCompleted() {
        guard showPreviewLabels else { return }

        // Reordering does not change currentSpaceUUID, so the normal space-change
        // observer cannot restore preview labels hidden during the operation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.updateAllWindowModes()
        }
    }

    func syncWindowsWithDict(updateModes: Bool = true) {
        guard let spaceManager = spaceManager else { return }
        let allSpaces = spaceManager.spaceNameDict

        // Add windows for new spaces.
        for space in allSpaces {
            ensureWindow(for: space.id, name: space.customName, displayID: space.displayID, updateMode: updateModes)
        }

        // Remove windows for spaces that no longer exist.
        cleanupRedundantWindows()

        // Only restore label modes when hideWhenSwitching is off.
        if updateModes {
            updateAllWindowModes()
        }
    }

    // Removes windows for obsolete spaces.
    func cleanupRedundantWindows() {
        guard let spaceManager = spaceManager else { return }
        let validUUIDs = Set(spaceManager.spaceNameDict.map { $0.id })

        let redundantIDs = createdWindows.keys.filter { !validUUIDs.contains($0) }

        for id in redundantIDs {
            if let window = createdWindows[id] {
                window.pendingVisibilityTask?.cancel()
                window.close()
            }
            createdWindows.removeValue(forKey: id)
            print("SpaceLabelManager: Removed redundant window for space \(id)")
        }

        purgeOrphanedLabelWindows(validUUIDs: validUUIDs)
    }

    /// The dictionary is only the manager's bookkeeping. NSWindow can retain
    /// label instances after a rebuild has replaced that bookkeeping, so also
    /// sweep the application's actual windows for duplicates and orphans.
    private func purgeOrphanedLabelWindows(validUUIDs: Set<String>) {
        let registeredWindows = Set(createdWindows.values.map(ObjectIdentifier.init))
        let applicationLabelWindows = NSApp.windows.compactMap { $0 as? SpaceLabelWindow }

        for window in applicationLabelWindows {
            let isValid = validUUIDs.contains(window.spaceId)
            let isRegistered = registeredWindows.contains(ObjectIdentifier(window))
            let isCanonical = createdWindows[window.spaceId].map { $0 === window } ?? false

            if !isValid || !isRegistered || !isCanonical {
                window.pendingVisibilityTask?.cancel()
                window.close()
                print("SpaceLabelManager: Closed orphaned label window for space \(window.spaceId)")
            }
        }
    }

    func recalculateUnifiedSize() {
        guard let spaceManager = spaceManager else { return }

        if !Thread.isMainThread {
            Task { @MainActor [weak self] in self?.recalculateUnifiedSize() }
            return
        }

        let pFontScale = previewFontScale.isNaN || previewFontScale <= 0 ? 1.0 : previewFontScale
        let pPadScale =
            previewPaddingScale.isNaN || previewPaddingScale <= 0 ? 1.0 : previewPaddingScale

        let baseFontSize: CGFloat = 180
        let scaledFontSize = baseFontSize * CGFloat(pFontScale)
        let referenceFont = NSFont.systemFont(ofSize: scaledFontSize, weight: .bold)

        var maxWidth: CGFloat = 600
        var maxHeight: CGFloat = 300

        for space in spaceManager.spaceNameDict {
            let name = spaceManager.getSpaceName(space.id)
            let size = name.size(withAttributes: [.font: referenceFont])
            if size.width > maxWidth { maxWidth = size.width }
            if size.height > maxHeight { maxHeight = size.height }
        }

        let basePadH: CGFloat = 200
        let basePadV: CGFloat = 150
        let paddingH = basePadH * CGFloat(pPadScale)
        let paddingV = basePadV * CGFloat(pPadScale)

        var finalSize = NSSize(width: maxWidth + paddingH, height: maxHeight + paddingV)

        if let screen = NSScreen.screens.first {
            finalSize.width = min(finalSize.width, screen.frame.width * 0.95)
            finalSize.height = min(finalSize.height, screen.frame.height * 0.9)
        }

        if finalSize.width.isNaN || finalSize.height.isNaN || finalSize.width < 10
            || finalSize.height < 10
        {
            return
        }

        let windows = Array(createdWindows.values)
        for window in windows {
            window.setPreviewSize(finalSize)
        }
    }

    func updateAllWindowModes(forDisplay displayID: String? = nil) {
        Task { @MainActor in
            let visibleUUIDs = SpaceHelper.getVisibleSystemSpaceIDs()
            self.applyVisibility(visibleUUIDs, forDisplay: displayID)
        }
    }

    func applyVisibility(_ visibleUUIDs: Set<String>, forDisplay displayID: String? = nil) {
        if let id = displayID {
             print("SpaceLabelManager: applyVisibility(visibleUUIDs: \(visibleUUIDs)) SCOPED to display: \(id)")
        } else {
             print("SpaceLabelManager: applyVisibility(visibleUUIDs: \(visibleUUIDs)) GLOBAL refresh")
        }
        
        let windowsSnapshot = self.createdWindows

        for (key, window) in windowsSnapshot {
            if let targetDisplay = displayID, window.displayID != targetDisplay {
                continue // Skip windows that are on a different display than the one we are updating
            }
            
            let isVisibleOnAnyScreen = visibleUUIDs.contains(key)
            if isVisibleOnAnyScreen {
                window.isTransitionDestination = false
            }
            window.setMode(isCurrentSpace: isVisibleOnAnyScreen)
        }
    }

    func hidePreviewLabel(for spaceId: String) {
        if let window = createdWindows[spaceId],
            !window.isActiveMode && !window.preserveVisibilityDuringSwitch {
            window.hideImmediately()
        }
    }

    func hideAllPreviewLabels() {
        DiagnosticEventLog.shared.record(subsystem: "Labels", level: "info", "hideAllPreviewLabels (windows=\(createdWindows.count))")
        for window in createdWindows.values
            where !window.isActiveMode && !window.preserveVisibilityDuringSwitch {
            window.hideImmediately()
        }
    }

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
        if let existingWindow = createdWindows[spaceId] {
            if existingWindow.findTargetScreen() == nil {
                existingWindow.pendingVisibilityTask?.cancel()
                existingWindow.close()
                createdWindows.removeValue(forKey: spaceId)
            } else if existingWindow.displayID != displayID {
                existingWindow.pendingVisibilityTask?.cancel()
                existingWindow.close()
                createdWindows.removeValue(forKey: spaceId)
            } else {
                // BUG FIX: Even if the window exists and is visible, we MUST update its mode
                // (Active vs Preview) and refresh its appearance. Otherwise, labels can
                // get stuck in Preview mode when returning from fullscreen.
                // During a switch (updateMode: false), skip this — setMode + refreshAppearance
                // both call updateVisibility which can make labels visible prematurely.
                if updateMode {
                    let isCurrent = (spaceId == spaceManager?.currentSpaceUUID)
                    existingWindow.setMode(isCurrentSpace: isCurrent)
                    existingWindow.refreshAppearance()
                }
                return
            }
        }
        createWindow(for: spaceId, name: name, displayID: displayID)
    }

    func createWindow(for spaceId: String, name: String, displayID: String) {
        guard let spaceManager = spaceManager else { return }

        // Inherit fullscreen status from the space manager.
        let isFullscreen =
            spaceManager.spaceNameDict.first(where: { $0.id == spaceId })?.isFullscreen ?? false

        let window = SpaceLabelWindow(
            spaceId: spaceId, name: name, displayID: displayID, isFullscreen: isFullscreen,
            spaceManager: spaceManager, labelManager: self)

        // Do not allow a label for an unavailable external display to fall
        // back onto the main display. A later topology pass will recreate it
        // when macOS exposes the screen.
        guard window.findTargetScreen() != nil else {
            window.close()
            return
        }

        createdWindows[spaceId] = window
        let isCurrent = (spaceId == spaceManager.currentSpaceUUID)
        window.setMode(isCurrentSpace: isCurrent)
        self.recalculateUnifiedSize()
        window.refreshAppearance()
        window.bindToTargetSpace()
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
        reloadWorkItem?.cancel()
        reloadWorkItem = nil
        reloadGeneration += 1
        removeAllWindows()
    }

    func removeAllWindows() {
        var windows = Array(createdWindows.values)
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
    }


    func seedAllLabels() {
        guard showPreviewLabels, let spaceManager = spaceManager else { return }
        print("SpaceLabelManager: Background seeding all labels for Mission Control...")
        let allSpaces = spaceManager.spaceNameDict
        for space in allSpaces {
            ensureWindow(for: space.id, name: space.customName, displayID: space.displayID)
        }
        updateAllWindowModes()

        // SAFETY: 2 seconds after seeding, verify no labels are stranded on the
        // wrong space. Preview labels that failed CGS binding would otherwise
        // cluster on the current desktop.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.verifyLabelBinding()
        }
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
                window.hideImmediately()
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
