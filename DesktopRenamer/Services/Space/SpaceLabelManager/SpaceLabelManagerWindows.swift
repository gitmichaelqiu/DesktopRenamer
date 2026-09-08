import AppKit
import Combine
import Foundation

extension SpaceLabelManager {

    func updateGlobalState(
        isDocked: Bool,
        edge: NSRectEdge,
        center: NSPoint,
        sourceWindow: SpaceLabelWindow? = nil
    ) {
        let centerChanged = globalCenterPoint.map {
            $0.x != center.x || $0.y != center.y
        } ?? true
        let stateChanged = globalIsDocked != isDocked
            || globalDockEdge.rawValue != edge.rawValue
            || centerChanged

        self.globalIsDocked = isDocked
        self.globalDockEdge = edge
        self.globalCenterPoint = center

        UserDefaults.standard.set(isDocked, forKey: kGlobalIsDocked)
        UserDefaults.standard.set(Int(edge.rawValue), forKey: kGlobalDockEdge)
        UserDefaults.standard.set(center.x, forKey: kGlobalCenterX)
        UserDefaults.standard.set(center.y, forKey: kGlobalCenterY)

        if stateChanged {
            synchronizeActiveWindows(excluding: sourceWindow)
        }
    }

    /// Applies shared label geometry to every display immediately. A drag on
    /// one active label changes global state without changing the current
    /// Space, so the normal SpaceManager visibility reconciliation does not
    /// run for the other displays.
    private func synchronizeActiveWindows(excluding sourceWindow: SpaceLabelWindow?) {
        for window in activeWindows.values {
            if let sourceWindow, window === sourceWindow {
                continue
            }
            window.syncFromGlobalState()
            window.updateLayout(isCurrentSpace: true, updateFrame: false)
        }
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
        let windows = Array(createdWindows.values) + Array(activeWindows.values)
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

                // Active labels are independent of preview-label hiding. Keep
                // their state synchronized immediately and retry briefly while
                // WindowServer finishes publishing the new current space.
                self.scheduleActiveLabelSynchronization()

                if self.hideWhenSwitching {
                    let visibleUUIDs = self.resolvedVisibleSpaceIDs()
                    let visibleSpaceSetChanged = self.recordVisibleSpaceIDs(visibleUUIDs)
                    let currentSpaceIsVisible = !visibleUUIDs.isEmpty
                        && visibleUUIDs.contains(self.spaceManager?.currentSpaceUUID ?? "")
                    self.suppressPreviewLabelsForTransition(
                        duration: 0.6,
                        reason: "space switch",
                        beginsNewTransition: visibleSpaceSetChanged,
                        transitionCompleted: currentSpaceIsVisible && !SpaceHelper.isSwitching
                    )
                } else {
                    self.updateAllWindowModes(forDisplay: self.spaceManager?.currentDisplayID)
                }

                if !self.hideWhenSwitching {
                    let workItem = DispatchWorkItem { [weak self] in
                        DiagnosticEventLog.shared.record(subsystem: "Labels", level: "info", "delayed restore firing")
                        self?.updateAllWindowModes()
                    }
                    self.delayedRestoreWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: workItem)
                }
            }
            .store(in: &cancellables)

        spaceManager.$spaceNameDict
            .receive(on: DispatchQueue.main)
            .sink { [weak self] spaces in
                guard let self = self else { return }

                let spaceIDs = Set(spaces.map(\.id))
                let spaceLayoutChanged = self.knownSpaceIDs != spaceIDs
                let fullscreenSpaceIDs = Set(spaces.filter(\.isFullscreen).map(\.id))
                let fullscreenLayoutChanged = self.knownFullscreenSpaceIDs != fullscreenSpaceIDs
                self.knownSpaceIDs = spaceIDs
                self.knownFullscreenSpaceIDs = fullscreenSpaceIDs

                // Exiting fullscreen changes the managed-space layout without
                // necessarily changing currentSpaceUUID. Entering fullscreen
                // has the same timing issue: a new preview can be created
                // before WindowServer reports the fullscreen space as current.
                // Use the complete ID set as a fallback because fullscreen
                // metadata can arrive after the new managed space itself.
                if self.hideWhenSwitching && (spaceLayoutChanged || fullscreenLayoutChanged) {
                    self.suppressPreviewLabelsForTransition(
                        duration: 1.2,
                        reason: "space layout transition",
                        beginsNewTransition: true
                    )
                }

                self.recalculateUnifiedSize()
                // When hideWhenSwitching is on, don't restore labels here —
                // the transition suppression work item owns restoration.
                // syncWindowsWithDict still creates and removes windows, it
                // just skips the final updateAllWindowModes.
                self.syncWindowsWithDict(updateModes: self.hideWhenSwitching != true)
            }
            .store(in: &cancellables)

        workspaceSpaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleExternalSpaceTransitionNotification()
            }
        }

        workspaceApplicationActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleApplicationActivationNotification()
            }
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSpaceSwitchRequested),
            name: NSNotification.Name("SpaceSwitchRequested"), object: nil)

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleProgrammaticSpaceSwitchStarted(_:)),
            name: NSNotification.Name("SpaceProgrammaticSwitchStarted"), object: nil)

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSpaceChangeWillReconcile),
            name: NSNotification.Name("SpaceChangeWillReconcile"), object: nil)

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleProgrammaticSpaceTransitionSettled(_:)),
            name: NSNotification.Name("SpaceProgrammaticSwitchSettled"), object: nil)

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSpaceSwitchTargetRequested(_:)),
            name: NSNotification.Name("SpaceSwitchTargetRequested"), object: nil)

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSpaceRearrangementCompleted),
            name: NSNotification.Name("SpaceRearrangementCompleted"), object: nil)

    }

    @objc private func handleSpaceSwitchRequested() {
        cancelLaunchSpaceRestore(reason: "space switch requested")

        // Start suppression at the request boundary, before WindowServer or the
        // reconciliation callbacks can enqueue a visibility refresh. This may
        // be called from GestureManager's background callback, so only hop to
        // the main queue when necessary.
        if Thread.isMainThread {
            beginPreviewSuppressionForSwitchRequest()
        } else {
            // GestureManager posts this from the multitouch callback. Queue
            // the suppression without blocking that callback; the gesture's
            // subsequent main-queue switch request is enqueued after this
            // notification, so preview hiding still happens first.
            DispatchQueue.main.async { [weak self] in
                self?.beginPreviewSuppressionForSwitchRequest()
            }
        }
    }

    @objc private func handleProgrammaticSpaceSwitchStarted(_ notification: Notification) {
        cancelLaunchSpaceRestore(reason: "programmatic space switch started")
    }

    private func cancelLaunchSpaceRestore(reason: String) {
        guard launchSpaceRestoreIsPending || launchSpaceRestoreWorkItem != nil else { return }

        launchSpaceRestoreIsPending = false
        launchSpaceRestoreWorkItem?.cancel()
        launchSpaceRestoreWorkItem = nil
        DiagnosticEventLog.shared.record(
            subsystem: "Labels",
            level: "info",
            "Launch-space restore cancelled: \(reason)"
        )
    }

    func cancelLaunchSpaceRestoreForUserInteraction() {
        cancelLaunchSpaceRestore(reason: "active label interaction started")
    }

    private func beginPreviewSuppressionForSwitchRequest() {
        delayedRestoreWorkItem?.cancel()
        delayedRestoreWorkItem = nil
        if hideWhenSwitching {
            suppressPreviewLabelsForTransition(
                duration: 1.2,
                reason: "space switch requested",
                beginsNewTransition: true
            )
        }
    }

    private func handleExternalSpaceTransitionNotification() {
        if Thread.isMainThread {
            handleConfirmedExternalSpaceTransition()
        } else {
            DispatchQueue.main.sync { [weak self] in
                self?.handleConfirmedExternalSpaceTransition()
            }
        }
    }

    private func handleConfirmedExternalSpaceTransition() {
        guard hideWhenSwitching else { return }

        let visibleSpaceIDs = resolvedVisibleSpaceIDs()
        let didChange = recordVisibleSpaceIDs(visibleSpaceIDs)
        suppressPreviewLabelsForTransition(
            duration: 1.2,
            reason: "active space notification",
            beginsNewTransition: didChange
        )
    }

    @objc private func handleProgrammaticSpaceTransitionSettled(_ notification: Notification) {
        guard hideWhenSwitching else { return }

        let visibleSpaceIDs = resolvedVisibleSpaceIDs()
        guard !visibleSpaceIDs.isEmpty else { return }

        let targetSpaceID = notification.userInfo?["spaceID"] as? String
        guard targetSpaceID == nil || visibleSpaceIDs.contains(targetSpaceID ?? "") else {
            return
        }

        suppressPreviewLabelsForTransition(
            duration: 0.15,
            reason: "programmatic space transition settled",
            transitionCompleted: true
        )
    }

    private func handleApplicationActivationNotification() {
        if Thread.isMainThread {
            processApplicationActivationNotification()
        } else {
            DispatchQueue.main.sync { [weak self] in
                self?.processApplicationActivationNotification()
            }
        }
    }

    private func processApplicationActivationNotification() {
        guard hideWhenSwitching else { return }
        guard !shouldPreservePreviewWindowOrderingForSettings else { return }

        if liveSpaceSetChangedSinceLastObservation() {
            suppressPreviewLabelsForTransition(
                duration: 1.2,
                reason: "application activation space transition",
                beginsNewTransition: true
            )
            return
        }

        // Application activation can arrive before WindowServer updates its
        // Current Space entry. Keep checking the live managed-space set during
        // the handoff instead of relying on one timing-sensitive read. A
        // same-space activation remains untouched because suppression starts
        // only after an actual space-set change is observed.
        applicationActivationTransitionCheckWorkItem?.cancel()
        applicationActivationTransitionGeneration += 1
        scheduleApplicationActivationTransitionCheck(
            attempt: 0,
            generation: applicationActivationTransitionGeneration
        )
    }

    private func scheduleApplicationActivationTransitionCheck(attempt: Int, generation: Int) {
        let delays: [TimeInterval] = [0.05, 0.12, 0.25, 0.45, 0.7, 1.0]
        guard generation == applicationActivationTransitionGeneration,
              attempt < delays.count else {
            applicationActivationTransitionCheckWorkItem = nil
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.checkApplicationActivationSpaceTransition(
                attempt: attempt,
                generation: generation
            )
        }
        applicationActivationTransitionCheckWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delays[attempt], execute: workItem)
    }

    /// Prevent preview panels from becoming activation candidates while the
    /// menu-bar app activates its regular Settings window.
    func beginSettingsWindowPresentation() {
        applicationActivationTransitionCheckWorkItem?.cancel()
        applicationActivationTransitionCheckWorkItem = nil
        applicationActivationTransitionGeneration += 1
        settingsPreviewRestoreWorkItem?.cancel()
        settingsPreviewRestoreWorkItem = nil
        isSettingsWindowOpen = false
        delayedRestoreWorkItem?.cancel()
        delayedRestoreWorkItem = nil
        arePreviewLabelsSuppressedForSettings = true
        hideAllPreviewLabelsForSettingsActivation()
        DiagnosticEventLog.shared.record(
            subsystem: "Labels",
            level: "info",
            "Settings presentation started — suppressing preview labels before app activation"
        )
    }

    /// Restore preview panels after Settings has become the active window.
    func completeSettingsWindowActivation() {
        guard arePreviewLabelsSuppressedForSettings else { return }

        isSettingsWindowOpen = true
        arePreviewLabelsSuppressedForSettings = false
        DiagnosticEventLog.shared.record(
            subsystem: "Labels",
            level: "info",
            "Settings window became key — restoring preview labels"
        )
        DispatchQueue.main.async { [weak self] in
            self?.scheduleSettingsPreviewRestore()
        }
    }

    /// Restore preview panels if Settings closes before its key-window
    /// activation callback is delivered.
    func endSettingsWindowPresentation() {
        let needsRestore = arePreviewLabelsSuppressedForSettings || isSettingsWindowOpen
        settingsPreviewRestoreWorkItem?.cancel()
        settingsPreviewRestoreWorkItem = nil
        arePreviewLabelsSuppressedForSettings = false
        isSettingsWindowOpen = false

        guard needsRestore else { return }
        scheduleSettingsPreviewRestoreAfterClose()
    }

    /// Reconcile previews after Settings closes, but wait for an in-flight
    /// programmatic switch or pending promotion to finish first. A switch can
    /// publish its final space before Settings' close callback is delivered,
    /// so dropping the reconciliation at that boundary can leave previews
    /// hidden indefinitely when transition hiding is disabled.
    private func scheduleSettingsPreviewRestoreAfterClose() {
        settingsPreviewRestoreWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !SpaceHelper.isSwitching,
                  !SpaceHelper.isProgrammaticSwitchPromotionPending else {
                self.scheduleSettingsPreviewRestoreAfterClose()
                return
            }

            self.settingsPreviewRestoreWorkItem = nil
            self.updateAllWindowModes()
        }
        settingsPreviewRestoreWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }

    private func checkApplicationActivationSpaceTransition(attempt: Int, generation: Int) {
        guard hideWhenSwitching,
              generation == applicationActivationTransitionGeneration else { return }
        if !liveSpaceSetChangedSinceLastObservation() {
            scheduleApplicationActivationTransitionCheck(
                attempt: attempt + 1,
                generation: generation
            )
            return
        }

        applicationActivationTransitionCheckWorkItem = nil
        suppressPreviewLabelsForTransition(
            duration: 1.2,
            reason: "application activation space transition",
            beginsNewTransition: true
        )
    }

    private func liveSpaceSetChangedSinceLastObservation() -> Bool {
        let visibleSpaceIDs = resolvedVisibleSpaceIDs()
        guard !visibleSpaceIDs.isEmpty else { return false }

        let currentSpaceID = spaceManager?.currentSpaceUUID ?? ""
        let managerHasStaleCurrentSpace = !currentSpaceID.isEmpty
            && !visibleSpaceIDs.contains(currentSpaceID)
        let didChange = recordVisibleSpaceIDs(visibleSpaceIDs)
        return managerHasStaleCurrentSpace || didChange
    }

    @discardableResult
    func recordVisibleSpaceIDs(_ visibleSpaceIDs: Set<String>) -> Bool {
        guard !visibleSpaceIDs.isEmpty else { return false }

        let didChange = !lastKnownVisibleSpaceIDs.isEmpty
            && visibleSpaceIDs != lastKnownVisibleSpaceIDs
        lastKnownVisibleSpaceIDs = visibleSpaceIDs
        return didChange
    }
}
