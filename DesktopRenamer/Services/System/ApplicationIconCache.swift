import AppKit

enum ApplicationIconCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(forFilePath path: String) -> NSImage {
        let key = path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let icon = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(icon, forKey: key)
        return icon
    }

    static func icon(forBundleIdentifier bundleIdentifier: String) -> NSImage {
        let key = "bundle:" + bundleIdentifier as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let icon: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            icon = NSWorkspace.shared.icon(for: .application)
        }
        cache.setObject(icon, forKey: key)
        return icon
    }
}
