import AppKit
import Foundation

extension SpaceAPI {
    func makeSpaceSnapshotPayload(_ manager: SpaceManager, revision: UInt64) -> SpaceAPISnapshot {
        let spaces = manager.spaceNameDict
        let apiIDsByManagedID = Dictionary(uniqueKeysWithValues: spaces.map { ($0.id, $0.spaceAPIID) })
        return SpaceAPISnapshot(
            apiVersion: DesktopRenamerAPIVersion.current,
            revision: revision,
            timestamp: Self.apiTimestamp(),
            currentSpaceIDs: SpaceHelper.getCurrentSpaceIDs().compactMap { apiIDsByManagedID[$0] },
            currentSpaceID: apiIDsByManagedID[manager.currentSpaceUUID] ?? "",
            currentDisplayID: manager.currentDisplayID,
            currentSpaceName: manager.getSpaceName(manager.currentSpaceUUID),
            movedWindowsCount: manager.movedWindowsOriginalSpaces.count,
            spaces: makeSpaceRecords(manager)
        )
    }

    /// Returns the historical snapshot shape used by the legacy command channel.
    /// Structured clients should use makeSpaceSnapshotPayload instead.
    func makeSpaceSnapshot(_ manager: SpaceManager) throws -> String {
        let displayNames = displayNamesByID()
        let spaces = manager.spaceNameDict
            .sorted {
                if $0.displayID != $1.displayID {
                    return $0.displayID.localizedStandardCompare($1.displayID) == .orderedAscending
                }
                return $0.num < $1.num
            }
            .map { space -> [String: Any] in
                var record: [String: Any] = [
                    "id": space.id,
                    "name": manager.getSpaceName(space.id),
                    "displayID": space.displayID,
                    "displayName": displayName(for: space.displayID, using: displayNames),
                    "number": space.num,
                    "isFullscreen": space.isFullscreen,
                    "isLocked": manager.lockedSpaceIDs.contains(space.id)
                ]
                if let appPath = space.appPath {
                    record["appPath"] = appPath
                }
                return record
            }
        let snapshot: [String: Any] = [
            "apiVersion": DesktopRenamerAPIVersion.current,
            "currentSpaceIDs": SpaceHelper.getCurrentSpaceIDs(),
            "currentSpaceID": manager.currentSpaceUUID,
            "currentDisplayID": manager.currentDisplayID,
            "currentSpaceName": manager.getSpaceName(manager.currentSpaceUUID),
            "movedWindowsCount": manager.movedWindowsOriginalSpaces.count,
            "spaces": spaces
        ]
        guard JSONSerialization.isValidJSONObject(snapshot) else {
            throw NSError(
                domain: "DesktopRenamer.SpaceAPI",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not encode space snapshot."]
            )
        }
        let data = try JSONSerialization.data(withJSONObject: snapshot)
        return String(decoding: data, as: UTF8.self)
    }

    func makeWindowsSnapshotPayload(_ manager: SpaceManager, revision: UInt64) -> SpaceAPIWindowsSnapshot {
        let spaces = manager.spaceNameDict
        return SpaceAPIWindowsSnapshot(
            apiVersion: DesktopRenamerAPIVersion.current,
            revision: revision,
            timestamp: Self.apiTimestamp(),
            spaces: makeSpaceRecords(manager),
            windows: makeSpaceAPIWindowRecords(
                SpaceHelper.getWindowRecordsForAllSpaces(spaces: spaces),
                spaces: spaces
            )
        )
    }

    func makeWindowsSnapshotPayloadAsync(_ manager: SpaceManager, revision: UInt64) async -> SpaceAPIWindowsSnapshot {
        let spaces = manager.spaceNameDict
        let spaceRecords = makeSpaceRecords(manager)
        let timestamp = Self.apiTimestamp()
        let windows = await Task.detached(priority: .userInitiated) {
            SpaceHelper.getWindowRecordsForAllSpaces(spaces: spaces)
        }.value

        return SpaceAPIWindowsSnapshot(
            apiVersion: DesktopRenamerAPIVersion.current,
            revision: revision,
            timestamp: timestamp,
            spaces: spaceRecords,
            windows: makeSpaceAPIWindowRecords(windows, spaces: spaces)
        )
    }

    func makeWindowsSnapshot(_ manager: SpaceManager, revision: UInt64) throws -> String {
        try encodeJSON(makeWindowsSnapshotPayload(manager, revision: revision))
    }

