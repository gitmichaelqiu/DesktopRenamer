import AppKit
import Foundation
import SwiftUI
import WidgetKit

extension SpaceManager {

    // MARK: - Diagnostic Report Accessors

    /// Returns a human-readable description of the last wake time, including
    /// remaining cooling time if we are still in the post-wake stabilization window.
    var lastWakeTimeAgo: String {
        let elapsed = Date().timeIntervalSince(lastWakeTime)
        if elapsed < wakeCoolingDuration {
            let remaining = wakeCoolingDuration - elapsed
            return "cooling (\(String(format: "%.1f", remaining))s remaining, started \(String(format: "%.1f", elapsed))s ago)"
        }
        return "\(String(format: "%.1f", elapsed))s ago"
    }

    /// Space change retry count / max for diagnostic reports.
    var spaceChangeRetryInfo: String {
        "\(spaceChangeRetryCount)/\(maxSpaceChangeRetries)"
    }

    /// Fullscreen exit retry set contents for diagnostic reports.
    var fullscreenExitRetryingInfo: String {
        fullscreenExitRetrying.isEmpty ? "(empty)" : fullscreenExitRetrying.sorted().joined(separator: ", ")
    }

    /// Connected display UUIDs for diagnostic reports.
    var connectedDisplayUUIDsInfo: String {
        connectedDisplayUUIDs.isEmpty ? "(none)" : connectedDisplayUUIDs.sorted().joined(separator: ", ")
    }

    /// Last manual switch target space UUID for diagnostic reports.
    var lastManualSwitchTargetUUIDInfo: String {
        lastManualSwitchTargetUUID ?? "nil"
    }

    func pruneStaleMovedWindows() {
        guard !SpaceHelper.isDragging else { return }
        var staleKeys: [Int] = []
        for (windowID, entry) in movedWindowsOriginalSpaces {
            guard let actualCgsSpaceID = SpaceHelper.getWindowSpaceID(id: windowID) else {
                staleKeys.append(windowID)
                continue
            }
            if actualCgsSpaceID != entry.currentSpaceUUID {
                print("SpaceManager: Pruning window \(windowID) from restore queue — expected \(entry.currentSpaceUUID), actual \(actualCgsSpaceID)")
                staleKeys.append(windowID)
            }
        }
        for key in staleKeys {
            movedWindowsOriginalSpaces.removeValue(forKey: key)
        }
    }

    func restoreAllMovedWindows() {
        restoreMovedWindows(fromOriginalSpaceUUID: nil)
    }

    func restoreMovedWindows(fromOriginalSpaceUUID spaceUUID: String?) {
        pruneStaleMovedWindows()
        let windowIDs = movedWindowsOriginalSpaces.compactMap { windowID, entry in
            spaceUUID == nil || entry.originalSpaceUUID == spaceUUID ? windowID : nil
        }
        let startedNewRun = movedWindowRestoreQueue.enqueue(windowIDs)
        guard startedNewRun else { return }

        movedWindowRestoreInitialSpaceUUID = currentSpaceUUID
        restoreNextMovedWindow(generation: movedWindowRestoreQueue.generation)
    }

    private func restoreNextMovedWindow(generation: UInt64) {
        guard movedWindowRestoreQueue.isRunning,
              movedWindowRestoreQueue.generation == generation else {
            return
        }

        guard let windowID = movedWindowRestoreQueue.takeNext(generation: generation) else {
            finishMovedWindowRestoration(generation: generation)
            return
        }

        guard let entry = movedWindowsOriginalSpaces[windowID] else {
            _ = movedWindowRestoreQueue.completeActive(windowID: windowID, generation: generation)
            DispatchQueue.main.async { [weak self] in
                self?.restoreNextMovedWindow(generation: generation)
            }
            return
        }

        guard let currentSpace = spaceNameDict.first(where: { $0.id == entry.currentSpaceUUID }) else {
            _ = movedWindowRestoreQueue.completeActive(windowID: windowID, generation: generation)
            DispatchQueue.main.async { [weak self] in
                self?.restoreNextMovedWindow(generation: generation)
            }
            return
        }

        print("SpaceManager: Restoring window \(windowID) from \(entry.currentSpaceUUID) back to \(entry.originalSpaceUUID)")
        switchToSpace(currentSpace, forceInstant: true, isManual: false)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.60) { [weak self] in
            guard let self,
                  self.movedWindowRestoreQueue.generation == generation,
                  self.movedWindowRestoreQueue.activeWindowID == windowID else {
                return
            }

            SpaceHelper.focusWindow(id: windowID, pid: entry.pid)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self,
                      self.movedWindowRestoreQueue.generation == generation,
                      self.movedWindowRestoreQueue.activeWindowID == windowID else {
                    return
                }

                SpaceHelper.dragActiveWindow(to: entry.originalSpaceUUID, forceInstant: true)
                self.movedWindowsOriginalSpaces.removeValue(forKey: windowID)
                guard self.movedWindowRestoreQueue.completeActive(windowID: windowID, generation: generation) else {
                    return
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.50) { [weak self] in
                    self?.restoreNextMovedWindow(generation: generation)
                }
            }
        }
    }

    private func finishMovedWindowRestoration(generation: UInt64) {
        guard movedWindowRestoreQueue.finishIfDrained(generation: generation) else { return }

        let initialSpaceUUID = movedWindowRestoreInitialSpaceUUID
        movedWindowRestoreInitialSpaceUUID = nil
        if let initialSpaceUUID,
           let initialSpace = spaceNameDict.first(where: { $0.id == initialSpaceUUID }) {
            print("SpaceManager: All restorations complete. Switching back to initial space \(initialSpaceUUID)")
            switchToSpace(initialSpace, forceInstant: true, isManual: false)
        }
    }
}
