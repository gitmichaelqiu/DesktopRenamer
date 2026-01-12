import Foundation
import AppKit

class SpaceHelper {
    static var fullscreenThreshold: Int {
        get { UserDefaults.standard.integer(forKey: "com.michaelqiu.desktoprenamer.fullscreenthreshold") }
        set { UserDefaults.standard.set(newValue, forKey: "com.michaelqiu.desktoprenamer.fullscreenthreshold") }
    }

    // Callback: (UUID, isDesktop, ncCount, DisplayID)
    private static var onSpaceChange: ((String, Bool, Int, String) -> Void)?
    
    // Store event monitors
    private static var globalEventMonitor: Any?
    private static var localEventMonitor: Any?
    
    static func startMonitoring(onChange: @escaping (String, Bool, Int, String) -> Void) {
        onSpaceChange = onChange
        
        // 1. Monitor system space changes (Swiping Left/Right)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            detectSpaceChange()
        }
        
        // 2. Monitor app activation (Cmd+Tab or Dock Click)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in
            detectSpaceChange()
        }
        
        // 3. Monitor Mouse Clicks (Switching Displays)
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
             detectSpaceChange()
        }
        
        // Also monitor local events (clicks on the app's own windows/menu)
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
             detectSpaceChange()
             return event
        }
        
        detectSpaceChange()
    }
    
    static func stopMonitoring() {
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
    }
    
    private static func getActiveDisplay() -> NSScreen? {
        if let frontApp = NSWorkspace.shared.frontmostApplication {
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            
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
        
    static func getVisibleSpaceUUIDs(completion: @escaping (Set<String>) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
            let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
            
            // Use local copy of screens to prevent mutation issues during loop
            let screens = NSScreen.screens
            var visibleUUIDs = Set<String>()

            // If screens are empty (e.g. headless or mid-transition), return empty safely
            if screens.isEmpty {
                completion([])
                return
            }

            for screen in screens {
                for window in windowList {
                    guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                          let x = bounds["X"] as? CGFloat,
                          let y = bounds["Y"] as? CGFloat,
                          let w = bounds["Width"] as? CGFloat,
                          let h = bounds["Height"] as? CGFloat else { continue }
                    
                    let windowRect = CGRect(x: x, y: y, width: w, height: h)
                    let center = CGPoint(x: windowRect.midX, y: windowRect.midY)
                    
                    if isPoint(center, inside: screen.frame) {
                        if let owner = window[kCGWindowOwnerName as String] as? String,
                           owner == "Dock",
                           let name = window[kCGWindowName as String] as? String,
                           name.starts(with: "Wallpaper-") {
                            
                            let uuid = String(name.dropFirst("Wallpaper-".count))
                            let finalUUID = uuid.isEmpty ? "MAIN" : uuid
                            visibleUUIDs.insert(finalUUID)
                            break
                        }
                    }
                }
            }
            completion(visibleUUIDs)
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
        
        let flippedY = NSMaxY(primaryScreen.frame) - point.y
        let flippedPoint = CGPoint(x: point.x, y: flippedY)
        
        return screenFrame.contains(flippedPoint)
    }
}
