import Foundation

struct DesktopSpace: Identifiable, Codable {
    let id: Int
    var customName: String
    
    var displayName: String {
        return customName.isEmpty ? "Desktop \(id)" : customName
    }
} 