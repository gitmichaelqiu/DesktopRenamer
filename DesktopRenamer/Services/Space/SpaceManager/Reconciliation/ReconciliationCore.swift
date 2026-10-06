import AppKit
import Foundation
import SwiftUI
import WidgetKit

extension SpaceManager {
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

        // Programmatic transaction state and the per-display observation
        // fence already reject stale snapshots. A wall-clock manual-switch
        // window cannot distinguish a real user switch immediately after a
        // completed request, so it must not gate reconciliation here.

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

}
