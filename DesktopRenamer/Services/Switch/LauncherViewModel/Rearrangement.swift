import AppKit
import Foundation
import SwiftUI

@MainActor
extension LauncherViewModel {

    func rearrangeSelectedDesktop(direction: DesktopRearrangementDirection) {
        guard activeCommand?.type == .switchToDesktop,
              stagingWindow == nil else { return }

        if isRearrangingSpace {
            pendingRearrangementDirections.append(direction)
            return
        }

        guard !isLauncherBusy else { return }

        let spaces = filteredSpaces
        guard selectedRowIndex >= 0,
              selectedRowIndex < spaces.count,
              let manager = AppDelegate.shared.spaceManager,
              let sourceSpace = currentSpaces.first(where: { $0.id == spaces[selectedRowIndex].id }),
              !sourceSpace.isFullscreen else { return }

        let orderedSpaces = currentSpaces
            .filter { $0.displayID == sourceSpace.displayID && !$0.isFullscreen }
        guard let sourceIndex = orderedSpaces.firstIndex(where: { $0.id == sourceSpace.id }) else { return }

        let sourceID = sourceSpace.id
        let orderedIDs = orderedSpaces.map(\.id)
        let completion: (SpaceRearrangementService.Result) -> Void = { [weak self] result in
            guard let self = self else { return }
            self.rearrangementRecoveryWorkItem?.cancel()
            self.rearrangementRecoveryWorkItem = nil
            self.isRearrangingSpace = false
            self.requestLauncherFieldFocus()
            guard case .success = result else {
                self.pendingRearrangementDirections.removeAll()
                return
            }

            self.applyLocalSpaceOrder(orderedIDs: self.expectedOrder(
                from: orderedIDs,
                sourceIndex: sourceIndex,
                direction: direction
            ), displayID: sourceSpace.displayID)
            self.selectedRowIndex = self.filteredSpaces.firstIndex { $0.id == sourceID } ?? self.selectedRowIndex
            manager.refreshSpaceState()
            self.startNextQueuedRearrangement()
        }

        isRearrangingSpace = true
        scheduleRearrangementRecovery(for: manager)
        switch direction {
        case .up:
            guard sourceIndex > 0 else {
                finishRearrangementRecovery()
                return
            }
            SpaceRearrangementService.shared.rearrange(
                sourceID: sourceID,
                before: orderedIDs[sourceIndex - 1],
                orderedSpaceIDs: orderedIDs,
                displayID: sourceSpace.displayID,
                completion: completion
            )
        case .down:
            guard sourceIndex < orderedIDs.count - 1 else {
                finishRearrangementRecovery()
                return
            }
            if sourceIndex + 2 < orderedIDs.count {
                SpaceRearrangementService.shared.rearrange(
                    sourceID: sourceID,
                    before: orderedIDs[sourceIndex + 2],
                    orderedSpaceIDs: orderedIDs,
                    displayID: sourceSpace.displayID,
                    completion: completion
                )
            } else {
                SpaceRearrangementService.shared.rearrangeToEnd(
                    sourceID: sourceID,
                    orderedSpaceIDs: orderedIDs,
                    displayID: sourceSpace.displayID,
                    completion: completion
                )
            }
        }
    }

