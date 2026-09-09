import AppKit
import Darwin.sys.sysctl
import Foundation
import SwiftUI
import WidgetKit

extension SpaceManager {

    static let persistentNameCachePrefix = "PersistentSpace|"

    static func persistentNameCacheKey(for persistentID: String) -> String {
        persistentNameCachePrefix + persistentID.uppercased()
    }

    private static func readBootSessionID() -> String? {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0,
              size > 1 else {
            return nil
        }

        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &value, &size, nil, 0) == 0 else {
            return nil
        }
        let sessionID = String(cString: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return sessionID.isEmpty ? nil : sessionID.uppercased()
    }

    // MARK: - Periodic Space Layout Check

    func startPeriodicSpaceLayoutCheck() {
        stopPeriodicSpaceLayoutCheck()
        spaceLayoutCheckTimer = Timer.scheduledTimer(withTimeInterval: spaceLayoutCheckInterval, repeats: true) { [weak self] _ in
            self?.checkForNewSpaces()
        }
    }

    func stopPeriodicSpaceLayoutCheck() {
        spaceLayoutCheckTimer?.invalidate()
        spaceLayoutCheckTimer = nil
    }

    func scheduleFullscreenSpaceRearrangement(
        fullscreenSpaceID: String,
        afterSourceSpaceID sourceSpaceID: String,
        displayID: String
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self = self,
                  self.autoRearrangeFullscreenSpaces,
                  let state = SpaceHelper.getSystemState(onDisplayID: displayID) else { return }

            let orderedIDs = state.spaces
                .filter { $0.displayID == displayID }
                .map(\.id)
            guard let sourceIndex = orderedIDs.firstIndex(of: sourceSpaceID),
                  orderedIDs.contains(fullscreenSpaceID) else { return }

            let completion: (SpaceRearrangementService.Result) -> Void = { result in
                if case .failure(let message) = result {
                    DiagnosticEventLog.shared.record(
                        subsystem: "SpaceManager",
                        level: "warning",
                        "Automatic fullscreen space rearrangement failed: \(message)"
                    )
                }
                self.refreshSpaceState()
            }

            if sourceIndex + 1 < orderedIDs.count {
                let nextSpaceID = orderedIDs[sourceIndex + 1]
                guard nextSpaceID != fullscreenSpaceID else { return }
                SpaceRearrangementService.shared.rearrange(
                    sourceID: fullscreenSpaceID,
                    before: nextSpaceID,
                    orderedSpaceIDs: orderedIDs,
                    displayID: displayID,
                    completion: completion
                )
            } else {
                SpaceRearrangementService.shared.rearrangeToEnd(
                    sourceID: fullscreenSpaceID,
                    orderedSpaceIDs: orderedIDs,
                    displayID: displayID,
                    completion: completion
                )
            }
        }
    }

    /// Lightweight check that compares the current CGS space set against
    /// spaceNameDict. If new spaces exist (e.g., created in Mission Control on an
    /// external display) without a space switch having occurred, triggers a full
    /// detection refresh to pick them up.
    private func checkForNewSpaces() {
        guard !isSystemSleeping else { return }
        guard !isInWakeCoolingPeriod else { return }
        guard let cgsState = SpaceHelper.getSystemState() else { return }
        let cgsIDs = Set(cgsState.spaces.map { $0.id })
        let currentIDs = Set(spaceNameDict.map { $0.id })
        guard cgsIDs != currentIDs else { return }
        print("SpaceManager: Detected space layout change (CGS: \(cgsIDs.count) vs cached: \(currentIDs.count)). Refreshing...")
        refreshSpaceState()
    }
    
    func loadSavedData() {
        currentBootSessionID = Self.readBootSessionID()
        let savedBootSessionID = UserDefaults.standard.string(forKey: SpaceManager.bootSessionKey)
        shouldRestoreNamesByPositionAfterBoot = currentBootSessionID != nil
            && currentBootSessionID != savedBootSessionID?.uppercased()

        if let data = UserDefaults.standard.data(forKey: SpaceManager.spacesKey),
           let spaces = try? JSONDecoder().decode([DesktopSpace].self, from: data) {
            spaceNameDict = spaces.map {
                var s = $0
                s.customName = s.customName.replacingOccurrences(of: "~", with: "")
                
                // Migrate displayID from "Name (ID)" to UUID if needed
                if s.displayID.contains("(") && s.displayID.contains(")") {
                    if let lastParenIndex = s.displayID.lastIndex(of: "("),
                       let lastBracketIndex = s.displayID.lastIndex(of: ")") {
                        let idStart = s.displayID.index(after: lastParenIndex)
                        let idString = String(s.displayID[idStart..<lastBracketIndex])
                        var displayIdentifier = s.displayID
                        if let screenID = UInt32(idString),
                           let uuidRef = CGDisplayCreateUUIDFromDisplayID(screenID) {
                            let uuid = uuidRef.takeRetainedValue()
                            if let uuidStr = CFUUIDCreateString(nil, uuid) as String? {
                                displayIdentifier = uuidStr.uppercased()
                            }
                        }
                        s.displayID = displayIdentifier
                    }
                }
                return s
            }
        }
        if let data = UserDefaults.standard.data(forKey: SpaceManager.nameCacheKey),
           let cache = try? JSONDecoder().decode([String: String].self, from: data) {
            nameCache = cache.mapValues { $0.replacingOccurrences(of: "~", with: "") }
        }
        if let data = UserDefaults.standard.data(forKey: SpaceManager.indexCacheKey),
           let cache = try? JSONDecoder().decode([String: String].self, from: data) {
            indexCache = cache.mapValues { $0.replacingOccurrences(of: "~", with: "") }
        }
        if (nameCache.isEmpty || indexCache.isEmpty) && !spaceNameDict.isEmpty {
            var displayDesktopCounters: [String: Int] = [:]
            for space in spaceNameDict where !space.isFullscreen {
                let count = displayDesktopCounters[space.displayID, default: 0] + 1
                displayDesktopCounters[space.displayID] = count
                
                if !space.customName.isEmpty {
                    nameCache[space.id] = space.customName
                    let indexKey = "\(space.displayID)|Desktop|\(count)"
                    indexCache[indexKey] = space.customName
                }
            }
            saveData()
        }
    }
    
    public func saveSpaces() {
        saveData()
    }
    
    func saveData() {
        // We only save the spaces. Naming logic for fullscreen is re-run on load/refresh.
        if let data = try? JSONEncoder().encode(spaceNameDict) {
            UserDefaults.standard.set(data, forKey: SpaceManager.spacesKey)
        }
        if let data = try? JSONEncoder().encode(nameCache) {
            UserDefaults.standard.set(data, forKey: SpaceManager.nameCacheKey)
        }
        if let data = try? JSONEncoder().encode(indexCache) {
            UserDefaults.standard.set(data, forKey: SpaceManager.indexCacheKey)
        }
    }

    func completeBootNameMigration(using spaces: [DesktopSpace]) {
        guard shouldRestoreNamesByPositionAfterBoot else { return }

        // Numeric ManagedSpaceIDs from the previous boot are unsafe. Preserve
        // durable UUID entries and rebuild the numeric aliases from the names
        // that were just reconciled against the new boot's space list.
        var rebuiltCache = nameCache.filter {
            $0.key.hasPrefix(Self.persistentNameCachePrefix)
        }
        for space in spaces where !space.isFullscreen && !space.customName.isEmpty {
            rebuiltCache[space.id] = space.customName
            if let persistentID = space.persistentID {
                rebuiltCache[Self.persistentNameCacheKey(for: persistentID)] = space.customName
            }
        }
        nameCache = rebuiltCache
        shouldRestoreNamesByPositionAfterBoot = false
        if let currentBootSessionID {
            UserDefaults.standard.set(currentBootSessionID, forKey: SpaceManager.bootSessionKey)
        }
        DiagnosticEventLog.shared.record(
            subsystem: "SpaceManager",
            level: "info",
            "Rebuilt space-name identity cache for the current boot session"
        )
    }
}
