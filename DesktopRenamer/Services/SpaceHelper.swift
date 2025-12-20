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
    
    // MARK: - Core Logic
    
    /// Returns the NSScreen where the mouse cursor is currently located.
    private static func getActiveDisplay() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        // NSMouseInRect handles the bottom-left coordinate system of AppKit automatically
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
    }
    
    // RENAMED: getRawSpaceUUID
    // This now filters by the Active Display (where the cursor is).
    static func getRawSpaceUUID(completion: @escaping (String, Int) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { // Wait for Window Server update
            
            // 1. Determine which display we are interested in (where the mouse is)
            guard let activeScreen = getActiveDisplay() else {
                // Fallback if no screen is found (unlikely), return empty state
                completion("", 0)
                return
            }
            
            // 2. Get all windows
            let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
            let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
            
            var uuid = ""
            var ncCnt = 0
            
            // 3. Iterate and Filter by Active Screen
            for window in windowList {
                guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                      let x = bounds["X"] as? CGFloat,
                      let y = bounds["Y"] as? CGFloat,
                      let w = bounds["Width"] as? CGFloat,
                      let h = bounds["Height"] as? CGFloat else { continue }
                
                let windowRect = CGRect(x: x, y: y, width: w, height: h)
                let windowCenter = CGPoint(x: windowRect.midX, y: windowRect.midY)
                
                // CRITICAL: Only process this window if it is on the active screen
                if isPoint(windowCenter, inside: activeScreen.frame) {
                    
                    if let owner = window[kCGWindowOwnerName as String] as? String {
                        
                        // Metric: Notification Center count for this specific screen
                        if owner == "Notification Center" {
                            ncCnt += 1
                        }
                        // UUID: Wallpaper identifier for this specific screen
                        else if owner == "Dock",
                                let name = window[kCGWindowName as String] as? String,
                                name.starts(with: "Wallpaper-") {
                            
                            uuid = String(name.dropFirst("Wallpaper-".count))
                            if uuid == "" {
                                uuid = "MAIN"
                            }
                        }
                    }
                }
            }
            
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
    
    // MARK: - Coordinate Helpers
    
    // Helper to handle the coordinate system comparison (CoreGraphics Top-Left vs AppKit Bottom-Left)
    static func isPoint(_ point: CGPoint, inside screenFrame: CGRect) -> Bool {
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


// Extension kept for debugging purposes if needed
extension SpaceHelper {
    
    static func testMultiDisplayDetection() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
            let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
            
            let screens = NSScreen.screens
            print("\n🚀 [TEST] MULTI-DISPLAY DETECTION START")
            print("Detected \(screens.count) screens.")

            for (index, screen) in screens.enumerated() {
                var screenUUID = "UNKNOWN"
                var screenNcCnt = 0
                let screenFrame = screen.frame
                
                for window in windowList {
                    guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                          let x = bounds["X"] as? CGFloat,
                          let y = bounds["Y"] as? CGFloat,
                          let w = bounds["Width"] as? CGFloat,
                          let h = bounds["Height"] as? CGFloat else { continue }
                    
                    let windowRect = CGRect(x: x, y: y, width: w, height: h)
                    let windowCenter = CGPoint(x: windowRect.midX, y: windowRect.midY)
                    
                    if isPoint(windowCenter, inside: screenFrame) {
                        if let owner = window[kCGWindowOwnerName as String] as? String {
                            if owner == "Notification Center" {
                                screenNcCnt += 1
                            }
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
}
