import Foundation
import AppKit

extension SpaceAPI {
    func makeSpaceSnapshot(_ manager: SpaceManager) throws -> String {
        let spaces = manager.spaceNameDict.sorted {
            if $0.displayID != $1.displayID {
                return $0.displayID.localizedStandardCompare($1.displayID) == .orderedAscending
            }
            return $0.num < $1.num
        }.map { space in
            var result: [String: Any] = [
                "id": space.id,
                "name": manager.getSpaceName(space.id),
                "displayID": space.displayID,
                "displayName": displayName(for: space.displayID),
                "number": space.num,
                "isFullscreen": space.isFullscreen
            ]
            if let appPath = space.appPath {
                result["appPath"] = appPath
            }
            return result
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

    private func displayName(for displayID: String) -> String {
        for screen in NSScreen.screens {
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(screenNumber.uint32Value)?.takeRetainedValue(),
                  let uuidString = CFUUIDCreateString(nil, uuid) as String? else {
                continue
            }
            if uuidString.caseInsensitiveCompare(displayID) == .orderedSame {
                return screen.localizedName
            }
        }
        return displayID == "Main" ? "Main Display" : "Display"
    }
}
