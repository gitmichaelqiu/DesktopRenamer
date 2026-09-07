import AppKit
import Foundation
import SwiftUI
import WidgetKit

extension SpaceManager {

    /// WindowServer can briefly report a neighboring space while a synthetic
    /// gesture is still settling. The transaction coordinator is authoritative
    /// during that interval; a timestamp is not sufficient because the retry
    /// window can outlive the manual-attribution window.
    private func shouldIgnoreStaleTransactionObservation(_ observedSpaceID: String, source: String) -> Bool {
        guard SpaceHelper.isSwitching,
              let activeTargetSpaceID = SpaceHelper.activeProgrammaticSwitchTargetSpaceID,
              observedSpaceID != activeTargetSpaceID else {
            return false
        }

        let generation = SpaceHelper.activeProgrammaticSwitchGeneration.map(String.init) ?? "nil"
        print("SpaceManager: Stale space \(observedSpaceID) detected during active switch to \(activeTargetSpaceID) (source: \(source)). Ignoring.")
        DiagnosticEventLog.shared.record(
            subsystem: "SpaceManager",
            level: "info",
            "Ignoring stale transaction observation: generation=\(generation), observed=\(observedSpaceID), target=\(activeTargetSpaceID), source=\(source)"
        )

        // Do not schedule a SpaceManager retry while the transaction is still
        // active. The transaction's generation-scoped completion or timeout
        // owns recovery; a retry created here can outlive the transaction and
        // publish the stale observation that was just rejected.
        return true
    }

    /// Handles the active-space notification before the delayed raw-space scan
    /// runs. This is the only path allowed to release a confirmed destination
    /// fence: monitor and retry reads can repeat an old WindowServer snapshot,
    /// while an ordered active-space notification represents a new transition.
    func handleAuthoritativeSpaceChange(_ spacesByDisplay: [String: String]) {
        let traceID = SpaceHelper.debugTraceID()
        SpaceHelper.debugTrace(
            traceID,
            "manager authoritative notification received snapshot=\(SpaceHelper.debugFormatSpaceMap(spacesByDisplay)), modelCurrent=\(currentSpaceUUID), fences=\(confirmedSpaceObservationFence.confirmations.mapValues { $0.spaceID + "/g" + String($0.generation) })"
        )
        let update = { [weak self] in
            guard let self else { return }

            for (displayID, spaceID) in spacesByDisplay {
                guard let confirmation = self.confirmedSpaceObservationFence.confirmation(
                    for: displayID
                ) else {
                    SpaceHelper.debugTrace(
                        traceID,
                        "manager authoritative display=\(displayID), space=\(spaceID), decision=no-fence"
                    )
                    continue
                }

                if spaceID == confirmation.spaceID {
                    self.confirmedSpaceObservationFence.markDestinationObserved(
                        displayID: displayID,
                        spaceID: spaceID
                    )
                    self.currentSpaceByDisplay[displayID] = spaceID
                    SpaceHelper.debugTrace(
                        traceID,
                        "manager authoritative display=\(displayID), space=\(spaceID), decision=mark-confirmed-destination generation=\(confirmation.generation)"
                    )
                    continue
                }

                let recentProgrammaticSwitch = Date().timeIntervalSince1970
                    - SpaceHelper.lastProgrammaticSwitchTime < 2.0
                if recentProgrammaticSwitch,
                   SpaceHelper.lastProgrammaticTargetSpaceID == confirmation.spaceID {
                    SpaceHelper.debugTrace(
                        traceID,
                        "manager authoritative display=\(displayID), space=\(spaceID), decision=ignore-recent-programmatic-confirmation confirmed=\(confirmation.spaceID)"
                    )
                    DiagnosticEventLog.shared.record(
                        subsystem: "SpaceManager",
                        level: "info",
                        "Ignoring superseded programmatic active-space observation: display=\(displayID), observed=\(spaceID), confirmed=\(confirmation.spaceID)"
                    )
                    continue
                }

                guard self.confirmedSpaceObservationFence.clearForExternalObservation(
                    displayID: displayID,
                    spaceID: spaceID
                ) else {
                    SpaceHelper.debugTrace(
                        traceID,
                        "manager authoritative display=\(displayID), space=\(spaceID), decision=ignore-before-destination-observed confirmed=\(confirmation.spaceID)"
                    )
                    DiagnosticEventLog.shared.record(
                        subsystem: "SpaceManager",
                        level: "info",
                        "Ignoring pre-confirmation active-space observation: display=\(displayID), observed=\(spaceID), confirmed=\(confirmation.spaceID)"
                    )
                    continue
                }

                DiagnosticEventLog.shared.record(
                    subsystem: "SpaceManager",
                    level: "info",
                    "Cleared confirmed-space fence after external transition: display=\(displayID), observed=\(spaceID), previous=\(confirmation.spaceID)"
                )
                if self.spaceChangeRetryDisplayID == displayID {
                    self.cancelSpaceChangeRetry()
                }
                SpaceHelper.debugTrace(
                    traceID,
                    "manager authoritative display=\(displayID), space=\(spaceID), decision=clear-fence previous=\(confirmation.spaceID)"
                )
            }
        }

        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }

