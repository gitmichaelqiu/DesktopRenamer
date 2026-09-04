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
                    let visibleUUIDs = SpaceHelper.getVisibleSystemSpaceIDs()
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
        guard launchSpaceRestoreIsPending else { return }

        launchSpaceRestoreIsPending = false
        launchSpaceRestoreWorkItem?.cancel()
        launchSpaceRestoreWorkItem = nil
        DiagnosticEventLog.shared.record(
            subsystem: "Labels",
            level: "info",
            "Launch-space restore cancelled: \(reason)"
        )
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

        let visibleSpaceIDs = SpaceHelper.getVisibleSystemSpaceIDs()
        let didChange = recordVisibleSpaceIDs(visibleSpaceIDs)
        suppressPreviewLabelsForTransition(
            duration: 1.2,
            reason: "active space notification",
            beginsNewTransition: didChange
        )
    }

    @objc private func handleProgrammaticSpaceTransitionSettled(_ notification: Notification) {
        guard hideWhenSwitching else { return }

        let visibleSpaceIDs = SpaceHelper.getVisibleSystemSpaceIDs()
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
    /// menu-bar app presents its regular Settings window.
    func beginSettingsWindowPresentation() {
        applicationActivationTransitionCheckWorkItem?.cancel()
        applicationActivationTransitionCheckWorkItem = nil
        applicationActivationTransitionGeneration += 1
        delayedRestoreWorkItem?.cancel()
        delayedRestoreWorkItem = nil
        arePreviewLabelsSuppressedForSettings = true
        hideAllPreviewLabels()
        DiagnosticEventLog.shared.record(
            subsystem: "Labels",
            level: "info",
            "Settings presentation started — suppressing preview labels before app activation"
        )
    }

    /// Restore preview panels after Settings closes and the app returns to its
    /// menu-bar-only activation policy.
    func endSettingsWindowPresentation() {
        guard arePreviewLabelsSuppressedForSettings else { return }

        arePreviewLabelsSuppressedForSettings = false
        DiagnosticEventLog.shared.record(
            subsystem: "Labels",
            level: "info",
            "Settings presentation ended — restoring preview labels"
        )
        DispatchQueue.main.async { [weak self] in
            self?.updateAllWindowModes()
        }
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
        let visibleSpaceIDs = SpaceHelper.getVisibleSystemSpaceIDs()
        guard !visibleSpaceIDs.isEmpty else { return false }

        let currentSpaceID = spaceManager?.currentSpaceUUID ?? ""
        let managerHasStaleCurrentSpace = !currentSpaceID.isEmpty
            && !visibleSpaceIDs.contains(currentSpaceID)
        let didChange = recordVisibleSpaceIDs(visibleSpaceIDs)
        return managerHasStaleCurrentSpace || didChange
    }

    @discardableResult
    private func recordVisibleSpaceIDs(_ visibleSpaceIDs: Set<String>) -> Bool {
        guard !visibleSpaceIDs.isEmpty else { return false }

        let didChange = !lastKnownVisibleSpaceIDs.isEmpty
            && visibleSpaceIDs != lastKnownVisibleSpaceIDs
        lastKnownVisibleSpaceIDs = visibleSpaceIDs
        return didChange
    }

    @objc private func handleSpaceChangeWillReconcile() {
        guard hideWhenSwitching else { return }

        // SpaceManager publishes spaceNameDict before currentSpaceUUID. This
        // boundary keeps window creation and dictionary-driven refreshes inside
        // the same suppression state as the actual switch.
        suppressPreviewLabelsForTransition(
            duration: 1.2,
            reason: "space reconciliation",
            beginsNewTransition: true
        )
    }

    private func suppressPreviewLabelsForTransition(
        duration: TimeInterval,
        reason: String,
        beginsNewTransition: Bool = false,
        transitionCompleted: Bool = false
    ) {
        let now = Date()
        let hasPendingTransition = previewTransitionRestoreWorkItem != nil
            || previewLabelsSuppressedUntil != nil
        let shouldBeginNewTransition = beginsNewTransition || !hasPendingTransition

        previewTransitionRestoreWorkItem?.cancel()
        previewTransitionRestoreWorkItem = nil
        previewTransitionGeneration += 1
        let generation = previewTransitionGeneration

        if shouldBeginNewTransition {
            previewTransitionRestoreAttempt = 0
            previewTransitionStablePasses = 0
            previewTransitionLastVisibleUUIDs = nil
            previewTransitionCompletionObserved = false
            previewTransitionFallbackDeadline = now.addingTimeInterval(duration)
        } else if !previewTransitionCompletionObserved {
            // Extend an unconfirmed transition when another WindowServer
            // reconciliation pass arrives, but never extend a transition after
            // its active-space notification has confirmed completion.
            let requestedFallback = now.addingTimeInterval(duration)
            previewTransitionFallbackDeadline = max(
                previewTransitionFallbackDeadline ?? .distantPast,
                requestedFallback
            )
        }

        if transitionCompleted {
            let wasAlreadyCompleted = previewTransitionCompletionObserved
            previewTransitionCompletionObserved = true
            if !wasAlreadyCompleted {
                previewTransitionStablePasses = 0
                previewTransitionLastVisibleUUIDs = nil
            }

            // The notification is the completion boundary. Keep a short
            // settling interval for the final WindowServer snapshot instead of
            // waiting out the original blind suppression delay.
            previewLabelsSuppressedUntil = now.addingTimeInterval(0.15)
        } else if !previewTransitionCompletionObserved {
            let requestedSuppressionEnd = now.addingTimeInterval(duration)
            let existingSuppressionEnd = previewLabelsSuppressedUntil ?? .distantPast
            previewLabelsSuppressedUntil = max(existingSuppressionEnd, requestedSuppressionEnd)
        }

        hideAllPreviewLabels()

        DiagnosticEventLog.shared.record(
            subsystem: "Labels",
            level: "info",
            "\(reason) — hiding previews during transition"
        )

        let delay = max(0.01, previewLabelsSuppressedUntil?.timeIntervalSinceNow ?? duration)
        schedulePreviewTransitionRestore(
            after: delay,
            generation: generation,
            reason: reason
        )
    }

    private func schedulePreviewTransitionRestore(
        after delay: TimeInterval,
        generation: Int,
        reason: String
    ) {
        let workItem = DispatchWorkItem { [weak self] in
            self?.attemptPreviewTransitionRestore(generation: generation, reason: reason)
        }
        previewTransitionRestoreWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(0.01, delay),
            execute: workItem
        )
    }

    private func attemptPreviewTransitionRestore(generation: Int, reason: String) {
        guard generation == previewTransitionGeneration else { return }
        guard let suppressionEnd = previewLabelsSuppressedUntil else {
            previewTransitionRestoreWorkItem = nil
            return
        }

        let now = Date()
        if suppressionEnd > now {
            schedulePreviewTransitionRestore(
                after: suppressionEnd.timeIntervalSince(now),
                generation: generation,
                reason: reason
            )
            return
        }

        // If the active-space notification has not arrived yet, keep the
        // previews hidden until the bounded fallback deadline. The short
        // minimum suppression interval above is not a completion signal.
        if !previewTransitionCompletionObserved,
           let fallbackDeadline = previewTransitionFallbackDeadline,
           fallbackDeadline > now {
            schedulePreviewTransitionRestore(
                after: fallbackDeadline.timeIntervalSince(now),
                generation: generation,
                reason: reason
            )
            return
        }

        let visibleUUIDs = SpaceHelper.getVisibleSystemSpaceIDs()
        let currentSpaceID = spaceManager?.currentSpaceUUID ?? ""
        let hasKnownCurrentSpace = !currentSpaceID.isEmpty
        let currentSpaceIsVisible = !hasKnownCurrentSpace || visibleUUIDs.contains(currentSpaceID)
        let liveStateIsStable = !visibleUUIDs.isEmpty
            && currentSpaceIsVisible
            && !SpaceHelper.isSwitching

        if liveStateIsStable && previewTransitionLastVisibleUUIDs == visibleUUIDs {
            previewTransitionStablePasses += 1
        } else {
            previewTransitionStablePasses = 0
        }
        previewTransitionLastVisibleUUIDs = visibleUUIDs
        previewTransitionRestoreAttempt += 1

        // Require two identical, non-transitioning WindowServer snapshots.
        // This prevents a late visibility refresh from reopening previews while
        // macOS is still publishing the destination space. Never fall through
        // to restoration after a fixed number of attempts: doing so reopens
        // previews precisely when a Dock/app activation transition is still
        // reporting stale state.
        let requiredStablePasses = 2
        if previewTransitionStablePasses < requiredStablePasses {
            schedulePreviewTransitionRestore(
                after: liveStateIsStable ? 0.15 : 0.25,
                generation: generation,
                reason: reason
            )
            return
        }

        previewLabelsSuppressedUntil = nil
        previewTransitionRestoreWorkItem = nil
        previewTransitionLastVisibleUUIDs = nil
        previewTransitionCompletionObserved = false
        previewTransitionFallbackDeadline = nil
        DiagnosticEventLog.shared.record(
            subsystem: "Labels",
            level: "info",
            "\(reason) transition settled — restoring previews"
        )
        updateAllWindowModes()
    }

    @objc private func handleSpaceSwitchTargetRequested(_ notification: Notification) {
        let prepareActiveLabel = { [weak self] in
            guard let self = self,
                  let spaceID = notification.userInfo?["spaceID"] as? String,
                  let window = self.activeWindows[spaceID] else { return }

            // This window is already bound to the destination space. Showing
            // it now lets WindowServer reveal it with the destination rather
            // than waiting for a later reconciliation pass.
            window.setActiveVisibility(true, animated: false)
            self.scheduleActiveLabelSynchronization()
        }

        if Thread.isMainThread {
            prepareActiveLabel()
        } else {
            DispatchQueue.main.sync(execute: prepareActiveLabel)
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

        // Window creation/removal changes the set covered by the active-label
        // cache, even when the visible-space set remains unchanged.
        lastActiveVisibilitySpaceIDs = nil

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

        let redundantIDs = Set(createdWindows.keys).union(activeWindows.keys)
            .filter { !validUUIDs.contains($0) }

        for id in redundantIDs {
            if let window = createdWindows[id] {
                window.pendingVisibilityTask?.cancel()
                window.close()
            }
            createdWindows.removeValue(forKey: id)
            if let window = activeWindows[id] {
                window.pendingVisibilityTask?.cancel()
                window.close()
            }
            activeWindows.removeValue(forKey: id)
            print("SpaceLabelManager: Removed redundant window for space \(id)")
        }

        purgeOrphanedLabelWindows(validUUIDs: validUUIDs)
    }

    /// The dictionary is only the manager's bookkeeping. NSWindow can retain
    /// label instances after a rebuild has replaced that bookkeeping, so also
    /// sweep the application's actual windows for duplicates and orphans.
    private func purgeOrphanedLabelWindows(validUUIDs: Set<String>) {
        let registeredWindows = Set(
            (Array(createdWindows.values) + Array(activeWindows.values)).map(ObjectIdentifier.init)
        )
        let applicationLabelWindows = NSApp.windows.compactMap { $0 as? SpaceLabelWindow }

        for window in applicationLabelWindows {
            let isValid = validUUIDs.contains(window.spaceId)
            let isRegistered = registeredWindows.contains(ObjectIdentifier(window))
            let isCanonical = createdWindows[window.spaceId].map { $0 === window } == true
                || activeWindows[window.spaceId].map { $0 === window } == true

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
        let visibleUUIDs = SpaceHelper.getVisibleSystemSpaceIDs()
        applyVisibility(visibleUUIDs, forDisplay: displayID)
    }

    private func scheduleActiveLabelSynchronization() {
        activeSyncWorkItems.forEach { $0.cancel() }
        activeSyncWorkItems.removeAll()

        // CGS can report the old space for a short period after the change
        // notification. These bounded passes keep active labels responsive
        // without coupling them to the preview-label settling delay. The
        // first pass is intentionally asynchronous so a pre-shown destination
        // label is not immediately hidden by a stale CGS snapshot.
        for delay in [0.05, 0.12, 0.25, 0.45, 0.7] {
            let workItem = DispatchWorkItem { [weak self] in
                self?.updateActiveWindowModes()
            }
            activeSyncWorkItems.append(workItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    private func updateActiveWindowModes() {
        let visibleUUIDs = SpaceHelper.getVisibleSystemSpaceIDs()
        updateActiveWindowModes(for: visibleUUIDs)
    }

    private func updateActiveWindowModes(
        for visibleUUIDs: Set<String>,
        displayID: String? = nil,
        force: Bool = false
    ) {
        let eligibleWindows = activeWindows.filter {
            displayID == nil || $0.value.displayID == displayID
        }
        let windowIDs = Set(eligibleWindows.keys)
        let currentLabelNeedsRepair = showActiveLabels
            && eligibleWindows.contains { key, window in
                visibleUUIDs.contains(key)
                    && (!window.isCurrentSpaceLabel || !window.isVisible)
            }
        guard force
            || lastActiveVisibilitySpaceIDs != visibleUUIDs
            || lastActiveVisibilityWindowIDs != windowIDs
            || lastActiveVisibilityDisplayID != displayID
            || currentLabelNeedsRepair else {
            return
        }

        lastActiveVisibilitySpaceIDs = visibleUUIDs
        lastActiveVisibilityWindowIDs = windowIDs
        lastActiveVisibilityDisplayID = displayID
        for (key, window) in eligibleWindows {
            window.setActiveVisibility(visibleUUIDs.contains(key), animated: false)
        }
    }

    func applyVisibility(_ visibleUUIDs: Set<String>, forDisplay displayID: String? = nil) {
        // Every visibility refresh is also a source-independent transition
        // checkpoint. This closes the race where a refresh was queued before
        // NSWorkspace delivered its space-change notification (for example
        // after a notification click or an external app activation).
        let currentSpaceID = spaceManager?.currentSpaceUUID ?? ""
        let managerHasStaleCurrentSpace = !currentSpaceID.isEmpty
            && !visibleUUIDs.isEmpty
            && !visibleUUIDs.contains(currentSpaceID)
        let visibleSpaceSetChanged = recordVisibleSpaceIDs(visibleUUIDs)
        if hideWhenSwitching && (visibleSpaceSetChanged || managerHasStaleCurrentSpace) {
            // A changed visible-space set is the first destination snapshot,
            // not proof that the animation has finished. Keep previews hidden
            // until the current-space publisher confirms the destination and
            // the settling pass observes a stable WindowServer state.
            suppressPreviewLabelsForTransition(
                duration: 1.2,
                reason: "visibility refresh detected space transition",
                beginsNewTransition: visibleSpaceSetChanged
            )
        }

        if let id = displayID {
             print("SpaceLabelManager: applyVisibility(visibleUUIDs: \(visibleUUIDs)) SCOPED to display: \(id)")
        } else {
             print("SpaceLabelManager: applyVisibility(visibleUUIDs: \(visibleUUIDs)) GLOBAL refresh")
        }

        let suppressPreviews = isPreviewTransitionSuppressed
        // During a transition every preview is hidden regardless of fullscreen
        // metadata. Avoid another synchronous managed-space read on this hot
        // path; the stable refresh below still rechecks fullscreen metadata
        // when previews are allowed to return.
        let fullscreenDisplayIDs = suppressPreviews
            ? []
            : currentFullscreenDisplayIDs(
                visibleUUIDs: visibleUUIDs,
                displayID: displayID
            )
        let windowsSnapshot = self.createdWindows

        for (key, window) in windowsSnapshot {
            if let targetDisplay = displayID, window.displayID != targetDisplay {
                continue // Skip windows that are on a different display than the one we are updating
            }

            if suppressPreviews
                || visibleUUIDs.contains(key)
                || fullscreenDisplayIDs.contains(window.displayID) {
                // The active space has its own dedicated label window. Keep
                // the preview window bound to the space, but never visible on
                // the active desktop or over a fullscreen app.
                window.hideImmediately()
            } else {
                window.updateVisibility(animated: false, visibleSpaceIDs: visibleUUIDs)
            }
        }

        updateActiveWindowModes(for: visibleUUIDs, displayID: displayID)
    }

    private func currentFullscreenDisplayIDs(
        visibleUUIDs: Set<String>,
        displayID: String?
    ) -> Set<String> {
        guard let spaceManager = spaceManager else { return [] }

        var fullscreenDisplayIDs = Set<String>(
            spaceManager.spaceNameDict.compactMap { space in
                guard space.isFullscreen,
                      visibleUUIDs.contains(space.id),
                      displayID == nil || displayID == space.displayID else {
                    return nil
                }
                return space.displayID
            }
        )

        // Fullscreen metadata can lag behind the managed-space ID. Refresh the
        // live fallback only when the visible-space set changes; repeated label
        // refreshes during one transition can otherwise perform the same CGS
        // read once per window.
        if visibleUUIDs != lastLiveFullscreenVisibleSpaceIDs
            || displayID != lastLiveFullscreenDisplayScope {
            lastLiveFullscreenVisibleSpaceIDs = visibleUUIDs
            lastLiveFullscreenDisplayScope = displayID
            if let liveState = SpaceHelper.getSystemState() {
                lastLiveFullscreenDisplayIDs = Set<String>(liveState.spaces.compactMap { space in
                    guard space.isFullscreen,
                          visibleUUIDs.contains(space.id),
                          displayID == nil || displayID == space.displayID else {
                        return nil
                    }
                    return space.displayID
                })
            } else {
                lastLiveFullscreenDisplayIDs = []
            }
        }

        fullscreenDisplayIDs.formUnion(lastLiveFullscreenDisplayIDs)
        return fullscreenDisplayIDs
    }

    func hidePreviewLabel(for spaceId: String) {
        if let window = createdWindows[spaceId] {
            window.hideImmediately()
        }
    }

    func hideAllPreviewLabels() {
        DiagnosticEventLog.shared.record(subsystem: "Labels", level: "info", "hideAllPreviewLabels (windows=\(createdWindows.count))")
        for window in createdWindows.values {
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

        let isCurrent = (spaceId == spaceManager.currentSpaceUUID)
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
        print("SpaceLabelManager: Background seeding all labels for Mission Control...")
        let allSpaces = spaceManager.spaceNameDict
        for space in allSpaces {
            ensureWindow(for: space.id, name: space.customName, displayID: space.displayID)
        }
        updateAllWindowModes()
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
