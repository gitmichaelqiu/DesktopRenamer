import Foundation

struct WindowSnapshot: Codable, Sendable {
    let id: Int
    let pid: Int32
    let ownerName: String
    let appPath: String
    let title: String
    let isMinimized: Bool
    let isHidden: Bool
}

struct SpaceWindowSnapshot: Codable, Sendable {
    let id: String
    let name: String
    let displayName: String
    let num: Int
    let isFullscreen: Bool
    let appPath: String?
    let windows: [WindowSnapshot]
}
