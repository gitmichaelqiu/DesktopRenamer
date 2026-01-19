import Foundation
import AppKit
import CoreGraphics

// MARK: - CGS Private API Definitions (Read-Only)
// We retain these only for DETECTING spaces, not for switching.
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
    
    // MARK: - Space Switching Logic
    static func switchToSpace(_ spaceID: String) {
        // 1. Resolve Target Space Info
        // We need to look up the current Space Number because shortcuts are based on index (Space 1, Space 2...)
        var targetNum: Int? = nil
        if let state = getSystemState(),
           let targetSpace = state.spaces.first(where: { $0.id == spaceID }) {
            targetNum = targetSpace.num
        }
        
        // 2. PRIORITY: Simulate Keyboard Shortcut (Control + Number)
        // Since window activation can be visually disruptive (forcing window to front),
        // we prefer the native shortcut IF it is available/effective for this space number.
        if let num = targetNum {
            // CHECK: Verify if the system shortcut is actually enabled and matches our expectation (Ctrl+N)
            // If the user disabled the shortcut or changed it to something else (e.g. Option+N),
            // we skip the simulation to avoid doing nothing, and go straight to the fallback.
            if isShortcutEnabled(for: num) && simulateDesktopShortcut(for: num) {
                print("Switched using Shortcut (Method B)")
                return
            }
        }
        
        // 3. Fallback: Activate our own Space Label Window (Precise & Reliable)
        // Since we have a window on every desktop, activating the specific one
        // on the target space forces the OS to switch to it immediately.
        if switchByActivatingOwnWindow(for: spaceID) {
            print("Switched using Own Window (Method A1)")
            return
        }
    }
    
    private static func switchByActivatingOwnWindow(for spaceID: String) -> Bool {
        // Iterate through our own windows to find the SpaceLabelWindow on the target space.
        for window in NSApp.windows {
            // Check if this window is a SpaceLabelWindow and matches the target space ID.
            if let labelWindow = window as? SpaceLabelWindow, labelWindow.spaceId == spaceID {
                // Ensure the window is visible so the OS can switch to it
                if !labelWindow.isVisible {
                    labelWindow.orderFront(nil)
                }
                // Bringing it to front and key status triggers the space switch
                labelWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return true
            }
        }
        return false
    }
    
    /// Checks if the Mission Control shortcut for "Switch to Desktop N" is enabled and matches Control+N.
    private static func isShortcutEnabled(for number: Int) -> Bool {
        // Standard Symbolic HotKey IDs for Spaces 1-16 (Apple reserved range)
        // 118 -> Space 1
        // ...
        let baseID = 118
        let targetID = baseID + (number - 1)
        
        // Attempt to read the global domain for symbolic hotkeys
        guard let dict = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys"),
              let hotkeys = dict["AppleSymbolicHotKeys"] as? [String: Any] else {
            // If we can't read the domain (e.g. sandbox restriction), default to true
            // to attempt the shortcut rather than failing open to the more disruptive window-switch.
            return true
        }
        
        // If the entry is missing, macOS defaults usually apply (Enabled, Ctrl+N).
        guard let targetKeyDict = hotkeys[String(targetID)] as? [String: Any] else {
            return true
        }
        
        // 1. Check "enabled" boolean
        if let enabled = targetKeyDict["enabled"] as? Bool, !enabled {
            return false
        }
        
        // 2. Check "parameters" to ensure it matches Control (262144) + Correct KeyCode
        // If the user changed the mapping, our hardcoded simulation will fail anyway.
        if let value = targetKeyDict["value"] as? [String: Any],
           let parameters = value["parameters"] as? [Int],
           parameters.count >= 3 {
            
            let registeredKeyCode = parameters[1]
            let registeredModifiers = parameters[2]
            
            let expectedKeyCode = Int(getKeyCode(for: number))
            let expectedModifiers = 262144 // Control Key Mask
            
            if registeredKeyCode != expectedKeyCode || registeredModifiers != expectedModifiers {
                 return false
            }
        }
        
        return true
    }
    
    private static func getKeyCode(for number: Int) -> CGKeyCode {
        // Map space number to standard ANSI Key Codes for row numbers
        // 1=18, 2=19, 3=20, 4=21, 5=23, 6=22, 7=26, 8=28, 9=25, 0=29
        switch number {
        case 1: return 18
        case 2: return 19
        case 3: return 20
        case 4: return 21
        case 5: return 23
        case 6: return 22
        case 7: return 26
        case 8: return 28
        case 9: return 25
        case 10: return 29 // Often mapped to Desktop 10 or 0
        default: return 255 // Unknown/No shortcut
        }
    }

    /// Simulates the keyboard shortcut for switching desktops.
    /// Returns true if the shortcut was successfully posted (i.e., a valid keycode exists for this number).
    @discardableResult
    private static func simulateDesktopShortcut(for number: Int) -> Bool {
        let code = getKeyCode(for: number)
        if code == 255 {
            print("SpaceHelper: No standard hotkey available for Space \(number)")
            return false
        }
        
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Create Key Down/Up Events
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else {
            return false
        }
        
        // Apply Control Flag (Control + Number)
        keyDown.flags = .maskControl
        keyUp.flags = .maskControl
        
        // Post Events
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        
        return true
    }
    
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
