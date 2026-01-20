import Foundation

struct DesktopSpace: Identifiable, Codable, Equatable {
    var id: String
    var customName: String
    var num: Int
    var displayID: String
    var isFullscreen: Bool
    
    // Custom decoding to handle legacy data
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        customName = try container.decode(String.self, forKey: .customName)
        num = try container.decode(Int.self, forKey: .num)
        displayID = try container.decodeIfPresent(String.self, forKey: .displayID) ?? "Main"
        isFullscreen = try container.decodeIfPresent(Bool.self, forKey: .isFullscreen) ?? false
    }
    
    // Default init
    init(id: String, customName: String, num: Int, displayID: String, isFullscreen: Bool = false) {
        self.id = id
        self.customName = customName
        self.num = num
        self.displayID = displayID
        self.isFullscreen = isFullscreen
    }
}
