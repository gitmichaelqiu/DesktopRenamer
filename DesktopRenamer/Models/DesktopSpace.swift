import Foundation

struct DesktopSpace: Identifiable, Codable, Equatable {
    var id: String
    var customName: String
    var num: Int
    var displayID: String
    var isFullscreen: Bool
    var appName: String?
    var appPath: String?
    var globalShortcutNum: Int? // Unified index for keyboard shortcuts (1, 2, 3...) across displays
    // Unlike ManagedSpaceID, this UUID normally survives a system reboot.
    // It is optional because macOS can leave it empty for some desktops.
    var persistentID: String?
    // App-owned identity exposed by the structured SpaceAPI. It is stored with
    // this record and retained when macOS reports a new ManagedSpaceID.
    var spaceAPIID: String
    
    // Custom decoding to handle legacy data
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        customName = try container.decode(String.self, forKey: .customName)
        num = try container.decode(Int.self, forKey: .num)
        displayID = try container.decodeIfPresent(String.self, forKey: .displayID) ?? "Main"
        isFullscreen = try container.decodeIfPresent(Bool.self, forKey: .isFullscreen) ?? false
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
        appPath = try container.decodeIfPresent(String.self, forKey: .appPath)
        globalShortcutNum = try container.decodeIfPresent(Int.self, forKey: .globalShortcutNum)
        persistentID = try container.decodeIfPresent(String.self, forKey: .persistentID)
        let storedSpaceAPIID = try container.decodeIfPresent(String.self, forKey: .spaceAPIID)
        if let storedSpaceAPIID, !storedSpaceAPIID.isEmpty {
            spaceAPIID = storedSpaceAPIID
        } else {
            spaceAPIID = UUID().uuidString
        }
    }
    
    // Default init
    init(id: String, customName: String, num: Int, displayID: String, isFullscreen: Bool = false, appName: String? = nil, appPath: String? = nil, globalShortcutNum: Int? = nil, persistentID: String? = nil, spaceAPIID: String = UUID().uuidString) {
        self.id = id
        self.customName = customName
        self.num = num
        self.displayID = displayID
        self.isFullscreen = isFullscreen
        self.appName = appName
        self.appPath = appPath
        self.globalShortcutNum = globalShortcutNum
        self.persistentID = persistentID
        self.spaceAPIID = spaceAPIID
    }

    mutating func preserveSpaceAPIIdentity(from previousSpaces: [DesktopSpace], afterBoot: Bool) {
        if let persistentID,
           let previousSpace = previousSpaces.first(where: { $0.persistentID == persistentID }) {
            spaceAPIID = previousSpace.spaceAPIID
            return
        }

        // A known persistent-ID mismatch means macOS has identified a new
        // Space, even if it reused the previous ManagedSpaceID.
        guard persistentID == nil, !afterBoot,
              let previousSpace = previousSpaces.first(where: {
                  $0.id == id && $0.persistentID == nil
              }) else {
            return
        }

        spaceAPIID = previousSpace.spaceAPIID
    }
}