    /// Returns the space that label windows should treat as current for a
    /// display. A confirmed programmatic destination takes precedence over a
    /// stale CGS read until the active-space notification has observed it.
    func currentSpaceIDForLabels(onDisplayID displayID: String) -> String? {
        currentSpaceIDsForLabels()[displayID]
    }

    /// Reads the visible Space for every display once, then overlays any
    /// confirmed programmatic destinations. Label windows otherwise perform
    /// several independent CGS reads during one refresh and can combine an
    /// old display snapshot with a new one.
    func currentSpaceIDsForLabels() -> [String: String] {
        var currentSpaceIDs = SpaceHelper.getCurrentSpaceIDsByDisplay()
        for displayID in Set(spaceNameDict.map(\.displayID)) {
            if let confirmation = confirmedSpaceObservationFence.confirmation(for: displayID) {
                currentSpaceIDs[displayID] = confirmation.spaceID
            } else if currentSpaceIDs[displayID] == nil,
                      let cachedSpaceID = currentSpaceByDisplay[displayID] {
                currentSpaceIDs[displayID] = cachedSpaceID
            }
        }
        return currentSpaceIDs
    }

    /// Resolves one visible space per display while preserving a confirmed
    /// destination over a stale WindowServer snapshot. This keeps all label
    /// refresh paths on the same authority as SpaceManager reconciliation.
    func visibleSpaceIDsForLabels() -> Set<String> {
        let currentSpaceIDs = currentSpaceIDsForLabels()
        var visibleSpaceIDs = Set(currentSpaceIDs.values)
        if visibleSpaceIDs.isEmpty {
            visibleSpaceIDs = SpaceHelper.getVisibleSystemSpaceIDs()
        }
        let spacesByDisplay = Dictionary(grouping: spaceNameDict, by: \.displayID)

        for (displayID, spaces) in spacesByDisplay {
            guard let currentSpaceID = currentSpaceIDs[displayID] else {
                continue
            }
            visibleSpaceIDs.subtract(spaces.map(\.id))
            visibleSpaceIDs.insert(currentSpaceID)
        }

        return visibleSpaceIDs
    }

    func refreshConnectedDisplays() {
        self.connectedDisplayUUIDs = Set(SpaceHelper.getAllDisplayUUIDs().map { $0.uppercased() })
        // print("SpaceManager: Refreshed connected displays: \(connectedDisplayUUIDs)")
    }
    
    func refreshSpaceState() {
        guard !isSystemSleeping else { return }
        SpaceHelper.getRawSpaceUUID { [weak self] rawUUID, isDesktop, ncCnt, displayID in
            self?.handleSpaceChange(rawUUID, isDesktop: isDesktop, ncCount: ncCnt, displayID: displayID, source: "Refresh")
        }
    }
    
