import Foundation
import AppKit

class SpaceHelper {
    private static var lastKnownSpace: Int = 1
    private static var onSpaceChange: ((Int) -> Void)?
    private static var wallpaperCache: [String: Int] = [:]
    private static var isFirstRun = true
    
    static func startMonitoring(onChange: @escaping (Int) -> Void) {
        onSpaceChange = onChange
        
        // Start a timer to check for space changes
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            if let currentSpace = getCurrentSpaceNumber() {
                if currentSpace != lastKnownSpace || isFirstRun {
                    lastKnownSpace = currentSpace
                    isFirstRun = false
                    onChange(currentSpace)
                }
            }
        }
    }
    
    static func stopMonitoring() {
        onSpaceChange = nil
    }
    
    static func getCurrentSpaceNumber() -> Int? {
        // Get all windows
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
        let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        
        // Look for the wallpaper window from Dock
        for window in windowList {
            if let owner = window[kCGWindowOwnerName as String] as? String,
               owner == "Dock",
               let name = window[kCGWindowName as String] as? String,
               name.starts(with: "Wallpaper-"),
               let layer = window[kCGWindowLayer as String] as? Int32,
               layer == -2147483624 { // This is the wallpaper layer
                
                // Extract UUID from wallpaper name
                let uuid = String(name.dropFirst("Wallpaper-".count))
                
                // If we haven't seen this wallpaper before, assign it the next space number
                if wallpaperCache[uuid] == nil {
                    let nextSpace = wallpaperCache.count + 1
                    wallpaperCache[uuid] = nextSpace
                    print("New wallpaper detected: \(uuid) -> Space \(nextSpace)")
                }
                
                return wallpaperCache[uuid]
            }
        }
        
        // If we can't find the wallpaper window, return the last known space
        return lastKnownSpace
    }
    
    static func debugPrintWindowInfo() {
        // Get all windows
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
        let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        
        print("\n--- Window Information Debug ---")
        for (index, window) in windowList.enumerated() {
            print("\nWindow \(index):")
            for (key, value) in window {
                print("\(key): \(value)")
            }
        }
        print("\n---------------------------")
    }
} 
