import Foundation

struct SpaceAPISnapshot: Codable {
    let apiVersion: String
    let currentSpaceIDs: [String]
    let currentSpaceName: String
    let spaces: [SpaceAPISnapshotSpace]
}

struct SpaceAPISnapshotSpace: Codable {
    let id: String
    let name: String
    let displayID: String
    let number: Int
    let isFullscreen: Bool
    let appPath: String?
}

extension SpaceAPI {
    func makeSpaceSnapshot(_ manager: SpaceManager) throws -> String {
        let spaces = manager.spaceNameDict.sorted {
            if $0.displayID != $1.displayID {
                return $0.displayID.localizedStandardCompare($1.displayID) == .orderedAscending
            }
            return $0.num < $1.num
        }.map { space in
            SpaceAPISnapshotSpace(
                id: space.id,
                name: manager.getSpaceName(space.id),
                displayID: space.displayID,
                number: space.num,
                isFullscreen: space.isFullscreen,
                appPath: space.appPath
            )
        }
        let snapshot = SpaceAPISnapshot(
            apiVersion: DesktopRenamerAPIVersion.current,
            currentSpaceIDs: SpaceHelper.getCurrentSpaceIDs(),
            currentSpaceName: manager.getSpaceName(manager.currentSpaceUUID),
            spaces: spaces
        )
        return String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
    }
}
