import AppKit
import Foundation
import SwiftUI
import WidgetKit

extension SpaceManager {

    func refreshConnectedDisplays() {
        self.connectedDisplayUUIDs = Set(SpaceHelper.getAllDisplayUUIDs().map {
            SpaceReconciliationSupport.normalizedDisplayID($0)
        })
        // print("SpaceManager: Refreshed connected displays: \(connectedDisplayUUIDs)")
    }
    
    func refreshSpaceState() {
        guard !isSystemSleeping else { return }
        SpaceHelper.getRawSpaceUUID { [weak self] rawUUID, isDesktop, ncCnt, displayID in
            self?.handleSpaceChange(rawUUID, isDesktop: isDesktop, ncCount: ncCnt, displayID: displayID, source: "Refresh")
        }
    }
    
    func handleSpaceChange(_ rawUUID: String, isDesktop: Bool, ncCount: Int, displayID: String, source: String) {
        DiagnosticEventLog.shared.record(subsystem: "SpaceManager", level: "info", "handleSpaceChange(display=\(displayID), source=\(source))")
        if SpaceHelper.isDragging {
            SpaceHelper.signalSpaceSwitchComplete(arrivedAtSpaceID: rawUUID)
        }
        
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.handleSpaceChange(rawUUID, isDesktop: isDesktop, ncCount: ncCount, displayID: displayID, source: source) }
            return
        }

        guard !isSystemSleeping else { return }

        print("SpaceManager: handleSpaceChange(rawUUID: \(rawUUID), displayID: \(displayID), source: \(source))")

        
        var shouldUpdateWidget = false

        guard let cgsState = SpaceHelper.getSystemState() else {
            if source == "Monitor" { scheduleSpaceChangeRetry() }
            return
        }

        let previousUUID = self.currentSpaceUUID
            
        let now = Date().timeIntervalSince1970
            let isRecentManualSwitch = now - lastManualSwitchTime < 2.0
            
            if isRecentManualSwitch, let targetUUID = lastManualSwitchTargetUUID {
                if cgsState.currentUUID != targetUUID {
                    print("SpaceManager: Stale space \(cgsState.currentUUID) detected during active switch to \(targetUUID) (source: \(source)). Ignoring.")
                    if source == "Monitor" {
                        scheduleSpaceChangeRetry()
                    }
                    return
                }
            }
            
            // First, see which names are already taken by active UUIDs so we don't double-assign.
            var claimedNames: Set<String> = []
            let activeUUIDs = Set(cgsState.spaces.map { $0.id })
            
            for (uuid, name) in nameCache {
                if activeUUIDs.contains(uuid) && !name.isEmpty {
                    claimedNames.insert(name)
                }
            }
            
            var newSpaceList: [DesktopSpace] = []
            
            // Calculate desktop indices per display
            var displayDesktopCounters: [String: Int] = [:]
            var spaceDesktopIndices: [String: Int] = [:]

            for sysSpace in cgsState.spaces {
                if !sysSpace.isFullscreen {
                    let dID = sysSpace.displayID
                    let count = displayDesktopCounters[dID, default: 0] + 1
                    displayDesktopCounters[dID] = count
                    spaceDesktopIndices[sysSpace.id] = count
                }
            }
            
            // Build updated space list and attempt to load names from cache; fullscreen names are not cached.
            for sysSpace in cgsState.spaces {
                var finalSpace = sysSpace
                
                if finalSpace.isFullscreen {
                     // For fullscreen spaces, we do NOT load custom names.
                     // The name will be auto-generated in the numbering pass below.
                     finalSpace.customName = "" // Placeholder
                } else {
                    let dIndex = spaceDesktopIndices[sysSpace.id] ?? 1
                    let indexKey = "\(finalSpace.displayID)|Desktop|\(dIndex)"
                    let legacyIndexKey = "\(finalSpace.displayID)|\(finalSpace.num)"
                    
                    if let cachedName = nameCache[sysSpace.id], !cachedName.isEmpty {
                        finalSpace.customName = cachedName
                    } else {
                        if let fallbackName = SpaceReconciliationSupport.claimAvailableName(
                            from: [indexCache[indexKey], indexCache[legacyIndexKey]],
                            claimedNames: &claimedNames
                        ) {
                            finalSpace.customName = fallbackName
                        } else if let existing = spaceNameDict.first(where: { $0.id == sysSpace.id }), !existing.customName.isEmpty {
                            finalSpace.customName = existing.customName
                            nameCache[sysSpace.id] = existing.customName
                            if indexCache[indexKey]?.isEmpty ?? true {
                                indexCache[indexKey] = existing.customName
                            }
                        }
                    }
                }
                newSpaceList.append(finalSpace)
            }
            
            // Assign names to fullscreen spaces based on their parent application.
            // Spaces are grouped by application name and numbered if multiple instances exist.
            var appGroups: [String: [Int]] = [:]
            
            for (index, space) in newSpaceList.enumerated() {
                if space.isFullscreen {
                    let name = space.appName ?? "Fullscreen"
                    appGroups[name, default: []].append(index)
                }
            }
            
            // Apply names: "Xcode", or "Xcode 1", "Xcode 2"
            for (appName, indices) in appGroups {
                let sortedIndices = indices.sorted { newSpaceList[$0].num < newSpaceList[$1].num }
                
                if sortedIndices.count == 1 {
                    newSpaceList[sortedIndices[0]].customName = appName
                } else {
                    for (i, index) in sortedIndices.enumerated() {
                        newSpaceList[index].customName = "\(appName) \(i + 1)"
                    }
                }
            }

            let knownSpaceIDs = Set(self.spaceNameDict.map { $0.id })
            let newlyCreatedFullscreenSpaces = newSpaceList.filter {
                $0.isFullscreen && !knownSpaceIDs.contains($0.id)
            }
            
            // STABILITY GUARD: Reject partial space lists to prevent corrupting
            // saved state. Transient CGS failures can return fewer spaces,
            // which would erase user data if saved.
            let validation = SpaceReconciliationSupport.validateSnapshot(
                detectedSpaces: newSpaceList,
                cachedSpaces: self.spaceNameDict
            )
            let isInconsistentSnapshot = !validation.isValid

            if !self.spaceNameDict.isEmpty && isInconsistentSnapshot {
                print("SpaceManager: Rejecting inconsistent space list (\(newSpaceList.count) vs cached \(self.spaceNameDict.count)). Skipping update.")
                DiagnosticEventLog.shared.record(subsystem: "SpaceManager", level: "warning", "Rejected inconsistent space snapshot: new=\(newSpaceList.count), cached=\(self.spaceNameDict.count), missingDisplay=\(validation.hasMissingSpacesOnExistingDisplay), duplicateIDs=\(validation.hasDuplicateSpaceIDs), duplicatePositions=\(validation.hasDuplicatePositions), source=\(source), wakeCooling=\(self.isInWakeCoolingPeriod)")
                if !cgsState.currentUUID.isEmpty {
                    self.currentSpaceUUID = cgsState.currentUUID
                }
                if source == "Monitor" {
                    scheduleSpaceChangeRetry()
                }
                return
            }

            if self.spaceNameDict != newSpaceList {
                self.spaceNameDict = newSpaceList
                
                // Refresh missing index entries only. CGS can briefly report a
                // reordered space list after reboot, so automatic detection must
                // not replace explicit desktop-position names.
                var cacheCounters: [String: Int] = [:]
                for space in self.spaceNameDict where !space.isFullscreen {
                    let count = cacheCounters[space.displayID, default: 0] + 1
                    cacheCounters[space.displayID] = count

                    if !space.customName.isEmpty {
                        let key = "\(space.displayID)|Desktop|\(count)"
                        if self.indexCache[key]?.isEmpty ?? true {
                            self.indexCache[key] = space.customName
                        }
                    }
                }
                
                saveData()
                shouldUpdateWidget = true
            }

            if self.autoRearrangeFullscreenSpaces,
               let sourceSpace = self.spaceNameDict.first(where: { $0.id == previousUUID && !$0.isFullscreen }) {
                for fullscreenSpace in newlyCreatedFullscreenSpaces where fullscreenSpace.displayID == sourceSpace.displayID {
                    scheduleFullscreenSpaceRearrangement(
                        fullscreenSpaceID: fullscreenSpace.id,
                        afterSourceSpaceID: sourceSpace.id,
                        displayID: sourceSpace.displayID
                    )
                }
            }
            
            let targetUUID = cgsState.currentUUID

            if previousUUID != targetUUID {
                // Check if previousUUID is in lockedSpaceIDs and this switch is not manual
                if self.lockedSpaceIDs.contains(previousUUID) {
                    let now = Date().timeIntervalSince1970
                    let isOurAppManual = (now - self.lastManualSwitchTime < 2.0) && (targetUUID == self.lastManualSwitchTargetUUID)
                    let isTrackpadManual = now - GestureManager.lastTrackpadSwipeTime < 1.5
                    let isOurAppProgrammatic = (now - SpaceHelper.lastProgrammaticSwitchTime < 2.0) && (targetUUID == SpaceHelper.lastProgrammaticTargetSpaceID)
                    
                    let isManual = isOurAppManual || isTrackpadManual || isOurAppProgrammatic
                    
                    if !isManual {
                        print("SpaceManager: Locked space switch detected from \(previousUUID) to \(targetUUID) (AUTOMATIC)")
                        if let frontApp = NSWorkspace.shared.frontmostApplication {
                            let pid = frontApp.processIdentifier
                            let appName = frontApp.localizedName ?? "App"
                            print("SpaceManager: Automatic switch triggered by \(appName) (PID: \(pid))")
                            
                            // Wait 50ms for the Window Server to settle, then drag-move the active window back to the locked space!
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                if let activeWin = SpaceHelper.getActiveWindowInfo(forPID: pid) {
                                    print("SpaceManager: Physical drag-moving active window \(activeWin.id) to locked space \(previousUUID)")
                                    if let existing = self.movedWindowsOriginalSpaces[activeWin.id] {
                                        if existing.originalSpaceUUID == previousUUID {
                                            self.movedWindowsOriginalSpaces.removeValue(forKey: activeWin.id)
                                            print("SpaceManager: Window \(activeWin.id) returned to original space \(previousUUID). Clearing tracking.")
                                        } else {
                                            self.movedWindowsOriginalSpaces[activeWin.id] = (originalSpaceUUID: existing.originalSpaceUUID, currentSpaceUUID: previousUUID, pid: activeWin.pid)
                                        }
                                    } else {
                                        self.movedWindowsOriginalSpaces[activeWin.id] = (originalSpaceUUID: targetUUID, currentSpaceUUID: previousUUID, pid: activeWin.pid)
                                    }
                                    SpaceHelper.dragActiveWindow(to: previousUUID, forceInstant: true)
                                } else {
                                    print("SpaceManager: Failed to capture active window to drag. Reverting space only.")
                                    if let targetSpaceObj = self.spaceNameDict.first(where: { $0.id == previousUUID }) {
                                        self.switchToSpace(targetSpaceObj, forceInstant: true, isManual: false)
                                    }
                                }
                            }
                        }
                    }
                }
                
                self.currentSpaceUUID = targetUUID
                self.pruneStaleMovedWindows()
                shouldUpdateWidget = true

                // If it was an SLS programmatic space switch, restore focus now
                // that the space change is complete. Native dock-swipe events
                // preserve focus on their own; raising a guessed top window here
                // can reorder the target space unexpectedly.
                let now = Date().timeIntervalSince1970
                let isProgrammatic = SpaceHelper.lastProgrammaticSwitchUsedSLS &&
                                     (now - SpaceHelper.lastProgrammaticSwitchTime < 2.0) &&
                                     (targetUUID == SpaceHelper.lastProgrammaticTargetSpaceID)
                if isProgrammatic {
                    print("SpaceManager: Programmatic space switch confirmed. Restoring focus on Space \(targetUUID).")
                    SpaceHelper.restoreFocusAfterSLSSwitch(spaceID: targetUUID, immediate: true)
                }
            }
            
            if self.currentDisplayID != cgsState.displayID {
                self.currentDisplayID = cgsState.displayID
            }
            self.currentSpaceByDisplay[cgsState.displayID] = cgsState.currentUUID
            if self.currentRawSpaceUUID != cgsState.currentUUID {
                self.currentRawSpaceUUID = cgsState.currentUUID
            }
            
            // Update desktop check based on fullscreen status of the matched space
            let isCurrentDesktop = !(self.spaceNameDict.first(where: { $0.id == self.currentSpaceUUID })?.isFullscreen ?? false)
            if self.currentIsDesktop != isCurrentDesktop {
                self.currentIsDesktop = isCurrentDesktop
                shouldUpdateWidget = true
            }
            
            // If no space change was detected from a monitor event, schedule
            // verification retries. Cmd+Tab can fire notifications before CGS
            // state stabilizes, causing stale labels when hideWhenSwitching is off.
            if previousUUID == self.currentSpaceUUID && source == "Monitor" {
                scheduleSpaceChangeRetry()
            } else {
                cancelSpaceChangeRetry()
            }

        if shouldUpdateWidget { scheduleWidgetUpdate() }
    }

    private func scheduleSpaceChangeRetry() {
        guard !isSystemSleeping else { return }
        guard spaceChangeRetryCount < maxSpaceChangeRetries else { return }
        spaceChangeRetryWorkItem?.cancel()

        let delay = TimeInterval(0.3 + Double(spaceChangeRetryCount) * 0.2)
        spaceChangeRetryCount += 1

        let workItem = DispatchWorkItem { [weak self] in
            self?.performRetryDetection()
        }
        spaceChangeRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func cancelSpaceChangeRetry() {
        spaceChangeRetryWorkItem?.cancel()
        spaceChangeRetryWorkItem = nil
        spaceChangeRetryCount = 0
    }

    private func performRetryDetection() {
        guard !isSystemSleeping else { return }
        guard let cgsState = SpaceHelper.getSystemState() else {
            scheduleSpaceChangeRetry()
            return
        }

        let now = Date().timeIntervalSince1970
        let isRecentManualSwitch = now - lastManualSwitchTime < 2.0
        
        if isRecentManualSwitch {
            if let targetUUID = lastManualSwitchTargetUUID, cgsState.currentUUID == targetUUID {
                if currentSpaceUUID != targetUUID {
                    handleSpaceChange(targetUUID, isDesktop: true, ncCount: 0,
                                     displayID: cgsState.displayID, source: "Retry")
                }
                cancelSpaceChangeRetry()
            } else {
                // Still transitioning, reschedule retry to check again later without reverting
                scheduleSpaceChangeRetry()
            }
        } else {
            if currentSpaceUUID != cgsState.currentUUID {
                handleSpaceChange(cgsState.currentUUID, isDesktop: true, ncCount: 0,
                                 displayID: cgsState.displayID, source: "Retry")
                cancelSpaceChangeRetry()
            } else {
                scheduleSpaceChangeRetry()
            }
        }
    }

    // Debounces widget updates to throttle system load.
    func scheduleWidgetUpdate() {
        widgetUpdateWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.performWidgetUpdate()
        }
        
        widgetUpdateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }
    
    struct WidgetSpace: Codable {
        let id: String
        let name: String
        let num: Int
        let displayID: String
    }

    private func performWidgetUpdate() {
        guard let defaults = UserDefaults(suiteName: SpaceManager.appGroupId) else { return }
        
        let name = getSpaceName(currentSpaceUUID)
        let num = getSpaceNum(currentSpaceUUID)
        // Check if current space is desktop
        let isDesktop = !(spaceNameDict.first(where: { $0.id == currentSpaceUUID })?.isFullscreen ?? false)
        
        // Prepare structured data for Widget
        let sortedSpaces = spaceNameDict.sorted {
            if $0.displayID != $1.displayID {
                return $0.displayID < $1.displayID
            }
            return $0.num < $1.num
        }
        
        let widgetSpaces = sortedSpaces.map { space in
            let defaultName = space.isFullscreen ? (space.appName ?? "Fullscreen") : String(format: NSLocalizedString("Space.DefaultName", comment: ""), space.num)
            return WidgetSpace(
                id: space.id,
                name: space.customName.isEmpty ? defaultName : space.customName,
                num: space.num,
                displayID: space.displayID
            )
        }
        
        var didChange = false

        if let data = try? JSONEncoder().encode(widgetSpaces), defaults.data(forKey: "widget_spacesData") != data {
            defaults.set(data, forKey: "widget_spacesData")
            didChange = true
        }
        
        // Some simple fields for basic widgets to use
        let allSpaceNames = sortedSpaces.map { space in
            if !space.customName.isEmpty { return space.customName }
            return space.isFullscreen ? (space.appName ?? "Fullscreen") : "\(space.num)"
        }
        if defaults.array(forKey: "widget_allSpaces") as? [String] != allSpaceNames {
            defaults.set(allSpaceNames, forKey: "widget_allSpaces")
            didChange = true
        }
        
        if defaults.string(forKey: "widget_spaceName") != name {
            defaults.set(name, forKey: "widget_spaceName")
            didChange = true
        }
        if defaults.object(forKey: "widget_spaceNum") as? Int != num {
            defaults.set(num, forKey: "widget_spaceNum")
            didChange = true
        }
        if defaults.object(forKey: "widget_isDesktop") as? Bool != isDesktop {
            defaults.set(isDesktop, forKey: "widget_isDesktop")
            didChange = true
        }
        if defaults.string(forKey: "widget_currentSpaceUUID") != currentSpaceUUID {
            defaults.set(currentSpaceUUID, forKey: "widget_currentSpaceUUID")
            didChange = true
        }

        if didChange {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    
    func prepareForTermination() {
        widgetUpdateWorkItem?.cancel()
        widgetUpdateWorkItem = nil
        wakeRecoveryWorkItem?.cancel()
        spaceChangeRetryWorkItem?.cancel()
        stopPeriodicSpaceLayoutCheck()
        SpaceHelper.stopMonitoring()
        DistributedNotificationCenter.default().postNotificationName(SpaceAPI.apiToggleNotification, object: nil, userInfo: ["isEnabled": false], deliverImmediately: true)
    }
}
