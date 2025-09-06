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
    
    static func getSpaceUUID(completion: @escaping (String) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { // Wait the system to update
            // Get all windows
            let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
            let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
            var uuid = ""
            var inFullscreen = true
            
            // Look for the wallpaper window
            for window in windowList {
                if let owner = window[kCGWindowOwnerName as String] as? String,
                   owner == "Dock",
                   let name = window[kCGWindowName as String] as? String,
                   name.starts(with: "Wallpaper-"),
                   let layer = window[kCGWindowLayer as String] as? Int32,
                   layer == -2147483624 { // This is the wallpaper layer
                    
                    // Extract UUID from wallpaper name
                    uuid = String(name.dropFirst("Wallpaper-".count))

                    if uuid == "" {
                        uuid = "MAIN"
                    }
                }
                else if let owner = window[kCGWindowOwnerName as String] as? String,
                        owner == "Control Center" {
                    inFullscreen = false
                }
            }
            
            if inFullscreen {
                uuid = "FULLSCREEN"
            }
            
            // Return
            completion(uuid)
        }
    }
    
    private static func detectSpaceChange() {
        getSpaceUUID {
            spaceUUID in onSpaceChange?(spaceUUID)
        }
    }
}

