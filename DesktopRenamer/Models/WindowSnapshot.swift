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

struct WindowEnumerationContext: Sendable {
    struct Display: Sendable {
        let id: String
        let name: String
        let frame: CGRect
    }

    struct Application: Sendable {
        let path: String
        let isHidden: Bool
    }

    let displays: [Display]
    let mainDisplayID: String?
    let applications: [Int32: Application]
}

struct SpaceWindowSnapshot: Codable, Sendable {
    let id: String
    let name: String
    let displayName: String
    let displayID: String?
    let num: Int
    let isFullscreen: Bool
    let appPath: String?
    let windows: [WindowSnapshot]
}
