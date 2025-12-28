import Foundation

struct DesktopSpace: Identifiable, Codable, Equatable {
    var id: String
    var customName: String
    var num: Int
    var displayID: String
    
    // Custom decoding to handle legacy data without displayID
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        customName = try container.decode(String.self, forKey: .customName)
        num = try container.decode(Int.self, forKey: .num)
        // Default to "Main" if displayID is missing in old data
        displayID = try container.decodeIfPresent(String.self, forKey: .displayID) ?? "Main"
    }
    
    // Default init
    init(id: String, customName: String, num: Int, displayID: String) {
        self.id = id
        self.customName = customName
        self.num = num
        self.displayID = displayID
    }
}