    private func startNextQueuedRearrangement() {
        guard activeCommand?.type == .switchToDesktop,
              let nextDirection = pendingRearrangementDirections.first else { return }

        pendingRearrangementDirections.removeFirst()
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.activeCommand?.type == .switchToDesktop else { return }
            self.rearrangeSelectedDesktop(direction: nextDirection)
        }
    }

    private func scheduleRearrangementRecovery(for manager: SpaceManager) {
        rearrangementRecoveryWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self, weak manager] in
            guard let self = self, self.isRearrangingSpace else { return }
            DiagnosticEventLog.shared.record(
                subsystem: "Launcher",
                level: "warning",
                "Rearrangement verification timed out; unlocking launcher"
            )
            self.isRearrangingSpace = false
            self.pendingRearrangementDirections.removeAll()
            self.requestLauncherFieldFocus()
            manager?.refreshSpaceState()
        }
        rearrangementRecoveryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: workItem)
    }

    private func finishRearrangementRecovery() {
        rearrangementRecoveryWorkItem?.cancel()
        rearrangementRecoveryWorkItem = nil
        isRearrangingSpace = false
        pendingRearrangementDirections.removeAll()
        requestLauncherFieldFocus()
    }

    private func expectedOrder(
        from orderedIDs: [String],
        sourceIndex: Int,
        direction: DesktopRearrangementDirection
    ) -> [String] {
        var result = orderedIDs
        let sourceID = result.remove(at: sourceIndex)
        let destinationIndex: Int
        switch direction {
        case .up:
            destinationIndex = sourceIndex - 1
        case .down:
            destinationIndex = min(sourceIndex + 1, result.count)
        }
        result.insert(sourceID, at: destinationIndex)
        return result
    }

    private func applyLocalSpaceOrder(orderedIDs: [String], displayID: String) {
        let spaceByID = Dictionary(uniqueKeysWithValues: currentSpaces.map { ($0.id, $0) })
        let displayIndices = currentSpaces.indices
            .filter { currentSpaces[$0].displayID == displayID && !currentSpaces[$0].isFullscreen }
        let positionNumbers = displayIndices.indices.map { $0 + 1 }

        for (index, spaceID) in orderedIDs.enumerated() {
            guard index < displayIndices.count,
                  index < positionNumbers.count,
                  let space = spaceByID[spaceID] else { continue }

            currentSpaces[displayIndices[index]] = SpaceGroup(
                id: space.id,
                name: space.name,
                displayName: space.displayName,
                num: positionNumbers[index],
                isFullscreen: space.isFullscreen,
                appPath: space.appPath,
                displayID: space.displayID
            )
        }
    }
    
    func executeSimpleCommand(_ type: LauncherCommandType) {
        DiagnosticEventLog.shared.record(subsystem: "Launcher", level: "info", "executeSimpleCommand: \(type.rawValue)")
        switch type {
        case .reloadLabels:
            incrementCommandFrequency(type.rawValue)
            if let labelManager = AppDelegate.shared.statusBarController?.labelManager {
                labelManager.reloadAllWindows()
            }
            closeLauncher()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                HUDWindowController.shared.show(
                    message: NSLocalizedString("Space Labels Reloaded", comment: ""),
                    systemImage: "arrow.clockwise.circle.fill",
                    iconColor: .blue
                )
            }

        case .toggleActiveLabel:
            incrementCommandFrequency(type.rawValue)
            if let labelManager = AppDelegate.shared.statusBarController?.labelManager {
                labelManager.showActiveLabels.toggle()
                let isEnabled = labelManager.showActiveLabels
                let status = isEnabled ? String(localized: "Enabled") : String(localized: "Disabled")
                let msg = String(format: String(localized: "Active Space Label: %@"), status)
                let icon = isEnabled ? "checkmark.circle.fill" : "xmark.circle.fill"
                let color: Color = isEnabled ? .green : .red
                closeLauncher()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    HUDWindowController.shared.show(message: msg, systemImage: icon, iconColor: color)
                }
            } else {
                closeLauncher()
            }

        case .togglePreviewLabel:
            incrementCommandFrequency(type.rawValue)
            if let labelManager = AppDelegate.shared.statusBarController?.labelManager {
                labelManager.showPreviewLabels.toggle()
                let isEnabled = labelManager.showPreviewLabels
                let status = isEnabled ? String(localized: "Enabled") : String(localized: "Disabled")
                let msg = String(format: String(localized: "Preview Space Labels: %@"), status)
                let icon = isEnabled ? "checkmark.circle.fill" : "xmark.circle.fill"
                let color: Color = isEnabled ? .green : .red
                closeLauncher()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    HUDWindowController.shared.show(message: msg, systemImage: icon, iconColor: color)
                }
            } else {
                closeLauncher()
            }

        case .toggleActiveLabelVisibility:
            incrementCommandFrequency(type.rawValue)
            if let labelManager = AppDelegate.shared.statusBarController?.labelManager {
                labelManager.showOnDesktop.toggle()
                let isEnabled = labelManager.showOnDesktop
                let status = isEnabled ? String(localized: "Enabled") : String(localized: "Disabled")
                let msg = String(format: String(localized: "Keep visible on desktop: %@"), status)
                let icon = isEnabled ? "checkmark.circle.fill" : "xmark.circle.fill"
                let color: Color = isEnabled ? .green : .red
                closeLauncher()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    HUDWindowController.shared.show(message: msg, systemImage: icon, iconColor: color)
                }
            } else {
                closeLauncher()
            }

        default:
            break
        }
    }
}