    func makeAPIInfo() -> SpaceAPIInfo {
        let accessRestricted = accessController.isRestricted
        let transports: [String] = socketServer.isRunning
            ? (accessRestricted ? ["unixDomainSocket"] : ["unixDomainSocket", "distributedNotificationCenter"])
            : (accessRestricted ? [] : ["distributedNotificationCenter"])
        return SpaceAPIInfo(
            contractVersion: DesktopRenamerAPIVersion.current,
            jsonRPCVersion: DesktopRenamerAPIContract.jsonRPCVersion,
            supportedMethods: DesktopRenamerAPIContract.supportedMethods,
            legacyNotifications: !accessRestricted,
            legacyCompatibility: accessRestricted ? "disabledByAccessPolicy" : "supported",
            eventNotifications: true,
            eventCapabilities: ["stateChanged"],
            maxPayloadBytes: DesktopRenamerAPIContract.maxPayloadBytes,
            transports: transports,
            socketEndpoint: socketServer.isRunning ? SpaceAPISocketServer.endpoint.path : nil,
            accessRestricted: accessRestricted
        )
    }

    func makeSpaceRecords(_ manager: SpaceManager) -> [SpaceAPISpace] {
        let displayNames = displayNamesByID()
        return manager.spaceNameDict
            .sorted {
                if $0.displayID != $1.displayID {
                    return $0.displayID.localizedStandardCompare($1.displayID) == .orderedAscending
                }
                return $0.num < $1.num
            }
            .map { space in
                SpaceAPISpace(
                    id: space.spaceAPIID,
                    name: manager.getSpaceName(space.id),
                    displayID: space.displayID,
                    displayName: displayName(for: space.displayID, using: displayNames),
                    number: space.num,
                    isFullscreen: space.isFullscreen,
                    appName: space.appName,
                    appPath: space.appPath,
                    globalShortcutNumber: space.globalShortcutNum,
                    isLocked: manager.lockedSpaceIDs.contains(space.id)
                )
            }
    }

    func makeSpaceAPIWindowRecords(_ windows: [SpaceAPIWindow], spaces: [DesktopSpace]) -> [SpaceAPIWindow] {
        let apiIDsByManagedID = Dictionary(uniqueKeysWithValues: spaces.map { ($0.id, $0.spaceAPIID) })
        return windows.compactMap { window in
            guard let spaceID = apiIDsByManagedID[window.spaceID] else { return nil }
            return SpaceAPIWindow(
                id: window.id,
                pid: window.pid,
                ownerName: window.ownerName,
                appPath: window.appPath,
                title: window.title,
                spaceID: spaceID,
                spaceIDs: window.spaceIDs.compactMap { apiIDsByManagedID[$0] },
                isMinimized: window.isMinimized,
                isHidden: window.isHidden
            )
        }
    }

    func managedSpaceID(forSpaceIdentifier identifier: String, manager: SpaceManager) -> String? {
        manager.spaceNameDict.first(where: { $0.spaceAPIID == identifier })?.id
            ?? manager.spaceNameDict.first(where: { $0.id == identifier })?.id
    }

    func spaceAPIIDs(forManagedSpaceIDs managedSpaceIDs: [String], manager: SpaceManager) -> [String] {
        let apiIDsByManagedID = Dictionary(uniqueKeysWithValues: manager.spaceNameDict.map { ($0.id, $0.spaceAPIID) })
        return managedSpaceIDs.compactMap { apiIDsByManagedID[$0] }
    }

    private func displayNamesByID() -> [String: String] {
        NSScreen.screens.reduce(into: [String: String]()) { names, screen in
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(screenNumber.uint32Value)?.takeRetainedValue(),
                  let uuidString = CFUUIDCreateString(nil, uuid) as String? else {
                return
            }
            names[uuidString.uppercased()] = screen.localizedName
        }
    }

    private func displayName(for displayID: String, using displayNames: [String: String]) -> String {
        if let name = displayNames[displayID.uppercased()] {
            return name
        }
        if displayID.caseInsensitiveCompare("Main") == .orderedSame {
            return "Main Display"
        }
        return "Display"
    }

    private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        guard data.count <= DesktopRenamerAPIContract.maxPayloadBytes else {
            throw SpaceAPIContractError.payloadTooLarge
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func apiTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
