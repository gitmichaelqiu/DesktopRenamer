import AppKit
import Foundation

extension SpaceAPI {
    func makeSpaceSnapshotPayload(_ manager: SpaceManager, revision: UInt64) -> SpaceAPISnapshot {
        SpaceAPISnapshot(
            apiVersion: DesktopRenamerAPIVersion.current,
            revision: revision,
            timestamp: Self.apiTimestamp(),
            currentSpaceIDs: SpaceHelper.getCurrentSpaceIDs(),
            currentSpaceName: manager.getSpaceName(manager.currentSpaceUUID),
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
                    "isFullscreen": space.isFullscreen
                ]
                if let appPath = space.appPath {
                    record["appPath"] = appPath
                }
                return record
            }
        let snapshot: [String: Any] = [
            "apiVersion": DesktopRenamerAPIVersion.current,
            "currentSpaceIDs": SpaceHelper.getCurrentSpaceIDs(),
            "currentSpaceName": manager.getSpaceName(manager.currentSpaceUUID),
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
        SpaceAPIWindowsSnapshot(
            apiVersion: DesktopRenamerAPIVersion.current,
            revision: revision,
            timestamp: Self.apiTimestamp(),
            spaces: makeSpaceRecords(manager),
            windows: SpaceHelper.getWindowRecordsForAllSpaces(spaces: manager.spaceNameDict)
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
            windows: windows
        )
    }

    func makeWindowsSnapshot(_ manager: SpaceManager, revision: UInt64) throws -> String {
        try encodeJSON(makeWindowsSnapshotPayload(manager, revision: revision))
    }

    func makeAPIInfo() -> SpaceAPIInfo {
        SpaceAPIInfo(
            contractVersion: DesktopRenamerAPIVersion.current,
            jsonRPCVersion: DesktopRenamerAPIContract.jsonRPCVersion,
            supportedMethods: DesktopRenamerAPIContract.supportedMethods,
            legacyNotifications: true,
            legacyCompatibility: "supported",
            eventNotifications: true,
            eventCapabilities: ["stateChanged"],
            maxPayloadBytes: DesktopRenamerAPIContract.maxPayloadBytes
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
                    id: space.id,
                    name: manager.getSpaceName(space.id),
                    displayID: space.displayID,
                    displayName: displayName(for: space.displayID, using: displayNames),
                    number: space.num,
                    isFullscreen: space.isFullscreen,
                    appName: space.appName,
                    appPath: space.appPath,
                    globalShortcutNumber: space.globalShortcutNum
                )
            }
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
