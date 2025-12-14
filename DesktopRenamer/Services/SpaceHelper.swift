import Foundation
import AppKit

class SpaceHelper {
    // Add the threshold constant backed by UserDefaults
    static var fullscreenThreshold: Int {
        get { UserDefaults.standard.integer(forKey: "com.michaelqiu.desktoprenamer.fullscreenthreshold") }
        set { UserDefaults.standard.set(newValue, forKey: "com.michaelqiu.desktoprenamer.fullscreenthreshold") }
    }

    // Change the type of the callback to include ncCount
    private static var onSpaceChange: ((String, Int) -> Void)?
    
    // Change startMonitoring to accept the new callback signature
    static func startMonitoring(onChange: @escaping (String, Int) -> Void) {
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
    
    // Change getSpaceUUID completion signature to include Int
    static func getSpaceUUID(completion: @escaping (String, Int) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { // Wait the system to update
            // Get all windows
            let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
            let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
            var uuid = ""
            var ncCnt = 0 // ncCnt is here
            
            // Look for the wallpaper window
            
            
            var ccCnt = 0
            var dkCnt = 0
            var wsCnt = 0
            for window in windowList {
//                print(window[kCGWindowOwnerName as String] as? String ?? "Empty")
                
                
                if let owner = window[kCGWindowOwnerName as String] as? String,
                   owner == "Control Center" {
                    ccCnt += 1
                }
                if let owner = window[kCGWindowOwnerName as String] as? String,
                   owner == "Dock" {
                    dkCnt += 1
                }
                if let owner = window[kCGWindowOwnerName as String] as? String,
                   owner == "Window Server" {
                    wsCnt += 1
                }
                    
                
                if let owner = window[kCGWindowOwnerName as String] as? String,
                   owner == "Notification Center" {
                    ncCnt += 1
                } else if let owner = window[kCGWindowOwnerName as String] as? String,
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
                
//                if let owner = window[kCGWindowOwnerName as String] as? String {
//                    print(owner)
//                }
            }
            
            if ncCnt <= SpaceHelper.fullscreenThreshold {
                uuid = "FULLSCREEN"
            }
            
//            print("####################")
//            print(uuid)
//            print(ncCnt)
//            print(ccCnt)
//            print(dkCnt)
//            print(wsCnt)
//            print("####################")
            
            // Return both UUID and ncCnt
            completion(uuid, ncCnt)
        }
    }
    
    private static func detectSpaceChange() {
        // Update to handle two arguments
        getSpaceUUID { spaceUUID, ncCnt in
            onSpaceChange?(spaceUUID, ncCnt)
        }
    }
}
