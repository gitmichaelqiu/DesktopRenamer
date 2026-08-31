import AppKit
import Foundation

private func scriptSpaceRecord(_ space: SpaceAPISpace) -> [String: Any] {
    var record: [String: Any] = [
        "id": space.id,
        "name": space.name,
        "displayID": space.displayID,
        "displayName": space.displayName,
        "number": space.number,
        "isFullscreen": space.isFullscreen
    ]
    if let appName = space.appName {
        record["appName"] = appName
    }
    if let appPath = space.appPath {
        record["appPath"] = appPath
    }
    if let globalShortcutNumber = space.globalShortcutNumber {
        record["globalShortcutNumber"] = globalShortcutNumber
    }
    return record
}

private func scriptWindowRecord(_ window: SpaceAPIWindow) -> [String: Any] {
    var record: [String: Any] = [
        "id": window.id,
        "pid": window.pid,
        "ownerName": window.ownerName,
        "spaceID": window.spaceID,
        "isMinimized": window.isMinimized,
        "isHidden": window.isHidden
    ]
    if let appPath = window.appPath {
        record["appPath"] = appPath
    }
    if let title = window.title {
        record["title"] = title
    }
    return record
}

private func scriptSnapshotRecord(_ snapshot: SpaceAPISnapshot) -> [String: Any] {
    [
        "apiVersion": snapshot.apiVersion,
        "revision": snapshot.revision,
        "timestamp": snapshot.timestamp,
        "currentSpaceIDs": snapshot.currentSpaceIDs,
        "currentSpaceName": snapshot.currentSpaceName,
        "spaces": snapshot.spaces.map(scriptSpaceRecord)
    ]
}

private func scriptWindowsSnapshotRecord(_ snapshot: SpaceAPIWindowsSnapshot) -> [String: Any] {
    [
        "apiVersion": snapshot.apiVersion,
        "revision": snapshot.revision,
        "timestamp": snapshot.timestamp,
        "spaces": snapshot.spaces.map(scriptSpaceRecord),
        "windows": snapshot.windows.map(scriptWindowRecord)
    ]
}

class GetAPIInformationCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "info", "Command performed: GetAPIInformationCommand")
        guard isAPIEnabled() else { return nil }
        guard let manager = runOnMain({ AppDelegate.shared.spaceManager }) else {
            scriptErrorNumber = -3
            scriptErrorString = "DesktopRenamer is not ready."
            return nil
        }
        return runOnMain {
            let api = manager.spaceAPI ?? SpaceAPI(spaceManager: manager)
            return scriptAPIInfoRecord(api.makeAPIInfo())
        }
    }
}

class GetStructuredSpacesCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "info", "Command performed: GetStructuredSpacesCommand")
        guard isAPIEnabled() else { return nil }
        guard let manager = runOnMain({ AppDelegate.shared.spaceManager }) else {
            scriptErrorNumber = -3
            scriptErrorString = "DesktopRenamer is not ready."
            return nil
        }
        return runOnMain {
            let api = manager.spaceAPI ?? SpaceAPI(spaceManager: manager)
            return api.makeSpaceSnapshotPayload(manager, revision: 0).spaces.map(scriptSpaceRecord)
        }
    }
}

class GetStructuredSnapshotCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "info", "Command performed: GetStructuredSnapshotCommand")
        guard isAPIEnabled() else { return nil }
        guard let manager = runOnMain({ AppDelegate.shared.spaceManager }) else {
            scriptErrorNumber = -3
            scriptErrorString = "DesktopRenamer is not ready."
            return nil
        }
        return runOnMain {
            let api = manager.spaceAPI ?? SpaceAPI(spaceManager: manager)
            return scriptSnapshotRecord(api.makeSpaceSnapshotPayload(manager, revision: api.currentSnapshotRevision))
        }
    }
}

class GetStructuredWindowsCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        DiagnosticEventLog.shared.record(subsystem: "AppleScript", level: "info", "Command performed: GetStructuredWindowsCommand")
        guard isAPIEnabled() else { return nil }
        guard let manager = runOnMain({ AppDelegate.shared.spaceManager }) else {
            scriptErrorNumber = -3
            scriptErrorString = "DesktopRenamer is not ready."
            return nil
        }
        let context = runOnMain {
            let api = manager.spaceAPI ?? SpaceAPI(spaceManager: manager)
            return (manager.spaceNameDict, api.makeSpaceRecords(manager), api.currentSnapshotRevision)
        }
        let (spaces, spaceRecords, revision) = context

        // Window enumeration uses CoreGraphics and Accessibility APIs. Keep it
        // outside the main-actor capture so a structured AppleScript read does
        // not hold up the app while it walks other applications' windows.
        let snapshot = SpaceAPIWindowsSnapshot(
            apiVersion: DesktopRenamerAPIVersion.current,
            revision: revision,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            spaces: spaceRecords,
            windows: SpaceHelper.getWindowRecordsForAllSpaces(spaces: spaces)
        )
        return scriptWindowsSnapshotRecord(snapshot)
    }
}

private func scriptAPIInfoRecord(_ info: SpaceAPIInfo) -> [String: Any] {
    [
        "contractVersion": info.contractVersion,
        "jsonRPCVersion": info.jsonRPCVersion,
        "supportedMethods": info.supportedMethods,
        "legacyNotifications": info.legacyNotifications,
        "legacyCompatibility": info.legacyCompatibility,
        "eventNotifications": info.eventNotifications,
        "eventCapabilities": info.eventCapabilities,
        "maxPayloadBytes": info.maxPayloadBytes
    ]
}
