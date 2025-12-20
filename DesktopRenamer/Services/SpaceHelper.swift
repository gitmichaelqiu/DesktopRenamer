import Foundation
import AppKit

class SpaceHelper {
    // We keep the threshold for backward compatibility or valid main-screen logic if needed,
    // but the new boolean logic takes precedence.
    static var fullscreenThreshold: Int {
        get { UserDefaults.standard.integer(forKey: "com.michaelqiu.desktoprenamer.fullscreenthreshold") }
        set { UserDefaults.standard.set(newValue, forKey: "com.michaelqiu.desktoprenamer.fullscreenthreshold") }
    }

    // UPDATED: Callback now returns (UUID, isDesktop, DisplayID)
    // We replaced the 'Int' metric with a definitive 'Bool'
    private static var onSpaceChange: ((String, Bool, String) -> Void)?
    
    private static var displayMonitorTimer: Timer?
    private static var lastActiveScreenID: NSNumber?
    
    static func startMonitoring(onChange: @escaping (String, Bool, String) -> Void) {
        onSpaceChange = onChange
        
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            detectSpaceChange()
        }
        
        startDisplayMonitoring()
        detectSpaceChange()
    }
    
    static func stopMonitoring() {
        stopDisplayMonitoring()
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    // MARK: - Display Monitoring
    
    private static func startDisplayMonitoring() {
        stopDisplayMonitoring()
        if let currentScreen = getActiveDisplay() {
            lastActiveScreenID = currentScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        }
        displayMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            checkCursorDisplay()
        }
    }
    
    private static func stopDisplayMonitoring() {
        displayMonitorTimer?.invalidate()
        displayMonitorTimer = nil
    }
    
    private static func checkCursorDisplay() {
        guard let currentScreen = getActiveDisplay() else { return }
        let currentID = currentScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        
        if currentID != lastActiveScreenID {
            lastActiveScreenID = currentID
            detectSpaceChange()
        }
    }
    
    // MARK: - Core Logic
    
    private static func getActiveDisplay() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
    }
    
    // UPDATED: Returns isDesktop (Bool) instead of ncCount (Int)
    static func getRawSpaceUUID(completion: @escaping (String, Bool, String) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let activeScreen = getActiveDisplay() else {
                completion("", false, "Unknown")
                return
            }
            
            let screenID = activeScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber ?? 0
            let screenName = activeScreen.localizedName
            let displayIdentifier = "\(screenName) (\(screenID))"
            
            let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
            let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
            
            var uuid = ""
            var hasFinderDesktop = false
            
            for window in windowList {
                guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                      let x = bounds["X"] as? CGFloat,
                      let y = bounds["Y"] as? CGFloat,
                      let w = bounds["Width"] as? CGFloat,
                      let h = bounds["Height"] as? CGFloat else { continue }
                
                let windowRect = CGRect(x: x, y: y, width: w, height: h)
                let windowCenter = CGPoint(x: windowRect.midX, y: windowRect.midY)
                
                // Only check windows on the active display
                if isPoint(windowCenter, inside: activeScreen.frame) {
                    if let owner = window[kCGWindowOwnerName as String] as? String {
                        
                        // 1. Wallpaper UUID Detection (same as before)
                        if owner == "Dock",
                           let name = window[kCGWindowName as String] as? String,
                           name.starts(with: "Wallpaper-") {
                            uuid = String(name.dropFirst("Wallpaper-".count))
                            if uuid == "" { uuid = "MAIN" }
                        }
                        
                        // 2. New Desktop Detection Logic
                        // Finder windows with negative layer are the desktop icons/background.
                        // Regular Finder windows (file browser) have Layer 0.
                        if owner == "Finder",
                           let layer = window[kCGWindowLayer as String] as? Int,
                           layer < 0 {
                            hasFinderDesktop = true
                        }
                    }
                }
            }
            
            completion(uuid, hasFinderDesktop, displayIdentifier)
        }
    }
    
    static func detectSpaceChange() {
        getRawSpaceUUID { spaceUUID, isDesktop, displayID in
            onSpaceChange?(spaceUUID, isDesktop, displayID)
        }
    }
    
    static func isPoint(_ point: CGPoint, inside screenFrame: CGRect) -> Bool {
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