    func handleSpaceChange(
        _ rawUUID: String,
        isDesktop: Bool,
        ncCount: Int,
        displayID: String,
        source: String,
        bypassMonitorCoalescing: Bool = false
    ) {
        DiagnosticEventLog.shared.record(subsystem: "SpaceManager", level: "info", "handleSpaceChange(display=\(displayID), source=\(source))")
        if SpaceHelper.isDragging {
            SpaceHelper.signalSpaceSwitchComplete(arrivedAtSpaceID: rawUUID)
        }
        
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.handleSpaceChange(
                    rawUUID,
                    isDesktop: isDesktop,
                    ncCount: ncCount,
                    displayID: displayID,
                    source: source,
                    bypassMonitorCoalescing: bypassMonitorCoalescing
                )
            }
            return
        }

        guard !isSystemSleeping else { return }

        let traceID = SpaceHelper.debugTraceID()
        let receivedFence = confirmedSpaceObservationFence.confirmation(for: displayID)
            .map { $0.spaceID + "/g" + String($0.generation) } ?? "nil"
        let receivedTarget = SpaceHelper.activeProgrammaticSwitchTargetSpaceID ?? "nil"
        SpaceHelper.debugTrace(
            traceID,
            "manager observation received source=\(source), raw=\(rawUUID), display=\(displayID), bypassCoalescing=\(bypassMonitorCoalescing), modelCurrent=\(currentSpaceUUID), modelByDisplay=\(SpaceHelper.debugFormatSpaceMap(currentSpaceByDisplay)), liveBefore=\(SpaceHelper.debugFormatSpaceMap(SpaceHelper.getCurrentSpaceIDsByDisplay())), fence=\(receivedFence), switching=\(SpaceHelper.isSwitching), target=\(receivedTarget)"
        )

        if source == "Monitor" && !bypassMonitorCoalescing {
            scheduleMonitorSpaceChange(
                rawUUID: rawUUID,
                isDesktop: isDesktop,
                ncCount: ncCount,
                displayID: displayID
            )
            SpaceHelper.debugTrace(
                traceID,
                "manager observation deferred source=Monitor pendingMonitor=\(pendingMonitorSpaceChange?.rawUUID ?? "nil") monitorGeneration=\(monitorSpaceChangeGeneration)"
            )
            return
        }

        print("SpaceManager: handleSpaceChange(rawUUID: \(rawUUID), displayID: \(displayID), source: \(source))")

        
        var shouldUpdateWidget = false

        guard let cgsState = SpaceHelper.getSystemState(onDisplayID: displayID) else {
            SpaceHelper.debugTrace(traceID, "manager observation decision=discard-no-cgs-state source=\(source)")
            if source == "Monitor" { scheduleSpaceChangeRetry(displayID: displayID) }
            return
        }

        let previousUUID = self.currentSpaceUUID
        let targetUUID = cgsState.currentUUID
        let liveSpaceIDsByDisplay = SpaceHelper.getCurrentSpaceIDsByDisplay()
        let fenceDescription = confirmedSpaceObservationFence.confirmation(for: cgsState.displayID)
            .map { $0.spaceID + "/g" + String($0.generation) } ?? "nil"
        let pendingTarget = pendingProgrammaticSpaceSwitches[cgsState.displayID]?.spaceID ?? "nil"
        SpaceHelper.debugTrace(
            traceID,
            "manager snapshot source=\(source), cgsCurrent=\(targetUUID), cgsDisplay=\(cgsState.displayID), cgsSpaces=\(cgsState.spaces.map(\.id).joined(separator: ",")), liveAfter=\(SpaceHelper.debugFormatSpaceMap(liveSpaceIDsByDisplay)), fence=\(fenceDescription), pending=\(pendingTarget)"
        )

        if source == "Monitor" || source == "Retry" || source == "Refresh" {
            let authoritativeLiveSpaceID = SpaceHelper.getCurrentSpaceID(for: cgsState.displayID)

            if let pending = pendingProgrammaticSpaceSwitches[cgsState.displayID],
               pending.spaceID == targetUUID,
               authoritativeLiveSpaceID == targetUUID {
                confirmSpaceObservation(
                    displayID: cgsState.displayID,
                    spaceID: targetUUID,
                    generation: pending.generation
                )
            }

            let existingConfirmation = confirmedSpaceObservationFence.confirmation(
                for: cgsState.displayID
            )
            if targetUUID == existingConfirmation?.spaceID {
                confirmedSpaceObservationFence.markDestinationObserved(
                    displayID: cgsState.displayID,
                    spaceID: targetUUID
                )
            }
            if confirmedSpaceObservationFence.shouldIgnore(
                displayID: cgsState.displayID,
                observedSpaceID: targetUUID,
                liveSpaceID: authoritativeLiveSpaceID
            ) {
                DiagnosticEventLog.shared.record(
                    subsystem: "SpaceManager",
                    level: "info",
                    "Ignoring stale space observation: display=\(cgsState.displayID), observed=\(targetUUID), live=\(authoritativeLiveSpaceID ?? "nil"), confirmed=\(existingConfirmation?.spaceID ?? "nil"), source=\(source)"
                )

                if self.spaceChangeRetryDisplayID == cgsState.displayID {
                    cancelSpaceChangeRetry()
                }
                SpaceHelper.debugTrace(
                    traceID,
                    "manager observation decision=ignore-confirmed-fence observed=\(targetUUID), live=\(authoritativeLiveSpaceID ?? "nil"), source=\(source)"
                )
                return
            }

            // A monitor snapshot and the independent live query can overlap
            // while WindowServer is settling. Never publish the snapshot when
            // the authoritative read already identifies a different Space.
            if let authoritativeLiveSpaceID,
               authoritativeLiveSpaceID != targetUUID {
                DiagnosticEventLog.shared.record(
                    subsystem: "SpaceManager",
                    level: "info",
                    "Ignoring inconsistent space observation: display=\(cgsState.displayID), state=\(targetUUID), live=\(authoritativeLiveSpaceID), source=\(source)"
                )
                scheduleSpaceChangeRetry(displayID: cgsState.displayID)
                SpaceHelper.debugTrace(
                    traceID,
                    "manager observation decision=ignore-inconsistent-snapshot state=\(targetUUID), live=\(authoritativeLiveSpaceID), source=\(source)"
                )
                return
            }
        }

        if shouldIgnoreStaleTransactionObservation(targetUUID, source: source) {
            SpaceHelper.debugTrace(
                traceID,
                "manager observation decision=ignore-active-transaction observed=\(targetUUID), activeTarget=\(SpaceHelper.activeProgrammaticSwitchTargetSpaceID ?? "nil"), source=\(source)"
            )
            return
        }

        let isIntentionalWindowMove = SpaceHelper.consumeWindowMoveIntent(for: targetUUID)
            
        let now = Date().timeIntervalSince1970
            let isRecentManualSwitch = now - lastManualSwitchTime < 2.0
            
            if isRecentManualSwitch, let targetUUID = lastManualSwitchTargetUUID {
                if cgsState.currentUUID != targetUUID {
                    print("SpaceManager: Stale space \(cgsState.currentUUID) detected during active switch to \(targetUUID) (source: \(source)). Ignoring.")
                    if source == "Monitor" {
                        scheduleSpaceChangeRetry(displayID: displayID)
                    }
                    SpaceHelper.debugTrace(
                        traceID,
                        "manager observation decision=ignore-manual-attribution observed=\(cgsState.currentUUID), expected=\(targetUUID), source=\(source)"
                    )
                    return
                }
            }

            // A programmatic switch can expose its destination in one
            // WindowServer snapshot before the transition settles, then
            // briefly report the source space again. Do not publish the
            // destination from that first observation. The switch helper
            // verifies it independently and the completion handler refreshes
            // the model after confirmation.
            if SpaceHelper.isSwitching,
               SpaceHelper.activeProgrammaticSwitchTargetSpaceID == targetUUID {
                SpaceHelper.debugTrace(
                    traceID,
                    "manager observation decision=hold-for-programmatic-completion target=\(targetUUID), source=\(source)"
                )
                SpaceHelper.markProgrammaticSwitchComplete(at: targetUUID)
                return
            }
            
            // First, see which names are already taken by active UUIDs so we don't double-assign.
            var claimedNames: Set<String> = []
            for space in cgsState.spaces where !space.isFullscreen {
                if let persistentID = space.persistentID,
                   let name = nameCache[Self.persistentNameCacheKey(for: persistentID)],
                   !name.isEmpty {
                    claimedNames.insert(name)
                } else if !shouldRestoreNamesByPositionAfterBoot,
                          let name = nameCache[space.id],
                          !name.isEmpty {
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

                    let persistentName = finalSpace.persistentID.flatMap {
                        nameCache[Self.persistentNameCacheKey(for: $0)]
                    }
                    let positionalName = indexCache[indexKey]
                    let legacyPositionalName = indexCache[legacyIndexKey]
                    let managedIDName = shouldRestoreNamesByPositionAfterBoot
                        ? nil
                        : nameCache[sysSpace.id]

                    if let persistentName, !persistentName.isEmpty {
                        finalSpace.customName = persistentName
                    } else if let managedIDName, !managedIDName.isEmpty {
                        finalSpace.customName = managedIDName
                    } else if let positionalName,
                              !positionalName.isEmpty,
                              !claimedNames.contains(positionalName) {
                        finalSpace.customName = positionalName
                    } else if let legacyPositionalName,
                              !legacyPositionalName.isEmpty,
                              !claimedNames.contains(legacyPositionalName) {
                        finalSpace.customName = legacyPositionalName
                    } else if !shouldRestoreNamesByPositionAfterBoot,
                              let existing = spaceNameDict.first(where: { $0.id == sysSpace.id }),
                              !existing.customName.isEmpty {
                        finalSpace.customName = existing.customName
                    }

                    if !finalSpace.customName.isEmpty {
                        claimedNames.insert(finalSpace.customName)
                        nameCache[finalSpace.id] = finalSpace.customName
                        if let persistentID = finalSpace.persistentID {
                            nameCache[Self.persistentNameCacheKey(for: persistentID)] =
                                finalSpace.customName
                        }
                        if indexCache[indexKey]?.isEmpty ?? true {
                            indexCache[indexKey] = finalSpace.customName
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
            let isPartialList = !self.spaceNameDict.isEmpty && newSpaceList.count < self.spaceNameDict.count
            if isPartialList && (self.isInWakeCoolingPeriod || newSpaceList.count <= 1) {
                print("SpaceManager: Rejecting partial space list (\(newSpaceList.count) vs cached \(self.spaceNameDict.count)). Skipping update.")
                DiagnosticEventLog.shared.record(subsystem: "SpaceManager", level: "warning", "Rejected partial space list: new=\(newSpaceList.count), cached=\(self.spaceNameDict.count), source=\(source), wakeCooling=\(self.isInWakeCoolingPeriod)")
                if !cgsState.currentUUID.isEmpty {
                    self.currentSpaceUUID = cgsState.currentUUID
                }
                return
            }

            // The space list publisher is delivered independently from the
            // current-space publisher. Tell the label manager before publishing
            // the list so creating or refreshing a preview cannot bypass the
            // switch-transition suppression window.
            if previousUUID != targetUUID {
                NotificationCenter.default.post(
                    name: NSNotification.Name("SpaceChangeWillReconcile"),
                    object: nil
                )
            }

            let completesBootNameMigration = shouldRestoreNamesByPositionAfterBoot
            let spaceListChanged = self.spaceNameDict != newSpaceList
            if spaceListChanged {
                self.spaceNameDict = newSpaceList
            }

            if spaceListChanged || completesBootNameMigration {
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

                if completesBootNameMigration {
                    completeBootNameMigration(using: self.spaceNameDict)
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
            
            if previousUUID != targetUUID {
                // Check if previousUUID is in lockedSpaceIDs and this switch is not manual
                // A synthetic window drag intentionally changes spaces. Do not
                // treat its destination as an external escape from a locked
                // space, or the recovery path will immediately drag the same
                // window back to the source space.
                if self.lockedSpaceIDs.contains(previousUUID),
                   !SpaceHelper.isDragging,
                   !isIntentionalWindowMove {
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

            }

            self.currentSpaceByDisplay[cgsState.displayID] = targetUUID

            // Record the destination observation. SpaceHelper also waits for
            // the matching active-space notification before declaring the
            // programmatic transition complete.
            SpaceHelper.markProgrammaticSwitchComplete(at: targetUUID)
            
            if self.currentDisplayID != cgsState.displayID {
                self.currentDisplayID = cgsState.displayID
            }
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
                scheduleSpaceChangeRetry(displayID: displayID)
            } else {
                cancelSpaceChangeRetry()
            }

            SpaceHelper.debugTrace(
                traceID,
                "manager observation decision=publish previousModel=\(previousUUID), published=\(targetUUID), modelCurrentNow=\(self.currentSpaceUUID), modelByDisplayNow=\(SpaceHelper.debugFormatSpaceMap(self.currentSpaceByDisplay)), source=\(source)"
            )

        if shouldUpdateWidget { scheduleWidgetUpdate() }
    }

    private func scheduleMonitorSpaceChange(
        rawUUID: String,
        isDesktop: Bool,
        ncCount: Int,
        displayID: String
    ) {
        pendingMonitorSpaceChange = (rawUUID, isDesktop, ncCount, displayID)
        let traceID = SpaceHelper.debugTraceID()
        SpaceHelper.debugTrace(
            traceID,
            "monitor observation queued raw=\(rawUUID), display=\(displayID), existingWork=\(monitorSpaceChangeWorkItem != nil), nextGeneration=\(monitorSpaceChangeGeneration + 1)"
        )
        guard monitorSpaceChangeWorkItem == nil else {
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceManager",
                level: "info",
                "coalesced monitor observation: display=\(displayID)"
            )
            return
        }

        monitorSpaceChangeGeneration += 1
        let generation = monitorSpaceChangeGeneration
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  generation == self.monitorSpaceChangeGeneration else {
                return
            }

            self.monitorSpaceChangeWorkItem = nil
            guard let pending = self.pendingMonitorSpaceChange else { return }
            self.pendingMonitorSpaceChange = nil
            SpaceHelper.debugTrace(
                traceID,
                "monitor observation executing generation=\(generation), raw=\(pending.rawUUID), display=\(pending.displayID)"
            )
            self.handleSpaceChange(
                pending.rawUUID,
                isDesktop: pending.isDesktop,
                ncCount: pending.ncCount,
                displayID: pending.displayID,
                source: "Monitor",
                bypassMonitorCoalescing: true
            )
        }

        monitorSpaceChangeWorkItem = workItem
        // A single short run-loop interval absorbs duplicate WindowServer
        // notifications but does not add a perceptible delay to a gesture.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: workItem)
    }

    func cancelPendingMonitorSpaceChange() {
        if monitorSpaceChangeWorkItem != nil || pendingMonitorSpaceChange != nil {
            SpaceHelper.debugTrace(
                SpaceHelper.debugTraceID(),
                "monitor observation canceled generation=\(monitorSpaceChangeGeneration), pendingRaw=\(pendingMonitorSpaceChange?.rawUUID ?? "nil"), pendingDisplay=\(pendingMonitorSpaceChange?.displayID ?? "nil")"
            )
        }
        monitorSpaceChangeGeneration += 1
        monitorSpaceChangeWorkItem?.cancel()
        monitorSpaceChangeWorkItem = nil
        pendingMonitorSpaceChange = nil
    }

    func scheduleSpaceChangeRetry(displayID: String? = nil) {
        guard !isSystemSleeping else { return }
        guard spaceChangeRetryCount < maxSpaceChangeRetries else { return }
        if let displayID {
            spaceChangeRetryDisplayID = displayID
        }
        spaceChangeRetryWorkItem?.cancel()
        spaceChangeRetryGeneration += 1
        let generation = spaceChangeRetryGeneration

        let delay = TimeInterval(0.3 + Double(spaceChangeRetryCount) * 0.2)
        spaceChangeRetryCount += 1
        let traceID = SpaceHelper.debugTraceID()
        SpaceHelper.debugTrace(
            traceID,
            "retry scheduled generation=\(generation), display=\(spaceChangeRetryDisplayID ?? "nil"), count=\(spaceChangeRetryCount), delay=\(String(format: "%.2f", delay)), fence=\(spaceChangeRetryDisplayID.flatMap { confirmedSpaceObservationFence.confirmation(for: $0)?.spaceID } ?? "nil")"
        )

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self,
                  generation == self.spaceChangeRetryGeneration else { return }
            SpaceHelper.debugTrace(
                traceID,
                "retry executing generation=\(generation), display=\(self.spaceChangeRetryDisplayID ?? "nil")"
            )
            self.performRetryDetection(generation: generation)
        }
        spaceChangeRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func cancelSpaceChangeRetry() {
        spaceChangeRetryWorkItem?.cancel()
        spaceChangeRetryWorkItem = nil
        spaceChangeRetryGeneration += 1
        spaceChangeRetryCount = 0
        spaceChangeRetryObservedSpaceID = nil
        spaceChangeRetryObservedPasses = 0
        spaceChangeRetryDisplayID = nil
    }

    private func performRetryDetection(generation: Int) {
        guard !isSystemSleeping,
              generation == spaceChangeRetryGeneration else { return }
        let traceID = SpaceHelper.debugTraceID()
        guard let cgsState = SpaceHelper.getSystemState(onDisplayID: spaceChangeRetryDisplayID) else {
            SpaceHelper.debugTrace(traceID, "retry decision=reschedule-no-cgs-state generation=\(generation)")
            scheduleSpaceChangeRetry()
            return
        }

        // A WindowServer query may overlap a newer monitor observation or a
        // newly started switch. Cancellation cannot stop a work item that is
        // already executing, so reject its result again after the read.
        guard generation == spaceChangeRetryGeneration else { return }
        let liveSpaceID = SpaceHelper.getCurrentSpaceID(for: cgsState.displayID)
        SpaceHelper.debugTrace(
            traceID,
            "retry snapshot generation=\(generation), cgsCurrent=\(cgsState.currentUUID), display=\(cgsState.displayID), live=\(liveSpaceID ?? "nil"), fence=\(confirmedSpaceObservationFence.confirmation(for: cgsState.displayID)?.spaceID ?? "nil"), modelCurrent=\(currentSpaceUUID)"
        )

        if let confirmation = confirmedSpaceObservationFence.confirmation(
            for: cgsState.displayID
        ) {
            if cgsState.currentUUID == confirmation.spaceID {
                confirmedSpaceObservationFence.markDestinationObserved(
                    displayID: cgsState.displayID,
                    spaceID: cgsState.currentUUID
                )
            } else {
                DiagnosticEventLog.shared.record(
                    subsystem: "SpaceManager",
                    level: "info",
                    "Ignoring retry behind confirmed destination: display=\(cgsState.displayID), observed=\(cgsState.currentUUID), confirmed=\(confirmation.spaceID)"
                )
                if spaceChangeRetryDisplayID == cgsState.displayID {
                    cancelSpaceChangeRetry()
                }
                SpaceHelper.debugTrace(
                    traceID,
                    "retry decision=discard-behind-fence observed=\(cgsState.currentUUID), confirmed=\(confirmation.spaceID)"
                )
                return
            }
        }

        if shouldIgnoreStaleTransactionObservation(cgsState.currentUUID, source: "Retry") {
            SpaceHelper.debugTrace(traceID, "retry decision=discard-active-transaction observed=\(cgsState.currentUUID)")
            return
        }

        // A retry is specifically for a stale or incomplete monitor event.
        // Do not reconcile from a snapshot whose current space is not one of
        // the spaces WindowServer currently exposes as visible. During Dock
        // activation and animated switches these two CGS reads can briefly
        // disagree; accepting the older snapshot would move the model back to
        // the source space and reopen its preview label.
        let visibleSpaceIDs = SpaceHelper.getVisibleSystemSpaceIDs()
        guard generation == spaceChangeRetryGeneration else { return }
        guard !visibleSpaceIDs.isEmpty,
              visibleSpaceIDs.contains(cgsState.currentUUID) else {
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceManager",
                level: "info",
                "Ignoring inconsistent space retry: current=\(cgsState.currentUUID), visible=\(visibleSpaceIDs.sorted())"
            )
            scheduleSpaceChangeRetry()
            SpaceHelper.debugTrace(
                traceID,
                "retry decision=reschedule-not-visible current=\(cgsState.currentUUID), visible=\(visibleSpaceIDs.sorted())"
            )
            return
        }

        let independentlyObservedSpaceID = SpaceHelper.getCurrentSpaceID(for: cgsState.displayID)
        guard generation == spaceChangeRetryGeneration else { return }
        if let independentlyObservedSpaceID,
           independentlyObservedSpaceID != cgsState.currentUUID {
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceManager",
                level: "info",
                "Ignoring inconsistent space retry read: state=\(cgsState.currentUUID), independent=\(independentlyObservedSpaceID), display=\(cgsState.displayID)"
            )
            scheduleSpaceChangeRetry()
            SpaceHelper.debugTrace(
                traceID,
                "retry decision=reschedule-live-mismatch state=\(cgsState.currentUUID), independent=\(independentlyObservedSpaceID)"
            )
            return
        }

        if spaceChangeRetryObservedSpaceID == cgsState.currentUUID {
            spaceChangeRetryObservedPasses += 1
        } else {
            spaceChangeRetryObservedSpaceID = cgsState.currentUUID
            spaceChangeRetryObservedPasses = 1
        }

        guard spaceChangeRetryObservedPasses >= 2 else {
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceManager",
                level: "info",
                "Waiting for stable space retry candidate: current=\(cgsState.currentUUID), pass=\(spaceChangeRetryObservedPasses)/2"
            )
            scheduleSpaceChangeRetry()
            SpaceHelper.debugTrace(
                traceID,
                "retry decision=reschedule-unstable candidate=\(cgsState.currentUUID), pass=\(spaceChangeRetryObservedPasses)/2"
            )
            return
        }

        // Do not let an old retry commit after a transaction-start observer or
        // a newer retry chain invalidated it during the stability checks.
        guard generation == spaceChangeRetryGeneration else { return }

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
        SpaceHelper.debugTrace(
            traceID,
            "retry decision=complete generation=\(generation), candidate=\(cgsState.currentUUID), modelCurrentNow=\(currentSpaceUUID)"
        )
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
        
        if let data = try? JSONEncoder().encode(widgetSpaces) {
            defaults.set(data, forKey: "widget_spacesData")
        }
        
        // Some simple fields for basic widgets to use
        let allSpaceNames = sortedSpaces.map { space in
            if !space.customName.isEmpty { return space.customName }
            return space.isFullscreen ? (space.appName ?? "Fullscreen") : "\(space.num)"
        }
        defaults.set(allSpaceNames, forKey: "widget_allSpaces")
        
        defaults.set(name, forKey: "widget_spaceName")
        defaults.set(num, forKey: "widget_spaceNum")
        defaults.set(isDesktop, forKey: "widget_isDesktop")
        defaults.set(currentSpaceUUID, forKey: "widget_currentSpaceUUID")

        WidgetCenter.shared.reloadAllTimelines()
    }
    
    func prepareForTermination() {
        wakeRecoveryWorkItem?.cancel()
        spaceChangeRetryWorkItem?.cancel()
        stopPeriodicSpaceLayoutCheck()
        SpaceHelper.stopMonitoring()
        DistributedNotificationCenter.default().postNotificationName(SpaceAPI.apiToggleNotification, object: nil, userInfo: ["isEnabled": false], deliverImmediately: true)
    }
}
