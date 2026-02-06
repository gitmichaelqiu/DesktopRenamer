import Foundation
import AppKit

// MARK: - CGS Private API Definitions
@_silgen_name("_CGSDefaultConnection") private func _CGSDefaultConnection() -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces") private func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> CFArray?
@_silgen_name("CGSCopyActiveMenuBarDisplayIdentifier") private func CGSCopyActiveMenuBarDisplayIdentifier(_ cid: Int32) -> CFString?

class SpaceHelper {
    static var fullscreenThreshold: Int {
        get { UserDefaults.standard.integer(forKey: "com.michaelqiu.desktoprenamer.fullscreenthreshold") }
        set { UserDefaults.standard.set(newValue, forKey: "com.michaelqiu.desktoprenamer.fullscreenthreshold") }
    }

    private static var onSpaceChange: ((String, Bool, Int, String) -> Void)?
    private static var globalEventMonitor: Any?
    private static var localEventMonitor: Any?
    
    static func startMonitoring(onChange: @escaping (String, Bool, Int, String) -> Void) {
        onSpaceChange = onChange
        
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in detectSpaceChange() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { _ in detectSpaceChange() }
        
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in detectSpaceChange() }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
             detectSpaceChange()
             return event
        }
        
        detectSpaceChange()
    }
    
    static func stopMonitoring() {
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let monitor = globalEventMonitor { NSEvent.removeMonitor(monitor); globalEventMonitor = nil }
        if let monitor = localEventMonitor { NSEvent.removeMonitor(monitor); localEventMonitor = nil }
    }
    
    // MARK: - Legacy Detection
    private static func getActiveDisplay() -> NSScreen? {
        if let frontApp = NSWorkspace.shared.frontmostApplication, frontApp.bundleIdentifier != "com.apple.finder" {
            let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
            let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
            
            for window in windowList {
                if let pid = window[kCGWindowOwnerPID as String] as? Int,
                   pid == frontApp.processIdentifier,
                   let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                   let bounds = window[kCGWindowBounds as String] as? [String: Any],
                   let x = bounds["X"] as? CGFloat, let y = bounds["Y"] as? CGFloat,
                   let w = bounds["Width"] as? CGFloat, let h = bounds["Height"] as? CGFloat {
                    let center = CGPoint(x: x + w/2, y: y + h/2)
                    for screen in NSScreen.screens { if isPoint(center, inside: screen.frame) { return screen } }
                }
            }
        }
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
    }
    
    static func getRawSpaceUUID(completion: @escaping (String, Bool, Int, String) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard let activeScreen = getActiveDisplay() else { completion("", false, 0, "Unknown"); return }
            let screenID = activeScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber ?? 0
            let displayIdentifier = "\(activeScreen.localizedName) (\(screenID))"
            
            let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
            let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
            
            var uuid = "", ncCnt = 0, hasFinderDesktop = false
            for window in windowList {
                guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                      let x = bounds["X"] as? CGFloat, let y = bounds["Y"] as? CGFloat,
                      let w = bounds["Width"] as? CGFloat, let h = bounds["Height"] as? CGFloat else { continue }
                
                if isPoint(CGPoint(x: x + w/2, y: y + h/2), inside: activeScreen.frame),
                   let owner = window[kCGWindowOwnerName as String] as? String {
                    if owner == "Dock", let name = window[kCGWindowName as String] as? String, name.starts(with: "Wallpaper-") {
                        uuid = String(name.dropFirst("Wallpaper-".count))
                        if uuid == "" { uuid = "MAIN" }
                    }
                    if owner == "Notification Center" { ncCnt += 1 }
                    if owner == "Finder", let layer = window[kCGWindowLayer as String] as? Int, layer < 0 { hasFinderDesktop = true }
                }
            }
            completion(uuid, hasFinderDesktop, ncCnt, displayIdentifier)
        }
    }
        
    static func getVisibleSpaceUUIDs(completion: @escaping (Set<String>) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
            let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
            let screens = NSScreen.screens
            var visibleUUIDs = Set<String>()

            if screens.isEmpty { completion([]); return }
            for screen in screens {
                for window in windowList {
                    guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                          let x = bounds["X"] as? CGFloat, let y = bounds["Y"] as? CGFloat,
                          let w = bounds["Width"] as? CGFloat, let h = bounds["Height"] as? CGFloat else { continue }
                    if isPoint(CGPoint(x: x + w/2, y: y + h/2), inside: screen.frame) {
                        if let owner = window[kCGWindowOwnerName as String] as? String, owner == "Dock",
                           let name = window[kCGWindowName as String] as? String, name.starts(with: "Wallpaper-") {
                            let uuid = String(name.dropFirst("Wallpaper-".count))
                            visibleUUIDs.insert(uuid.isEmpty ? "MAIN" : uuid)
                            break
                        }
                    }
                }
            }
            completion(visibleUUIDs)
        }
    }
    
    // MARK: - New CGS Methods
    static func getSystemState() -> (spaces: [DesktopSpace], currentUUID: String, displayID: String)? {
        let conn = _CGSDefaultConnection()
        guard let displays = CGSCopyManagedDisplaySpaces(conn) as? [NSDictionary] else { return nil }
        guard let activeDisplay = CGSCopyActiveMenuBarDisplayIdentifier(conn) as? String else { return nil }
        
        var detectedSpaces: [DesktopSpace] = []
        var currentSpaceID = "FULLSCREEN"
        
        let targetDisplayID = displays.contains { ($0["Display Identifier"] as? String) == activeDisplay }
            ? activeDisplay
            : (displays.first { ($0["Display Identifier"] as? String) == "Main" }?["Display Identifier"] as? String ?? activeDisplay)
        
        for display in displays {
            guard let displayID = display["Display Identifier"] as? String,
                  let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            
            var regularIndex = 0
            for space in spaces {
                guard let managedID = space["ManagedSpaceID"] as? Int else { continue }
                let idString = String(managedID)
                let isFullscreen = space["TileLayoutManager"] != nil
                
                if !isFullscreen {
                    regularIndex += 1
                    detectedSpaces.append(DesktopSpace(id: idString, customName: "", num: regularIndex, displayID: displayID))
                }
                
                if let currentDict = display["Current Space"] as? [String: Any],
                   let currentID = currentDict["ManagedSpaceID"] as? Int, currentID == managedID {
                    if displayID == targetDisplayID {
                        currentSpaceID = isFullscreen ? "FULLSCREEN" : idString
                    }
                }
            }
        }
        return (detectedSpaces, currentSpaceID, targetDisplayID)
    }
    
    static func getVisibleSystemSpaceIDs() -> Set<String> {
        let conn = _CGSDefaultConnection()
        guard let displays = CGSCopyManagedDisplaySpaces(conn) as? [NSDictionary] else { return [] }
        var visibleIDs = Set<String>()
        for display in displays {
            if let currentDict = display["Current Space"] as? [String: Any],
               let currentID = currentDict["ManagedSpaceID"] as? Int {
                visibleIDs.insert(String(currentID))
            }
        }
        return visibleIDs
    }
    
    static func detectSpaceChange() {
        getRawSpaceUUID { spaceUUID, isDesktop, ncCnt, displayID in
            onSpaceChange?(spaceUUID, isDesktop, ncCnt, displayID)
        }
    }

    static func isPoint(_ point: CGPoint, inside screenFrame: CGRect) -> Bool {
        guard let primaryScreen = NSScreen.screens.first(where: { $0.frame.origin.x == 0 && $0.frame.origin.y == 0 }) else {
            return screenFrame.contains(point)
        }
        let flippedY = NSMaxY(primaryScreen.frame) - point.y
        return screenFrame.contains(CGPoint(x: point.x, y: flippedY))
    }
}
