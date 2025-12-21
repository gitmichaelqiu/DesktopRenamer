import Foundation
import AppKit

class SpaceHelper {
    static var fullscreenThreshold: Int {
        get { UserDefaults.standard.integer(forKey: "com.michaelqiu.desktoprenamer.fullscreenthreshold") }
        set { UserDefaults.standard.set(newValue, forKey: "com.michaelqiu.desktoprenamer.fullscreenthreshold") }
    }

    // Callback: (UUID, isDesktop, ncCount, DisplayID)
    private static var onSpaceChange: ((String, Bool, Int, String) -> Void)?
    
    static func startMonitoring(onChange: @escaping (String, Bool, Int, String) -> Void) {
        onSpaceChange = onChange
        
        // Monitor system space changes
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            detectSpaceChange()
        }
        
        // Also monitor app activation to catch focus changes between displays
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in
            detectSpaceChange()
        }
        
        detectSpaceChange()
    }
    
    static func stopMonitoring() {
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    private static func getActiveDisplay() -> NSScreen? {
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            // FIX: If Finder is active, ignore window checks because Finder owns
            // desktop windows on ALL screens simultaneously. Use mouse fallback instead.
            if frontApp.bundleIdentifier != "com.apple.finder" {
                
                let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
                let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
                
                for window in windowList {
                    if let pid = window[kCGWindowOwnerPID as String] as? Int,
                       pid == frontApp.processIdentifier,
                       let layer = window[kCGWindowLayer as String] as? Int,
                       layer == 0 {
                        
                        if let bounds = window[kCGWindowBounds as String] as? [String: Any],
                           let x = bounds["X"] as? CGFloat,
                           let y = bounds["Y"] as? CGFloat,
                           let w = bounds["Width"] as? CGFloat,
                           let h = bounds["Height"] as? CGFloat {
                            
                            let rect = CGRect(x: x, y: y, width: w, height: h)
                            let center = CGPoint(x: rect.midX, y: rect.midY)
                            
                            for screen in NSScreen.screens {
                                if isPoint(center, inside: screen.frame) {
                                    return screen
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Fallback: Use Mouse Location
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
    }
    
    static func getRawSpaceUUID(completion: @escaping (String, Bool, Int, String) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { // Slight delay to allow window server to update
            
            // 1. Determine Target Display
            guard let activeScreen = getActiveDisplay() else {
                completion("", false, 0, "Unknown")
                return
            }
            
            let screenID = activeScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber ?? 0
            let screenName = activeScreen.localizedName
            let displayIdentifier = "\(screenName) (\(screenID))"
            
            // 2. Scan Windows
            let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
            let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
            
            var uuid = ""
            var ncCnt = 0
            var hasFinderDesktop = false
            
            for window in windowList {
                guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                      let x = bounds["X"] as? CGFloat,
                      let y = bounds["Y"] as? CGFloat,
                      let w = bounds["Width"] as? CGFloat,
                      let h = bounds["Height"] as? CGFloat else { continue }
                
                let windowRect = CGRect(x: x, y: y, width: w, height: h)
                let windowCenter = CGPoint(x: windowRect.midX, y: windowRect.midY)
                
                // CRITICAL: Filter windows by the DETECTED active screen
                if isPoint(windowCenter, inside: activeScreen.frame) {
                    if let owner = window[kCGWindowOwnerName as String] as? String {
                        
                        // UUID (Wallpaper)
                        if owner == "Dock",
                           let name = window[kCGWindowName as String] as? String,
                           name.starts(with: "Wallpaper-") {
                            uuid = String(name.dropFirst("Wallpaper-".count))
                            if uuid == "" { uuid = "MAIN" }
                        }
                        
                        // Metric (NC Count)
                        if owner == "Notification Center" {
                            ncCnt += 1
                        }
                        
                        // Desktop Check (Finder Background)
                        if owner == "Finder",
                           let layer = window[kCGWindowLayer as String] as? Int,
                           layer < 0 {
                            hasFinderDesktop = true
                        }
                    }
                }
            }
            
            completion(uuid, hasFinderDesktop, ncCnt, displayIdentifier)
        }
    }
    
    static func detectSpaceChange() {
        getRawSpaceUUID { spaceUUID, isDesktop, ncCnt, displayID in
            onSpaceChange?(spaceUUID, isDesktop, ncCnt, displayID)
        }
    }

    static func isPoint(_ point: CGPoint, inside screenFrame: CGRect) -> Bool {
        // Find the screen that acts as the origin (0,0)
        guard let primaryScreen = NSScreen.screens.first(where: { $0.frame.origin.x == 0 && $0.frame.origin.y == 0 }) else {
            return screenFrame.contains(point)
        }
        
        // Flip Quartz coordinates (Y=0 at top) to Cocoa (Y=0 at bottom)
        // The reference height must be the PRIMARY screen's height.
        let flippedY = NSMaxY(primaryScreen.frame) - point.y
        let flippedPoint = CGPoint(x: point.x, y: flippedY)
        
        return screenFrame.contains(flippedPoint)
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
