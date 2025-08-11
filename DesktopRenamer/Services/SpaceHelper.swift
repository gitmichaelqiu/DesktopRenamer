import Foundation
import AppKit

class SpaceHelper {
    private static var onSpaceChange: ((String) -> Void)?
    
    static func startMonitoring(onChange: @escaping (String) -> Void) {
        onSpaceChange = onChange
        
        // Monitor space changes
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            detectSpaceChange()
        }
        
        // Initial detection
        detectSpaceChange()
    }
    
    static func stopMonitoring() {
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    static func getSpaceUUID() -> String {
        // Get all windows
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
        let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        
        // Look for the wallpaper window
        for window in windowList {
            if let owner = window[kCGWindowOwnerName as String] as? String,
               owner == "Dock",
               let name = window[kCGWindowName as String] as? String,
               name.starts(with: "Wallpaper-"),
               let layer = window[kCGWindowLayer as String] as? Int32,
               layer == -2147483624 { // This is the wallpaper layer
                
                // Extract UUID from wallpaper name
                var uuid = String(name.dropFirst("Wallpaper-".count))

                if uuid == "" {
                    uuid = "MAIN"
                }
                
                return uuid
            }
        }
        
        print("Debug: Services/SH getUUID failed")
        return ""
    }
    
    private static func detectSpaceChange() {
        let spaceUUID: String = getSpaceUUID()
        onSpaceChange?(spaceUUID)
    }
}

