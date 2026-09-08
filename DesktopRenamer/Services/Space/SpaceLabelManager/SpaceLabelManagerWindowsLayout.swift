import AppKit
import Combine
import Foundation


extension SpaceLabelManager {

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
        let visibleUUIDs = resolvedVisibleSpaceIDs()
        applyVisibility(visibleUUIDs, forDisplay: displayID)
    }

    func scheduleActiveLabelSynchronization() {
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

    func updateActiveWindowModes() {
        let visibleUUIDs = resolvedVisibleSpaceIDs()
        updateActiveWindowModes(for: visibleUUIDs)
    }

    func updateActiveWindowModes(
        for visibleUUIDs: Set<String>,
        displayID: String? = nil,
        force: Bool = false
    ) {
        let activeSpaceIDs = currentActiveSpaceIDs(fallback: visibleUUIDs)
        let eligibleWindows = activeWindows.filter {
            displayID == nil || $0.value.displayID == displayID
        }
        let windowIDs = Set(eligibleWindows.keys)
        let currentLabelNeedsRepair = showActiveLabels
            && eligibleWindows.contains { key, window in
                activeSpaceIDs.contains(key)
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
            window.setActiveVisibility(activeSpaceIDs.contains(key), animated: false)
        }
    }

    /// Resolves the active Space independently for every display. The
    /// SpaceManager's currentSpaceUUID tracks the display reported by the
    /// latest reconciliation callback, so using it for label visibility can
    /// hide a valid active label on another display or accept a stale snapshot
    /// during a rapid transition.
    private func currentActiveSpaceIDs(fallback visibleUUIDs: Set<String>) -> Set<String> {
        var spaceIDs = Set<String>()
        var fallbackByDisplay: [String: String] = [:]
        let currentSpaceIDs = spaceManager?.currentSpaceIDsForLabels() ?? [:]

        for (spaceID, window) in activeWindows where visibleUUIDs.contains(spaceID) {
            fallbackByDisplay[window.displayID] = spaceID
        }

        for displayID in Set(activeWindows.values.map(\.displayID)) {
            if let liveSpaceID = currentSpaceIDs[displayID] {
                spaceIDs.insert(liveSpaceID)
            } else if let fallbackSpaceID = fallbackByDisplay[displayID] {
                spaceIDs.insert(fallbackSpaceID)
            }
        }

        return spaceIDs.isEmpty ? visibleUUIDs : spaceIDs
    }

}
