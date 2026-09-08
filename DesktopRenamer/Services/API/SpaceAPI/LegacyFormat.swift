import Foundation

/// Keeps the historical delimiter-based output stable for existing clients.
enum SpaceAPILegacyFormatter {
    static func spaceLine(
        id: String,
        name: String,
        displayName: String,
        number: Int,
        isFullscreen: Bool,
        appPath: String?
    ) -> String {
        ">\(id)~\(name)~\(displayName)~\(number)~\(isFullscreen ? "1" : "0")~\(appPath ?? "")\n"
    }

    static func windowLine(
        id: Int,
        pid: Int32,
        ownerName: String,
        appPath: String?,
        title: String?,
        isMinimized: Bool,
        isHidden: Bool
    ) -> String {
        "  \(id)|\(pid)|\(ownerName)|\(appPath ?? "")|\(title ?? "")|\(isMinimized ? "1" : "0")|\(isHidden ? "1" : "0")\n"
    }
}
