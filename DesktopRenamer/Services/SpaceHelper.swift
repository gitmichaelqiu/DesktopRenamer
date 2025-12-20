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
    
    // RENAMED: getRawSpaceUUID
    // This now returns the RAW UUID (or "MAIN") without applying the fullscreen threshold logic.
    static func getRawSpaceUUID(completion: @escaping (String, Int) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { // Wait the system to update
            // Get all windows
            let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
            let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
            var uuid = ""
            var ncCnt = 0
            
            for window in windowList {
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
            }
            
            // REMOVED: The premature check "if ncCnt <= SpaceHelper.fullscreenThreshold".
            // We now return the raw data and let SpaceManager decide.
            
            completion(uuid, ncCnt)
        }
    }
    
    // Helper to manually trigger detection (exposed for Refresh actions)
    static func detectSpaceChange() {
        testMultiDisplayDetection()
        getRawSpaceUUID { spaceUUID, ncCnt in
            onSpaceChange?(spaceUUID, ncCnt)
        }
    }
}


import Foundation
import AppKit

extension SpaceHelper {
    
    /// NEW: Independent test function for multi-display detection.
    /// Does not interfere with original single-display monitoring logic.
    static func testMultiDisplayDetection() {
        // We wait briefly for the Window Server to update window positions after a space change.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
            let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
            
            let screens = NSScreen.screens
            print("\n🚀 [TEST] MULTI-DISPLAY DETECTION START")
            print("Detected \(screens.count) screens.")

            for (index, screen) in screens.enumerated() {
                var screenUUID = "UNKNOWN"
                var screenNcCnt = 0
                
                // Screen coordinates in AppKit (origin bottom-left) vs CoreGraphics (origin top-left)
                // However, kCGWindowBounds are usually relative to the main display origin[cite: 2, 8, 11].
                let screenFrame = screen.frame
                
                for window in windowList {
                    guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                          let x = bounds["X"] as? CGFloat,
                          let y = bounds["Y"] as? CGFloat,
                          let w = bounds["Width"] as? CGFloat,
                          let h = bounds["Height"] as? CGFloat else { continue }
                    
                    let windowRect = CGRect(x: x, y: y, width: w, height: h)
                    let windowCenter = CGPoint(x: windowRect.midX, y: windowRect.midY)
                    
                    // We check if the window's center is within this specific screen's bounds[cite: 138, 222].
                    // Note: You may need to adjust Y coordinate flipping depending on your specific macOS coordinate mapping.
                    if isPoint(windowCenter, inside: screenFrame) {
                        if let owner = window[kCGWindowOwnerName as String] as? String {
                            // Count Notification Center windows for this screen only[cite: 186, 189].
                            if owner == "Notification Center" {
                                screenNcCnt += 1
                            }
                            // Identify the specific Wallpaper UUID for this screen[cite: 237, 241].
                            else if owner == "Dock",
                                    let name = window[kCGWindowName as String] as? String,
                                    name.starts(with: "Wallpaper-") {
                                screenUUID = String(name.dropFirst("Wallpaper-".count))
                                if screenUUID.isEmpty { screenUUID = "MAIN" }
                            }
                        }
                    }
                }
                
                print("📺 Display #\(index) | Bounds: \(screenFrame)")
                print("   ↳ UUID: \(screenUUID)")
                print("   ↳ Metric (NC Count): \(screenNcCnt)")
                print("   ↳ Status: \(screenNcCnt <= SpaceHelper.fullscreenThreshold ? "FULLSCREEN" : "DESKTOP")")
            }
            print("🚀 [TEST] MULTI-DISPLAY DETECTION END\n")
        }
    }
    
    // Helper to handle the coordinate system comparison
    private static func isPoint(_ point: CGPoint, inside screenFrame: CGRect) -> Bool {
        // Core Graphics uses top-left origin. NSScreen uses bottom-left origin.
        // We flip the point's Y relative to the primary screen (Screen 0) to match.
        if let primaryScreen = NSScreen.screens.first {
            let flippedY = primaryScreen.frame.height - point.y
            let flippedPoint = CGPoint(x: point.x, y: flippedY)
            return screenFrame.contains(flippedPoint)
        }
        return screenFrame.contains(point)
    }
}
